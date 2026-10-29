import 'dart:async';
import 'dart:math' as math;

import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';

import '../services/clove_notifications.dart';

import 'package:flutter_svg/flutter_svg.dart';

import '../data/database.dart';
import '../models/clove_track.dart';
import '../services/audio/playback_service.dart';
import '../services/playlist_repository.dart';
import '../widgets/local_artwork.dart';
import '../widgets/queue_swipe.dart';
import '../widgets/juggle_icon_button.dart';
import '../widgets/playlist_artwork.dart';
import 'add_to_playlist_sheet.dart';

const Color _obsidian = Color(0xFF0B0B0B);
const Color _inputSurface = Color(0xFF202020);
const Color _cloveMint = Color(0xFF1DE9B6);
const Color _mutedText = Color(0xFFB7B5BE);

class PlaylistDetailScreen extends StatefulWidget {
  const PlaylistDetailScreen({
    super.key,
    required this.repository,
    this.playlistId,
    this.likedSongs = false,
    this.onClose,
  });

  final PlaylistRepository repository;
  final int? playlistId;
  final bool likedSongs;
  final VoidCallback? onClose;

  @override
  State<PlaylistDetailScreen> createState() => _PlaylistDetailScreenState();
}

class _PlaylistDetailScreenState extends State<PlaylistDetailScreen>
    with SingleTickerProviderStateMixin {
  final TextEditingController _searchController = TextEditingController();

  final FocusNode _searchFocusNode = FocusNode();

  String _normalizeSearch(String value) {
    return value.toLowerCase().replaceAll(RegExp(r"[\s_\-']+"), '');
  }

  late final AnimationController _searchAnimationController;

  late final Animation<Offset> _searchSlideAnimation;

  String _query = '';
  bool _searchVisible = false;
  bool _openingSearch = false;
  double _pullDistance = 0;
  Stream<UserPlaylist?>? _playlistStream;
  Stream<List<CloveTrack>>? _tracksStream;
  List<CloveTrack>? _queuePositionSource;
  Map<String, int> _queuePositions = const {};

  bool get _hasQuery => _query.trim().isNotEmpty;

  String get _playbackSourceId => widget.likedSongs
      ? PlaybackService.likedSongsSourceId
      : PlaybackService.playlistSourceId(widget.playlistId!);

  @override
  void initState() {
    super.initState();
    _bindPlaylistStreams();

    _searchAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 280),
      reverseDuration: const Duration(milliseconds: 220),
    );

    _searchSlideAnimation =
        Tween<Offset>(begin: const Offset(0, -1.2), end: Offset.zero).animate(
          CurvedAnimation(
            parent: _searchAnimationController,
            curve: Curves.easeOutCubic,
            reverseCurve: Curves.easeInCubic,
          ),
        );

    _searchController.addListener(_handleSearchChanged);
  }

  @override
  void didUpdateWidget(covariant PlaylistDetailScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.repository != widget.repository ||
        oldWidget.playlistId != widget.playlistId ||
        oldWidget.likedSongs != widget.likedSongs) {
      _bindPlaylistStreams();
    }
  }

  void _bindPlaylistStreams() {
    if (widget.likedSongs) {
      _playlistStream = null;
      _tracksStream = widget.repository.watchLikedTracks();
      return;
    }

    final id = widget.playlistId;
    if (id == null) {
      _playlistStream = null;
      _tracksStream = null;
      return;
    }

    _playlistStream = widget.repository.watchPlaylist(id);
    _tracksStream = widget.repository.watchPlaylistTracks(id);
  }

  @override
  void dispose() {
    _searchController.removeListener(_handleSearchChanged);
    _searchController.dispose();
    _searchFocusNode.dispose();
    _searchAnimationController.dispose();
    super.dispose();
  }

  void _handleSearchChanged() {
    if (!mounted) return;

    setState(() {
      _query = _searchController.text;
    });
  }

  void _clearSearch() {
    _searchController.clear();
    _searchFocusNode.requestFocus();
  }

  Future<void> _openSearch() async {
    if (_searchVisible || _openingSearch) return;

    _openingSearch = true;

    setState(() {
      _searchVisible = true;
    });

    await _searchAnimationController.forward();

    if (!mounted) return;

    _openingSearch = false;

    // Focus only after the search field has finished appearing.
    _searchFocusNode.requestFocus();
  }

  Future<void> _closeSearch() async {
    if (!_searchVisible) return;

    _searchFocusNode.unfocus();

    await _searchAnimationController.reverse();

    if (!mounted) return;

    setState(() {
      _searchVisible = false;
      _query = '';
      _pullDistance = 0;
    });

    _searchController.clear();
  }

  void _onScrollNotification(ScrollNotification notification) {
    if (_searchVisible || _openingSearch) return;

    // Pull down only when the list is already at its top.
    if (notification.metrics.pixels > 0) {
      _pullDistance = 0;
      return;
    }

    if (notification is OverscrollNotification && notification.overscroll < 0) {
      _pullDistance += -notification.overscroll;

      final threshold = MediaQuery.sizeOf(context).height * 0.20;

      if (_pullDistance >= threshold) {
        _pullDistance = 0;
        unawaited(_openSearch());
      }
    }

    if (notification is ScrollEndNotification) {
      _pullDistance = 0;
    }
  }

  List<CloveTrack> _filterTracks(List<CloveTrack> tracks) {
    final query = _normalizeSearch(_query);

    if (query.isEmpty) return tracks;

    return tracks.where((track) {
      final title = _normalizeSearch(track.title);
      final artist = _normalizeSearch(track.artist);

      return title.contains(query) || artist.contains(query);
    }).toList();
  }

  Map<String, int> _positionsFor(List<CloveTrack> tracks) {
    if (identical(_queuePositionSource, tracks)) return _queuePositions;

    final positions = <String, int>{};
    for (var index = 0; index < tracks.length; index++) {
      positions.putIfAbsent(tracks[index].path, () => index);
    }
    _queuePositionSource = tracks;
    _queuePositions = positions;
    return positions;
  }

  @override
  Widget build(BuildContext context) {
    if (widget.likedSongs) {
      return StreamBuilder<List<CloveTrack>>(
        stream: _tracksStream,
        builder: (context, snapshot) {
          return _buildPage(
            context,
            tracks: snapshot.data ?? const [],
            loading: !snapshot.hasData,
            error: snapshot.hasError,
            title: 'Liked Songs',
            artwork: const PlaylistArtwork(size: 250, likedSongs: true),
          );
        },
      );
    }

    final id = widget.playlistId;

    if (id == null) {
      return const Scaffold(
        backgroundColor: _obsidian,
        body: SizedBox.shrink(),
      );
    }

    return StreamBuilder<UserPlaylist?>(
      stream: _playlistStream,
      builder: (context, playlistSnapshot) {
        final playlist = playlistSnapshot.data;

        if (playlistSnapshot.hasData && playlist == null) {
          return Scaffold(
            backgroundColor: _obsidian,
            appBar: AppBar(
              backgroundColor: _obsidian,
              foregroundColor: Colors.white,
              elevation: 0,
            ),
            body: const Center(
              child: Text(
                'This playlist is no longer available.',
                style: TextStyle(color: _mutedText),
              ),
            ),
          );
        }

        return StreamBuilder<List<CloveTrack>>(
          stream: _tracksStream,
          builder: (context, tracksSnapshot) {
            return _buildPage(
              context,
              tracks: tracksSnapshot.data ?? const [],
              loading: !tracksSnapshot.hasData || playlist == null,
              error: tracksSnapshot.hasError || playlistSnapshot.hasError,
              title: playlist?.name ?? 'Playlist',
              artwork: PlaylistArtwork(
                size: 250,
                artworkPath: playlist?.artworkPath,
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildPage(
    BuildContext context, {
    required List<CloveTrack> tracks,
    required bool loading,
    required bool error,
    required String title,
    required Widget artwork,
  }) {
    final visibleTracks = _filterTracks(tracks);
    final queuePositions = _positionsFor(tracks);

    return Scaffold(
      backgroundColor: _obsidian,
      resizeToAvoidBottomInset: true,
      body: Stack(
        children: [
          // Main screen. Tapping outside the search panel closes it.
          GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTap: () {
              if (_searchVisible) {
                unawaited(_closeSearch());
              }
            },
            child: NotificationListener<ScrollNotification>(
              onNotification: (notification) {
                _onScrollNotification(notification);
                return false;
              },
              child: CustomScrollView(
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                slivers: [
                  SliverAppBar(
                    pinned: true,
                    backgroundColor: _obsidian,
                    foregroundColor: Colors.white,
                    scrolledUnderElevation: 0,
                    surfaceTintColor: Colors.transparent,
                    elevation: 0,
                    title: null,
                    toolbarHeight: 48,
                    collapsedHeight: 48,
                    expandedHeight: 0,
                    leading: JuggleIconButton(
                      tooltip: 'Go back',
                      onPressed: () {
                        if (widget.onClose case final onClose?) {
                          onClose();
                        } else {
                          Navigator.of(context).maybePop();
                        }
                      },
                      size: 48,
                      icon: const Icon(
                        Icons.arrow_back_ios_new_rounded,
                        color: Colors.white,
                        size: 22,
                      ),
                    ),
                    flexibleSpace: const SizedBox.shrink(),
                  ),

                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(24, 0, 24, 10),
                      child: Column(
                        children: [
                          Center(
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 240),
                              child: AspectRatio(
                                aspectRatio: 1,
                                child: artwork,
                              ),
                            ),
                          ),
                          const SizedBox(height: 22),
                          Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                              title,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 27,
                                height: 1.08,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                              'SHVNIX  ·  ${tracks.length} '
                              '${tracks.length == 1 ? 'song' : 'songs'}',
                              style: const TextStyle(
                                color: _mutedText,
                                fontSize: 13,
                              ),
                            ),
                          ),
                          const SizedBox(height: 18),
                          Row(
                            children: [
                              if (widget.likedSongs && tracks.isNotEmpty)
                                const Icon(
                                  Icons.favorite_rounded,
                                  color: _cloveMint,
                                  size: 26,
                                ),
                              const Spacer(),
                              // Shuffle button — changes color based on shuffle state
                              StreamBuilder<PlaybackState>(
                                stream: PlaybackService.playbackStateStream,
                                builder: (context, snapshot) {
                                  final shuffleOn =
                                      snapshot.data?.shuffleMode ==
                                      AudioServiceShuffleMode.all;

                                  return AnimatedContainer(
                                    duration: const Duration(milliseconds: 200),
                                    width: 48,
                                    height: 48,
                                    decoration: BoxDecoration(
                                      color: shuffleOn
                                          ? _cloveMint.withValues(alpha: 0.18)
                                          : _inputSurface,
                                      shape: BoxShape.circle,
                                    ),
                                    child: JuggleIconButton(
                                      tooltip: shuffleOn
                                          ? 'Turn shuffle off'
                                          : 'Turn shuffle on',
                                      onPressed: tracks.isEmpty
                                          ? null
                                          : () async {
                                              await PlaybackService.setShuffleEnabled(
                                                !shuffleOn,
                                              );
                                            },
                                      size: 48,
                                      icon: Icon(
                                        Icons.shuffle_rounded,
                                        color: shuffleOn
                                            ? _cloveMint
                                            : _mutedText,
                                        size: 24,
                                      ),
                                    ),
                                  );
                                },
                              ),

                              const SizedBox(width: 10),

                              // Play / Pause — same JuggleIconButton structure as Now Playing
                              StreamBuilder<String?>(
                                stream: PlaybackService.playbackSourceStream,
                                initialData: PlaybackService.activeSourceId,
                                builder: (context, sourceSnapshot) {
                                  return StreamBuilder<PlaybackState>(
                                    stream: PlaybackService.playbackStateStream,
                                    builder: (context, stateSnapshot) {
                                      final active =
                                          sourceSnapshot.data ==
                                          _playbackSourceId;

                                      final playing =
                                          active &&
                                          (stateSnapshot.data?.playing ??
                                              false);

                                      return JuggleIconButton(
                                        tooltip: playing
                                            ? 'Pause playlist'
                                            : 'Play playlist',
                                        size: 68,
                                        onPressed: tracks.isEmpty
                                            ? null
                                            : () => _togglePlaylistPlayback(
                                                context,
                                                tracks,
                                                active: active,
                                                playing: playing,
                                              ),
                                        icon: Container(
                                          width: 58,
                                          height: 58,
                                          decoration: const BoxDecoration(
                                            color: _cloveMint,
                                            shape: BoxShape.circle,
                                          ),
                                          child: Icon(
                                            playing
                                                ? Icons.pause_rounded
                                                : Icons.play_arrow_rounded,
                                            size: 34,
                                            color: _obsidian,
                                          ),
                                        ),
                                      );
                                    },
                                  );
                                },
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),

                  if (loading)
                    const SliverFillRemaining(
                      hasScrollBody: false,
                      child: Center(
                        child: CircularProgressIndicator(color: _cloveMint),
                      ),
                    )
                  else if (error)
                    const SliverFillRemaining(
                      hasScrollBody: false,
                      child: Center(
                        child: Text(
                          'Could not load this playlist.',
                          style: TextStyle(color: _mutedText),
                        ),
                      ),
                    )
                  else if (visibleTracks.isEmpty)
                    SliverFillRemaining(
                      hasScrollBody: false,
                      child: _hasQuery ? _emptySearch() : _emptyPlaylist(),
                    )
                  else
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(0, 6, 0, 200),
                      sliver: SliverList.separated(
                        itemCount: visibleTracks.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 2),
                        itemBuilder: (context, index) {
                          return _trackRow(
                            context,
                            tracks,
                            visibleTracks,
                            queuePositions,
                            index,
                          );
                        },
                      ),
                    ),
                ],
              ),
            ),
          ),

          // Search panel stays above the tap-detecting main screen.
          // Interactions inside this panel won't trigger the outside tap.
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SlideTransition(
              position: _searchSlideAnimation,
              child: Material(
                color: _obsidian,
                child: SafeArea(
                  bottom: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                    child: _searchField(),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _searchField() {
    return TextField(
      controller: _searchController,
      focusNode: _searchFocusNode,
      autofocus: false,
      textInputAction: TextInputAction.search,
      style: const TextStyle(color: Colors.white, fontSize: 15),
      cursorColor: _cloveMint,
      decoration: InputDecoration(
        hintText: 'Search songs or artists',
        hintStyle: const TextStyle(color: _mutedText, fontSize: 14),

        // Search icon
        prefixIcon: Padding(
          padding: const EdgeInsets.all(14),
          child: SvgPicture.asset(
            'assets/icon/search.svg',
            width: 16,
            height: 16,
            colorFilter: const ColorFilter.mode(_mutedText, BlendMode.srcIn),
          ),
        ),

        // Clear text button
        suffixIcon: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_hasQuery)
              JuggleIconButton(
                tooltip: 'Clear search',
                onPressed: _clearSearch,
                size: 40,
                icon: const Icon(
                  Icons.clear_rounded,
                  color: _mutedText,
                  size: 20,
                ),
              ),

            JuggleIconButton(
              tooltip: 'Close search',
              onPressed: () => unawaited(_closeSearch()),
              size: 44,
              icon: const Icon(
                Icons.close_rounded,
                color: _cloveMint,
                size: 24,
              ),
            ),
          ],
        ),

        filled: true,
        fillColor: _inputSurface,

        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),

        // Default border
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: _cloveMint, width: 1.5),
        ),

        // Border when not focused
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: _cloveMint, width: 1.5),
        ),

        // Border when focused
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: _cloveMint, width: 1.5),
        ),
      ),
    );
  }

  Widget _emptySearch() {
    return Transform.translate(
      offset: const Offset(0, -70),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.search_off_rounded, color: _cloveMint, size: 46),
              const SizedBox(height: 14),
              const Text(
                'No songs found',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 7),
              Text(
                'No matches for "${_query.trim()}".',
                textAlign: TextAlign.center,
                style: const TextStyle(color: _mutedText),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _trackRow(
    BuildContext context,
    List<CloveTrack> queueTracks,
    List<CloveTrack> visibleTracks,
    Map<String, int> queuePositions,
    int index,
  ) {
    final track = visibleTracks[index];
    final queueIndex = queuePositions[track.path] ?? -1;

    return StreamBuilder<String?>(
      stream: PlaybackService.playbackSourceStream,
      initialData: PlaybackService.activeSourceId,
      builder: (context, sourceSnapshot) => StreamBuilder<MediaItem?>(
        stream: PlaybackService.mediaItemStream,
        builder: (context, itemSnapshot) {
          final active = isTrackActiveInPlaybackSource(
            activeSourceId: sourceSnapshot.data,
            expectedSourceId: _playbackSourceId,
            currentTrackId: trackIdFromMediaItem(itemSnapshot.data),
            trackId: track.path,
          );
          return QueueSwipe(
            successMessage: 'Added to queue',
            onQueue: () async {
              if (!PlaybackService.isPlaying) {
                return PlaybackService.queueTracksOrStart(
                  [track],
                  sourceId: _playbackSourceId,
                  sourcePositions: [queueIndex],
                );
              }

              await PlaybackService.addTracksToQueue(
                [track],
                sourceId: _playbackSourceId,
                sourcePositions: [queueIndex],
                expandSourceContext: true,
              );

              return true;
            },
            child: Material(
              type: MaterialType.transparency,
              animationDuration: Duration.zero,
              child: Theme(
                data: Theme.of(context).copyWith(
                  splashFactory: NoSplash.splashFactory,
                  splashColor: Colors.transparent,
                  highlightColor: Colors.transparent,
                  hoverColor: Colors.transparent,
                  focusColor: Colors.transparent,
                ),
                child: InkWell(
                  onTap: queueIndex < 0
                      ? null
                      : () => _play(
                          context,
                          queueTracks,
                          index: queueIndex,
                          sourceId: _playbackSourceId,
                        ),
                  child: Padding(
                    padding: const EdgeInsets.only(
                      left: 14,
                      right: 14,
                      top: 7,
                      bottom: 7,
                    ),
                    child: Row(
                      children: [
                        // Same artwork as LocalMusicScreen
                        LocalArtwork(track: track, size: 50, borderRadius: 13),

                        const SizedBox(width: 13),

                        // Song title and artist
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Row(
                                children: [
                                  if (active) ...[
                                    const PlayingEqualizer(),
                                    const SizedBox(width: 8),
                                  ],
                                  Expanded(
                                    child: Text(
                                      track.title,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        color: active
                                            ? _cloveMint
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
                                      track.artist,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      softWrap: false,
                                      style: const TextStyle(
                                        color: _mutedText,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    _formatDuration(track.duration),
                                    maxLines: 1,
                                    softWrap: false,
                                    style: const TextStyle(
                                      color: _mutedText,
                                      fontSize: 12,
                                      fontFeatures: [
                                        FontFeature.tabularFigures(),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),

                        // Keep your existing three-dot menu
                        PopupMenuButton<String>(
                          color: _inputSurface,
                          icon: const Icon(
                            Icons.more_vert_rounded,
                            color: Colors.white70,
                          ),
                          onSelected: (action) async {
                            if (action == 'remove') {
                              if (widget.likedSongs) {
                                await widget.repository.setLiked(track, false);
                              } else if (widget.playlistId != null) {
                                await widget.repository.removeFromPlaylist(
                                  widget.playlistId!,
                                  track.path,
                                );
                              }
                            } else if (action == 'add') {
                              await showAddToPlaylistSheet(
                                context,
                                repository: widget.repository,
                                track: track,
                              );
                            } else if (action == 'like') {
                              await widget.repository.setLiked(track, true);
                            }
                          },
                          itemBuilder: (_) => [
                            PopupMenuItem(
                              value: 'remove',
                              child: Text(
                                widget.likedSongs
                                    ? 'Remove from Liked Songs'
                                    : 'Remove from playlist',
                              ),
                            ),
                            const PopupMenuItem(
                              value: 'add',
                              child: Text('Save to another playlist'),
                            ),
                            const PopupMenuItem(
                              value: 'like',
                              child: Text('Add to Liked Songs'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _emptyPlaylist() {
    return Transform.translate(
      offset: const Offset(0, -70), // Move content up by 70px
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.queue_music_rounded,
                color: _cloveMint,
                size: 48,
              ),
              const SizedBox(height: 14),
              const Text(
                'This playlist is empty',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 7),
              const Text(
                'Add tracks from the player or your local music.',
                textAlign: TextAlign.center,
                style: TextStyle(color: _mutedText),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _play(
    BuildContext context,
    List<CloveTrack> tracks, {
    int index = 0,
    bool shuffle = false,
    required String sourceId,
  }) async {
    try {
      if (shuffle) {
        await PlaybackService.setShuffleEnabled(true);
      }

      await PlaybackService.playTracks(
        tracks,
        initialIndex: index,
        sourceId: sourceId,
      );
    } catch (error, stackTrace) {
      debugPrint('CLOVE: Playlist playback failed: $error');
      debugPrintStack(stackTrace: stackTrace);

      if (!context.mounted) return;

      CloveNotifications.show(
        context,
        const SnackBar(
          content: Text('Could not play one or more saved audio files.'),
        ),
      );
    }
  }

  Future<void> _togglePlaylistPlayback(
    BuildContext context,
    List<CloveTrack> tracks, {
    required bool active,
    required bool playing,
  }) async {
    try {
      if (!active) {
        await _play(context, tracks, sourceId: _playbackSourceId);
      } else if (playing) {
        await PlaybackService.pause();
      } else {
        await PlaybackService.play();
      }
    } catch (error, stackTrace) {
      debugPrint('CLOVE: Playlist playback control failed: $error');
      debugPrintStack(stackTrace: stackTrace);
      if (!context.mounted) return;
      CloveNotifications.show(
        context,
        const SnackBar(content: Text('Could not control playlist playback.')),
      );
    }
  }
}

class PlayingEqualizer extends StatefulWidget {
  const PlayingEqualizer({super.key});

  @override
  State<PlayingEqualizer> createState() => _PlayingEqualizerState();
}

class _PlayingEqualizerState extends State<PlayingEqualizer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  // Change this to 1 or 2 to try another style.
  static const int style = 0;

  static const Color mint = Color(0xFF1DE9B6);

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 650),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<bool>(
      stream: PlaybackService.isPlayingStream,
      initialData: PlaybackService.isPlaying,
      builder: (context, snapshot) {
        final isPlaying = snapshot.data ?? false;

        if (isPlaying && !_controller.isAnimating) {
          _controller.repeat();
        } else if (!isPlaying && _controller.isAnimating) {
          _controller.stop();
        }

        final heights = switch (style) {
          1 => [18.0, 12.0, 18.0],
          2 => [10.0, 16.0, 22.0, 16.0, 10.0],
          _ => [10.0, 20.0, 14.0, 26.0, 17.0],
        };

        return SizedBox(
          width: style == 1 ? 12 : 16,
          height: 16,
          child: AnimatedBuilder(
            animation: _controller,
            builder: (context, child) {
              return Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: List.generate(heights.length, (index) {
                  final phase = (_controller.value + index * 0.19) % 1.0;
                  final wave = (0.5 + 0.5 * math.sin(phase * 2 * math.pi))
                      .clamp(0.0, 1.0);
                  final height = 5.0 + wave * (heights[index] - 5.0);

                  return Container(
                    width: 2,
                    height: height.clamp(3.0, 16.0),
                    decoration: BoxDecoration(
                      color: mint,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  );
                }),
              );
            },
          ),
        );
      },
    );
  }
}

String _formatDuration(Duration duration) =>
    '${duration.inMinutes}:${duration.inSeconds.remainder(60).toString().padLeft(2, '0')}';
