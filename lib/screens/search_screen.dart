import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:audio_service/audio_service.dart';

import '../models/clove_track.dart';
import '../models/online_music_track.dart';
import '../services/online_music_provider.dart';
import '../services/online_action_tracker.dart';
import '../services/online_music_provider_scope.dart';
import '../services/online_playback_bridge.dart';
import '../services/audio/playback_service.dart';
import '../services/audio/playback_queue.dart';
import '../services/clove_notifications.dart';
import '../data/database.dart';
import '../services/playlist_repository.dart';
import '../services/recent_online_tracks.dart';
import '../widgets/clove_mini_player.dart';
import '../widgets/juggle_icon_button.dart';
import '../widgets/queue_swipe.dart';
import 'add_to_playlist_sheet.dart';
import 'playlist_detail_screen.dart';

const Color _obsidian = Color(0xFF0B0B0B);
const Color _mint = Color(0xFF1DE9B6);
const Color _muted = Color(0xFFB7B5BE);
const Duration _searchRequestTimeout = Duration(seconds: 45);

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key, this.provider, this.initialQuery});

  final OnlineMusicProvider? provider;
  final String? initialQuery;

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _searchController = TextEditingController();
  final _searchFocusNode = FocusNode();
  Timer? _searchDebounce;
  late final _playlistRepository = PlaylistRepository(AppDatabase.instance);
  final _recentTrackStore = RecentOnlineTracks();
  List<OnlineMusicTrack> _recentTracks = const [];
  StreamSubscription<MediaItem?>? _playbackMediaSubscription;
  String? _lastPlaylistRecentKey;
  late OnlineMusicProvider _provider;
  final List<OnlineMusicTrack> _results = [];
  final _onlineActions = OnlineActionTracker.instance;
  String? _errorMessage;
  String _query = '';
  int _requestGeneration = 0;
  int _playRequestGeneration = 0;
  Future<void> _onlineQueueTail = Future<void>.value();
  bool _isLoading = false;
  final Map<String, Future<String?>> _offlinePathLookups = {};

  void _clearSearch() {
    _searchController.clear();
    _searchFocusNode.requestFocus();
  }

  @override
  void initState() {
    super.initState();
    final initialQuery = widget.initialQuery?.trim() ?? '';
    if (initialQuery.isNotEmpty) _searchController.text = initialQuery;
    _searchController.addListener(_handleQueryChanged);
    _onlineActions.addListener(_handleOnlineActionsChanged);
    _loadRecentTracks();
    _playbackMediaSubscription = PlaybackService.mediaItemStream.listen(
      (item) => unawaited(_recordPlaylistPlayback(item)),
      onError: (Object _) {},
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (initialQuery.isNotEmpty) {
        _submitQuery();
      } else {
        _searchFocusNode.requestFocus();
      }
    });
  }

  Future<void> _loadRecentTracks() async {
    final tracks = await _recentTrackStore.load();
    if (!mounted) return;
    setState(() => _recentTracks = tracks);
    unawaited(_cacheRecentArtwork(tracks));
  }

  Future<void> _recordPlaylistPlayback(MediaItem? item) async {
    final currentItem = item;
    if (currentItem == null ||
        currentItem.extras?['sourceType'] != 'playlist') {
      return;
    }
    final canonicalId = canonicalTrackIdFromMediaItem(currentItem);
    final sourcePage = Uri.tryParse(canonicalId ?? '');
    final videoId = _youtubeVideoId(sourcePage);
    if (videoId == null || sourcePage == null) return;

    final trackKey = 'youtube:$videoId';
    if (_lastPlaylistRecentKey == trackKey) return;
    _lastPlaylistRecentKey = trackKey;

    try {
      final updated = await _recentTrackStore.record(
        OnlineMusicTrack(
          providerId: 'youtube',
          id: videoId,
          title: currentItem.title,
          artist: currentItem.artist,
          album: currentItem.album,
          artworkUri: currentItem.artUri,
          sourcePageUri: sourcePage,
          duration: currentItem.duration,
        ),
        moveToTop: false,
      );
      if (mounted) setState(() => _recentTracks = updated);
    } catch (_) {
      // A recents write failure should not affect playlist playback.
    }
  }

  String? _youtubeVideoId(Uri? uri) {
    if (uri == null) return null;
    final host = uri.host.toLowerCase();
    if (host == 'youtu.be' && uri.pathSegments.isNotEmpty) {
      return uri.pathSegments.first;
    }
    if (host == 'youtube.com' || host.endsWith('.youtube.com')) {
      final queryId = uri.queryParameters['v'];
      if (queryId != null && queryId.isNotEmpty) return queryId;
      final segments = uri.pathSegments;
      if (segments.length >= 2 &&
          {'shorts', 'live', 'embed'}.contains(segments.first)) {
        return segments[1];
      }
    }
    return null;
  }

  Future<void> _cacheRecentArtwork(List<OnlineMusicTrack> tracks) async {
    var nextIndex = 0;
    Future<void> worker() async {
      while (nextIndex < tracks.length) {
        final track = tracks[nextIndex++];
        if (track.artworkUri == null || track.artworkUri!.scheme == 'file') {
          continue;
        }
        try {
          final localized = await _recentTrackStore.cacheArtwork(track);
          if (!mounted || localized.artworkUri == track.artworkUri) continue;
          final key = '${track.providerId}:${track.id}';
          if (!_recentTracks.any(
            (item) => '${item.providerId}:${item.id}' == key,
          )) {
            continue;
          }
          setState(() {
            _recentTracks = _recentTracks
                .map(
                  (item) =>
                      '${item.providerId}:${item.id}' == key ? localized : item,
                )
                .toList(growable: false);
          });
        } catch (_) {
          // A missing network image should not prevent Search from opening.
        }
      }
    }

    await Future.wait(List.generate(3, (_) => worker()));
  }

  Future<void> _removeRecentTrack(OnlineMusicTrack track) async {
    final tracks = await _recentTrackStore.remove(track);
    if (!mounted) return;
    setState(() => _recentTracks = tracks);
  }

  Future<Uri?> _recordRecentTrack(
    OnlineMusicTrack track, {
    bool moveToTop = true,
  }) async {
    final tracks = await _recentTrackStore.record(track, moveToTop: moveToTop);
    if (mounted) setState(() => _recentTracks = tracks);
    return tracks
        .where(
          (item) => item.providerId == track.providerId && item.id == track.id,
        )
        .firstOrNull
        ?.artworkUri;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _provider = widget.provider ?? OnlineMusicProviderScope.of(context);
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _onlineActions.removeListener(_handleOnlineActionsChanged);
    unawaited(_playbackMediaSubscription?.cancel());
    _searchController
      ..removeListener(_handleQueryChanged)
      ..dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  void _handleOnlineActionsChanged() {
    if (mounted) setState(() {});
  }

  void _handleQueryChanged() {
    _searchDebounce?.cancel();
    ++_requestGeneration;
    final query = _searchController.text.trim();
    setState(() {
      _query = query;
      _errorMessage = null;
      // Keep the previous result list while the new query is debounced and
      // fetched. The body shows a loader during this transition instead of
      // briefly claiming that the query has no matches.
      _isLoading = query.isNotEmpty;
    });

    if (query.isNotEmpty) {
      _searchDebounce = Timer(const Duration(milliseconds: 500), () {
        if (mounted && query == _searchController.text.trim()) {
          _submitQuery();
        }
      });
    }
  }

  void _submitQuery() {
    _searchDebounce?.cancel();
    _searchDebounce = null;
    final query = _searchController.text.trim();
    if (query.isEmpty) return;
    final generation = ++_requestGeneration;
    setState(() {
      _query = query;
      _errorMessage = null;
      _isLoading = true;
    });
    _loadFirstPage(query, generation);
  }

  Future<void> _loadFirstPage(String query, int generation) async {
    if (!mounted || generation != _requestGeneration) return;
    setState(() {
      _isLoading = true;
    });
    try {
      // Some provider fallbacks (notably Android metadata lookup) can stall
      // without completing. Keep a broken request from leaving Search in its
      // loading state forever, including when the screen is reopened.
      final page = await _provider.search(query).timeout(_searchRequestTimeout);
      if (!mounted || generation != _requestGeneration) return;
      setState(() {
        _results
          ..clear()
          ..addAll(page.tracks);
        _isLoading = false;
      });
    } catch (error) {
      if (!mounted || generation != _requestGeneration) return;
      setState(() {
        _isLoading = false;
        _errorMessage = _providerErrorMessage(error);
      });
    }
  }

  Future<bool> _queueOnlineTrack(OnlineMusicTrack track) {
    final trackKey = '${track.providerId}:${track.id}';
    _onlineActions.beginQueueing(trackKey);
    final queued = _onlineQueueTail.then((_) async {
      final source = await _provider.resolvePlaybackSource(track);
      final playableSource = await _usablePlaybackSource(track, source);
      return PlaybackService.queueTracksOrStart([
        cloveTrackFromOnlineSource(track, playableSource),
      ], sourceId: 'online_youtube');
    });
    final result = queued.whenComplete(() {
      _offlinePathLookups.remove(trackKey);
      _onlineActions.finishQueueing(trackKey);
    });
    _onlineQueueTail = result.then<void>((_) {}).catchError((Object _) {});
    return result;
  }

  Future<bool> _likeOnlineTrack(OnlineMusicTrack track) async {
    final trackKey = '${track.providerId}:${track.id}';
    if (_onlineActions.isQueueing(trackKey)) return false;
    _onlineActions.beginQueueing(trackKey);
    try {
      final saving = _onlineQueueTail.then((_) => _downloadOfflineTrack(track));
      _onlineQueueTail = saving.then<void>((_) {}).catchError((Object _) {});
      final offlineTrack = await saving;
      _offlinePathLookups[trackKey] = Future.value(offlineTrack.path);
      await _playlistRepository.setLiked(offlineTrack, true);
      return true;
    } finally {
      _onlineActions.finishQueueing(trackKey);
    }
  }

  Future<void> _queueOnlineTrackFromIcon(OnlineMusicTrack track) async {
    final trackKey = '${track.providerId}:${track.id}';
    if (_onlineActions.isQueueing(trackKey)) return;
    _onlineActions.beginQueueing(trackKey);
    try {
      final saving = _onlineQueueTail.then((_) => _downloadOfflineTrack(track));
      _onlineQueueTail = saving.then<void>((_) {}).catchError((Object _) {});
      final offlineTrack = await saving;
      _offlinePathLookups[trackKey] = Future.value(offlineTrack.path);
      if (!mounted) return;
      await showAddToPlaylistSheet(
        context,
        repository: _playlistRepository,
        track: offlineTrack,
      );
    } catch (error) {
      if (mounted) _showPlaybackError(_playbackErrorMessage(error));
    } finally {
      _onlineActions.finishQueueing(trackKey);
    }
  }

  Future<CloveTrack> _downloadOfflineTrack(OnlineMusicTrack track) async {
    final provider = _provider;
    if (provider is! OfflineMusicDownloader) {
      throw const OnlineMusicProviderFailure(
        kind: OnlineMusicFailureKind.sourceResolutionFailed,
        message: 'Offline downloads are not supported by this provider.',
      );
    }
    final source = await (provider as OfflineMusicDownloader)
        .downloadForOffline(track);
    final audioFile = File.fromUri(source.uri);
    if (!await audioFile.exists()) {
      throw const OnlineMusicProviderFailure(
        kind: OnlineMusicFailureKind.sourceResolutionFailed,
        message: 'The downloaded song could not be found.',
      );
    }
    return CloveTrack(
      path: audioFile.path,
      title: track.title,
      artist: track.artist ?? track.creatorName ?? 'Unknown artist',
      album: track.album ?? '',
      duration: track.duration ?? Duration.zero,
      artworkUri: track.artworkUri,
      mediaId: track.sourcePage.toString(),
    );
  }

  Future<String?> _offlinePathFor(OnlineMusicTrack track) {
    final key = '${track.providerId}:${track.id}';
    return _offlinePathLookups.putIfAbsent(key, () async {
      final provider = _provider;
      if (provider is! OfflineMusicDownloader) return null;
      return (provider as OfflineMusicDownloader).findOfflineAudioPath(track);
    });
  }

  Future<void> _openTrack(
    OnlineMusicTrack track, {
    bool fromRecents = false,
  }) async {
    final requestGeneration = ++_playRequestGeneration;
    final trackKey = '${track.providerId}:${track.id}';
    _onlineActions.beginOpening(trackKey);
    try {
      final source = await _provider.resolvePlaybackSource(track);
      if (requestGeneration != _playRequestGeneration) return;
      final playableSource = await _usablePlaybackSource(track, source);
      if (requestGeneration != _playRequestGeneration) return;
      final sourceId = fromRecents ? searchRecentsSourceId : 'online_youtube';
      await _startOnlinePlayback(
        track,
        playableSource,
        requestGeneration,
        sourceId: sourceId,
      );
      Uri? offlineArtworkUri;
      if (fromRecents) {
        // Playing a recent item must not reorder the Recents list. Its stored
        // position remains stable while the complete recent queue is loaded.
        offlineArtworkUri = await _recordRecentTrack(track, moveToTop: false);
      } else {
        // A song launched from normal Search becomes the newest recent item.
        offlineArtworkUri = await _recordRecentTrack(track, moveToTop: true);
      }
      if (offlineArtworkUri?.scheme == 'file') {
        await PlaybackService.updateCurrentTrackArtwork(
          track.sourcePage.toString(),
          offlineArtworkUri!,
        );
      }
      if (fromRecents && requestGeneration == _playRequestGeneration) {
        await _queueRemainingRecents(track, requestGeneration);
      }
    } catch (error) {
      if (!mounted || requestGeneration != _playRequestGeneration) return;
      _showPlaybackError(_playbackErrorMessage(error));
    } finally {
      _onlineActions.finishOpening(trackKey);
    }
  }

  Future<void> _queueRemainingRecents(
    OnlineMusicTrack selected,
    int requestGeneration,
  ) async {
    final selectedKey = '${selected.providerId}:${selected.id}';
    final remaining = _recentTracks
        .where((track) => '${track.providerId}:${track.id}' != selectedKey)
        .toList(growable: false);
    if (remaining.isEmpty) return;

    final queue = <CloveTrack>[];
    for (final track in remaining) {
      if (requestGeneration != _playRequestGeneration) return;
      try {
        final source = await _provider.resolvePlaybackSource(track);
        final playableSource = await _usablePlaybackSource(track, source);
        queue.add(cloveTrackFromOnlineSource(track, playableSource));
      } catch (_) {
        // An unavailable old recent should not interrupt the selected song.
      }
    }
    if (queue.isNotEmpty && requestGeneration == _playRequestGeneration) {
      await PlaybackService.addTracksToQueue(
        queue,
        sourceId: searchRecentsSourceId,
      );
    }
  }

  Future<DirectAudioSource> _usablePlaybackSource(
    OnlineMusicTrack track,
    DirectAudioSource source,
  ) async {
    var resolved = source;
    final refreshBefore = DateTime.now().add(const Duration(seconds: 15));
    if (resolved.expiresAt != null &&
        !resolved.expiresAt!.isAfter(refreshBefore)) {
      resolved = await _provider.refreshPlaybackSource(track);
    }
    if (resolved.expiresAt != null &&
        !resolved.expiresAt!.isAfter(DateTime.now())) {
      return _provider.refreshPlaybackSource(track);
    }
    return resolved;
  }

  Future<void> _startOnlinePlayback(
    OnlineMusicTrack track,
    DirectAudioSource source,
    int requestGeneration, {
    required String sourceId,
  }) async {
    Future<void> start(DirectAudioSource resolved) =>
        PlaybackService.startTracks(
          [cloveTrackFromOnlineSource(track, resolved)],
          sourceId: sourceId,
          // YouTube stream URLs can require headers supplied by an extractor.
          shouldStart: () => requestGeneration == _playRequestGeneration,
          onPlaybackError: (error, _) {
            if (mounted && requestGeneration == _playRequestGeneration) {
              unawaited(
                _refreshAfterPlaybackError(
                  track,
                  resolved,
                  requestGeneration,
                  sourceId: sourceId,
                ),
              );
            }
          },
        );

    try {
      await start(source);
    } catch (startError) {
      if (source.isAppManagedFile ||
          source.expiresAt == null ||
          requestGeneration != _playRequestGeneration) {
        rethrow;
      }
      try {
        final refreshed = await _usablePlaybackSource(
          track,
          await _provider.refreshPlaybackSource(track),
        );
        await start(refreshed);
      } catch (refreshError) {
        throw OnlineMusicProviderFailure(
          kind: OnlineMusicFailureKind.sourceResolutionFailed,
          message: _playbackErrorMessage(
            refreshError is OnlineMusicProviderFailure
                ? refreshError
                : startError,
          ),
        );
      }
    }
  }

  Future<void> _refreshAfterPlaybackError(
    OnlineMusicTrack track,
    DirectAudioSource previous,
    int requestGeneration, {
    required String sourceId,
  }) async {
    if (requestGeneration != _playRequestGeneration) return;
    if (previous.isAppManagedFile) {
      _showPlaybackError(
        'Audio playback failed. Try selecting the song again.',
      );
      return;
    }
    try {
      final fresh = await _provider.refreshPlaybackSource(track);
      if (requestGeneration != _playRequestGeneration) return;
      await PlaybackService.startTracks(
        [cloveTrackFromOnlineSource(track, fresh)],
        sourceId: sourceId,
        shouldStart: () => requestGeneration == _playRequestGeneration,
        onPlaybackError: (error, _) {
          if (mounted && requestGeneration == _playRequestGeneration) {
            _showPlaybackError(_playbackErrorMessage(error));
          }
        },
      );
    } catch (error) {
      if (mounted && requestGeneration == _playRequestGeneration) {
        _showPlaybackError(_playbackErrorMessage(error));
      }
    }
  }

  String _playbackErrorMessage(Object error) =>
      error is OnlineMusicProviderFailure
      ? error.message
      : 'Could not start this song. Check the audio source and try again.';

  void _showPlaybackError(String message) {
    CloveNotifications.show(
      context,
      SnackBar(content: Text(message), duration: const Duration(seconds: 4)),
    );
  }

  String _providerErrorMessage(Object error) =>
      error is OnlineMusicProviderFailure
      ? error.message
      : 'Music search could not be completed. Please try again.';

  @override
  Widget build(BuildContext context) {
    return PopScope(
      child: Scaffold(
        backgroundColor: _obsidian,
        extendBody: true,
        body: Stack(
          children: [
            // Search content fills the screen behind the controls.
            Positioned.fill(
              child: SafeArea(bottom: false, child: _buildBody()),
            ),

            // Mini-player and search navigation float above the content.
            Positioned.fill(
              child: IgnorePointer(
                child: ColoredBox(color: Colors.transparent),
              ),
            ),

            Positioned.fill(
              child: Align(
                alignment: Alignment.bottomCenter,
                child: _buildShellControls(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildShellControls() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: CloveMiniPlayer(
            playlistRepository: _playlistRepository,
            // MainShell owns the persistent notification anchor.
            notificationAnchor: false,
          ),
        ),
        const SizedBox(height: 6),
        Padding(
          padding: const EdgeInsets.only(left: 18, right: 18, bottom: 6),
          child: _buildSearchNavigation(),
        ),
      ],
    );
  }

  Widget _buildSearchNavigation() {
    return SafeArea(
      top: false,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Main search pill — same style as bottom navigation
          Expanded(
            child: Container(
              height: 68,
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: _obsidian,
                borderRadius: BorderRadius.circular(50),
                border: Border.all(color: Colors.white.withValues(alpha: 0.25)),
              ),
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _searchController,
                          focusNode: _searchFocusNode,
                          onTapOutside: (_) => _searchFocusNode.unfocus(),
                          textInputAction: TextInputAction.search,
                          onSubmitted: (_) => _submitQuery(),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                          ),
                          cursorColor: _mint,
                          decoration: InputDecoration(
                            hintText: 'What would you like to play?',
                            hintStyle: TextStyle(color: Colors.white38),
                            border: InputBorder.none,
                            enabledBorder: InputBorder.none,
                            focusedBorder: InputBorder.none,
                            disabledBorder: InputBorder.none,
                            errorBorder: InputBorder.none,
                            focusedErrorBorder: InputBorder.none,
                            filled: false,
                            isDense: true,
                            suffixIcon: _query.isNotEmpty
                                ? JuggleIconButton(
                                    tooltip: 'Clear search',
                                    onPressed: _clearSearch,
                                    size: 40,
                                    icon: const Icon(
                                      Icons.clear_rounded,
                                      color: Colors.white38,
                                      size: 24,
                                    ),
                                  )
                                : null,
                            contentPadding: EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 12,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),

          const SizedBox(width: 8),

          // Circular close button — same style as search navigation
          Material(
            color: _obsidian,
            shape: const CircleBorder(),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: () => Navigator.of(context).pop(),
              child: Container(
                width: 68,
                height: 68,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.25),
                  ),
                ),
                child: const Center(
                  child: Icon(
                    Icons.close_rounded,
                    color: Color(0xFF8E8D95),
                    size: 32,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    final showingRecents = _query.isEmpty;
    final displayedTracks = showingRecents ? _recentTracks : _results;
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator(color: _mint));
    }
    if (_errorMessage != null && _results.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.wifi_off_rounded, color: _muted, size: 36),
              const SizedBox(height: 12),
              Text(
                _errorMessage!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: _muted),
              ),
              const SizedBox(height: 12),
              TextButton.icon(
                onPressed: _submitQuery,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Try again'),
              ),
            ],
          ),
        ),
      );
    }
    if (!showingRecents && _results.isEmpty) {
      return const Center(
        child: Text('No matching results', style: TextStyle(color: _muted)),
      );
    }
    if (displayedTracks.isEmpty) {
      return const Center(
        child: Text('No recent songs', style: TextStyle(color: _muted)),
      );
    }

    return ListView.separated(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: const EdgeInsets.only(top: 6, bottom: 200),

      itemCount: displayedTracks.length + (showingRecents ? 1 : 0),

      separatorBuilder: (_, _) => const SizedBox(height: 2),

      itemBuilder: (context, index) {
        if (showingRecents && index == 0) {
          return const Padding(
            padding: EdgeInsets.fromLTRB(16, 12, 16, 10),
            child: Text(
              'Recents',
              style: TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
          );
        }

        final result = displayedTracks[showingRecents ? index - 1 : index];
        final artworkUri = result.artworkUri;
        final resultKey = '${result.providerId}:${result.id}';
        final isOpening = _onlineActions.isOpening(resultKey);
        final isQueueing = _onlineActions.isQueueing(resultKey);

        return StreamBuilder<MediaItem?>(
          stream: PlaybackService.mediaItemStream,
          builder: (context, itemSnapshot) {
            final currentItem = itemSnapshot.data;
            final trackUrl = result.sourcePage.toString();
            final active =
                trackIdFromMediaItem(currentItem) == trackUrl ||
                canonicalTrackIdFromMediaItem(currentItem) == trackUrl;

            return QueueSwipe(
              successMessage: 'Added to queue',
              onSwipeLeft: () => _likeOnlineTrack(result),
              onQueue: () => _queueOnlineTrack(result),
              child: Material(
                type: MaterialType.transparency,
                child: InkWell(
                  onTap: isOpening || isQueueing
                      ? null
                      : () => _openTrack(result, fromRecents: showingRecents),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 7,
                    ),
                    child: Row(
                      children: [
                        // Square artwork, matching PlaylistDetailScreen.
                        ClipRRect(
                          borderRadius: BorderRadius.circular(13),
                          child: SizedBox(
                            width: 50,
                            height: 50,
                            child: Transform.scale(
                              scale: 1.4, // Increase this to zoom in more
                              child: artworkUri?.scheme == 'file'
                                  ? Image.file(
                                      File.fromUri(artworkUri!),
                                      width: 50,
                                      height: 50,
                                      fit: BoxFit.cover,
                                      errorBuilder: (_, _, _) => Container(
                                        color: const Color(0xFF202020),
                                        alignment: Alignment.center,
                                        child: const Icon(
                                          Icons.music_note_rounded,
                                          color: _muted,
                                        ),
                                      ),
                                    )
                                  : Image.network(
                                      artworkUri?.toString() ?? '',
                                      width: 50,
                                      height: 50,
                                      fit: BoxFit.cover,
                                      errorBuilder: (_, _, _) => Container(
                                        color: const Color(0xFF202020),
                                        alignment: Alignment.center,
                                        child: const Icon(
                                          Icons.music_note_rounded,
                                          color: _muted,
                                        ),
                                      ),
                                    ),
                            ),
                          ),
                        ),

                        const SizedBox(width: 13),

                        // Song title, artist, and duration.
                        Expanded(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  if (active) ...[
                                    const PlayingEqualizer(),
                                    const SizedBox(width: 8),
                                  ],
                                  Expanded(
                                    child: Text(
                                      result.title,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        color: active
                                            ? _mint
                                            : const Color(0xFFE0E0E0),
                                        fontWeight: FontWeight.w700,
                                        fontSize: 15,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      result.artist ??
                                          result.creatorName ??
                                          'Unknown artist',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      softWrap: false,
                                      style: const TextStyle(
                                        color: _muted,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ),
                                  if (result.duration case final duration?) ...[
                                    const SizedBox(width: 8),
                                    Text(
                                      _formatDuration(duration),
                                      style: const TextStyle(
                                        color: _muted,
                                        fontSize: 12,
                                        fontFeatures: [
                                          FontFeature.tabularFigures(),
                                        ],
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ],
                          ),
                        ),

                        const SizedBox(width: 8),
                        _searchSaveButton(result, isOpening || isQueueing),

                        if (showingRecents)
                          JuggleIconButton(
                            tooltip: 'Remove from recents',
                            size: 40,
                            onPressed: () => _removeRecentTrack(result),
                            icon: const Icon(
                              Icons.close_rounded,
                              color: _muted,
                              size: 23,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _searchSaveButton(OnlineMusicTrack track, bool busy) {
    if (busy) {
      return const SizedBox(
        width: 40,
        height: 40,
        child: Center(
          child: SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(color: _mint, strokeWidth: 2),
          ),
        ),
      );
    }

    Widget button({required bool isSaved}) => JuggleIconButton(
      tooltip: isSaved ? 'Saved to playlists' : 'Add to playlists',
      size: 40,
      onPressed: () => _queueOnlineTrackFromIcon(track),
      icon: Icon(
        isSaved ? Icons.check_circle_rounded : Icons.add_circle_outline_rounded,
        color: isSaved ? _mint : _muted,
        size: 20,
      ),
    );

    return FutureBuilder<String?>(
      future: _offlinePathFor(track),
      builder: (context, pathSnapshot) {
        final path = pathSnapshot.data;
        if (path == null) return button(isSaved: false);
        return StreamBuilder<TrackCollections>(
          stream: _playlistRepository.watchCollections(
            path,
            canonicalId: track.sourcePage.toString(),
          ),
          builder: (context, collectionsSnapshot) {
            final collections = collectionsSnapshot.data;
            final isSaved =
                collections != null &&
                (collections.isLiked || collections.playlistIds.isNotEmpty);
            return button(isSaved: isSaved);
          },
        );
      },
    );
  }

  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }
}
