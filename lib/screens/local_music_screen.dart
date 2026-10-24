import 'dart:async';
import 'dart:math' as math;

import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';

import '../services/clove_notifications.dart';

import 'package:permission_handler/permission_handler.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../models/clove_track.dart';
import '../services/audio/playback_service.dart';
import '../services/local_audio_library.dart';
import '../widgets/juggle_icon_button.dart';
import '../widgets/local_artwork.dart';
import '../widgets/queue_swipe.dart';

class LocalMusicScreen extends StatefulWidget {
  const LocalMusicScreen({
    super.key,
    required this.library,
    required this.initialResult,
    this.trackFilter,
    this.onClose,
  });

  final LocalAudioLibrary library;
  final LocalAudioScanResult initialResult;
  final Iterable<CloveTrack> Function(Iterable<CloveTrack>)? trackFilter;
  final VoidCallback? onClose;

  @override
  State<LocalMusicScreen> createState() => _LocalMusicScreenState();
}

class _LocalMusicScreenState extends State<LocalMusicScreen>
    with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  late LocalAudioScanResult _result;
  bool _loading = false;
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();

  late final AnimationController _searchAnimationController;
  late final Animation<Offset> _searchSlideAnimation;
  static const double _searchBarHeight = 50;

  String _query = '';
  bool _searchVisible = false;
  bool _openingSearch = false;

  bool get _hasQuery => _query.trim().isNotEmpty;

  static const Color _obsidian = Color(0xFF0B0B0B);
  static const Color _inputSurface = Color(0xFF202020);
  static const Color _cloveMint = Color(0xFF1DE9B6);
  static const Color _mutedText = Color(0xFFB7B5BE);

  @override
  void initState() {
    super.initState();

    _result = _filterResult(widget.initialResult);

    WidgetsBinding.instance.addObserver(this);

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

  String _normalizeSearch(String value) {
    return value.toLowerCase().replaceAll(RegExp(r"[\s_\-']+"), '');
  }

  List<CloveTrack> _filteredTracks(List<CloveTrack> tracks) {
    final query = _normalizeSearch(_query);

    if (query.isEmpty) return tracks;

    return tracks.where((track) {
      return _normalizeSearch(track.title).contains(query) ||
          _normalizeSearch(track.artist).contains(query);
    }).toList();
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
    _searchFocusNode.requestFocus();
  }

  Future<void> _closeSearch() async {
    if (!_searchVisible) return;

    _searchFocusNode.unfocus();

    await _searchAnimationController.reverse();

    if (!mounted) return;

    _searchController.clear();

    setState(() {
      _query = '';
      _searchVisible = false;
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);

    _searchController.removeListener(_handleSearchChanged);
    _searchController.dispose();
    _searchFocusNode.dispose();
    _searchAnimationController.dispose();

    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && !_result.hasPermission) {
      _scan(requestPermission: false);
    }
  }

  Future<void> _scan({bool requestPermission = true}) async {
    if (_loading) return;
    setState(() => _loading = true);
    final result = _filterResult(
      await widget.library.scan(requestPermission: requestPermission),
    );
    if (!mounted) return;
    setState(() {
      _result = result;
      _loading = false;
    });
  }

  LocalAudioScanResult _filterResult(LocalAudioScanResult result) {
    final filter = widget.trackFilter;
    if (filter == null) return result;
    return LocalAudioScanResult(
      tracks: filter(result.tracks).toList(growable: false),
      permissionStatus: result.permissionStatus,
      error: result.error,
    );
  }

  Future<void> _play(int index) async {
    final tracks = _result.tracks;
    if (index < 0 || index >= tracks.length) return;
    try {
      await PlaybackService.playTracks(
        tracks,
        initialIndex: index,
        sourceId: PlaybackService.localMusicSourceId,
      );
    } catch (error, stackTrace) {
      debugPrint('CLOVE: Local music playback failed: $error');
      debugPrintStack(stackTrace: stackTrace);
      if (!mounted) return;
      CloveNotifications.show(
        context,
        const SnackBar(content: Text('Could not play this local audio file.')),
      );
    }
  }

  Future<void> _openSettings() async {
    final opened = await openAppSettings();
    if (!opened && mounted) {
      CloveNotifications.show(
        context,
        const SnackBar(content: Text('Could not open app settings.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final tracks = _result.tracks;
    return Scaffold(
      backgroundColor: const Color(0xFF0B0B0B),
      appBar: AppBar(
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
        elevation: 0,
        backgroundColor: const Color(0xFF0B0B0B),
        foregroundColor: Colors.white,
        centerTitle: true,

        // Explicit back button
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

        title: const Text(
          'Local Music',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),

        actions: [
          JuggleIconButton(
            tooltip: _searchVisible ? 'Close search' : 'Search songs',
            onPressed: () {
              if (_searchVisible) {
                unawaited(_closeSearch());
              } else {
                unawaited(_openSearch());
              }
            },
            size: 48,
            icon: _searchVisible
                ? const Icon(Icons.close_rounded, color: Colors.white, size: 26)
                : SvgPicture.asset(
                    'assets/icon/search.svg',
                    width: 18,
                    height: 18,
                    colorFilter: const ColorFilter.mode(
                      Colors.white,
                      BlendMode.srcIn,
                    ),
                  ),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Stack(
        children: [
          Positioned.fill(
            child: _loading && tracks.isEmpty
                ? const Center(
                    child: CircularProgressIndicator(color: _cloveMint),
                  )
                : !_result.hasPermission
                ? _permissionState()
                : _result.error != null && tracks.isEmpty
                ? _emptyState(
                    Icons.error_outline_rounded,
                    'Could not scan local music',
                    'Check that your audio files are available, then try again.',
                    action: 'Retry scan',
                    onAction: () => _scan(),
                  )
                : _filteredTracks(tracks).isEmpty
                ? _hasQuery
                      ? _emptySearch()
                      : _buildEmptyTracks()
                : _buildTrackList(_filteredTracks(tracks)),
          ),

          if (_searchVisible)
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

  Widget _permissionState() {
    final status = _result.permissionStatus;
    final restricted = status?.isRestricted ?? false;
    final settings = status?.isPermanentlyDenied ?? false;
    return _emptyState(
      Icons.folder_off_outlined,
      restricted ? 'Music access is restricted' : 'Music access is needed',
      restricted
          ? 'Check device restrictions or contact its administrator.'
          : settings
          ? 'Allow Clove to access music in Android app settings.'
          : 'Allow Clove to access audio on this device to scan local music.',
      action: settings || restricted ? 'Open app settings' : 'Allow access',
      onAction: settings || restricted
          ? _openSettings
          : () => _scan(requestPermission: true),
    );
  }

  Widget _searchField() {
    return TextField(
      controller: _searchController,
      focusNode: _searchFocusNode,
      onTapOutside: (_) => _searchFocusNode.unfocus(),
      autofocus: false,
      textInputAction: TextInputAction.search,
      style: const TextStyle(color: Colors.white, fontSize: 15),
      cursorColor: _cloveMint,
      decoration: InputDecoration(
        hintText: 'Search songs or artists',
        hintStyle: const TextStyle(color: _mutedText, fontSize: 14),
        prefixIcon: Padding(
          padding: const EdgeInsets.all(14),
          child: SvgPicture.asset(
            'assets/icon/search.svg',
            width: 16,
            height: 16,
            colorFilter: const ColorFilter.mode(_mutedText, BlendMode.srcIn),
          ),
        ),
        suffixIcon: _hasQuery
            ? JuggleIconButton(
                tooltip: 'Clear search',
                onPressed: _clearSearch,
                size: 40,
                icon: const Icon(
                  Icons.clear_rounded,
                  color: _mutedText,
                  size: 20,
                ),
              )
            : null,
        filled: true,
        fillColor: _inputSurface,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: _cloveMint, width: 1.5),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: _cloveMint, width: 1.5),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: _cloveMint, width: 1.5),
        ),
      ),
    );
  }

  Widget _emptySearch() {
    return Center(
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
    );
  }

  Widget _buildEmptyTracks() {
    return RefreshIndicator(
      color: _cloveMint,
      onRefresh: _scan,
      child: ListView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        physics: const AlwaysScrollableScrollPhysics(),
        children: const [
          SizedBox(height: 120),
          Icon(Icons.library_music_outlined, color: _mutedText, size: 54),
          SizedBox(height: 14),
          Text(
            'No local tracks found',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white,
              fontSize: 17,
              fontWeight: FontWeight.w700,
            ),
          ),
          SizedBox(height: 8),
          Text(
            'Add audio files to your device and scan again.',
            textAlign: TextAlign.center,
            style: TextStyle(color: _mutedText),
          ),
        ],
      ),
    );
  }

  Widget _buildTrackList(List<CloveTrack> visibleTracks) {
    return RefreshIndicator(
      color: _cloveMint,
      onRefresh: _scan,
      child: ListView.separated(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: EdgeInsets.fromLTRB(
          0,
          _searchVisible ? _searchBarHeight + 10 : 10,
          0,
          200,
        ),
        itemCount: visibleTracks.length,
        separatorBuilder: (_, _) => const SizedBox(height: 4),
        itemBuilder: (context, index) {
          final track = visibleTracks[index];

          return StreamBuilder<MediaItem?>(
            stream: PlaybackService.mediaItemStream,
            builder: (context, currentSnapshot) {
              return StreamBuilder<String?>(
                stream: PlaybackService.playbackSourceStream,
                initialData: PlaybackService.activeSourceId,
                builder: (context, sourceSnapshot) {
                  final current = isTrackActiveInPlaybackSource(
                    activeSourceId: sourceSnapshot.data,
                    expectedSourceId: PlaybackService.localMusicSourceId,
                    currentTrackId: trackIdFromMediaItem(currentSnapshot.data),
                    trackId: track.path,
                  );

                  return QueueSwipe(
                    successMessage: 'Added to queue',
                    onQueue: () async {
                      final originalIndex = _result.tracks.indexOf(track);

                      if (!PlaybackService.isPlaying) {
                        return PlaybackService.queueTracksOrStart(
                          [track],
                          sourceId: PlaybackService.localMusicSourceId,
                          sourcePositions: [originalIndex],
                        );
                      }

                      await PlaybackService.addTracksToQueue(
                        [track],
                        sourceId: PlaybackService.localMusicSourceId,
                        sourcePositions: [originalIndex],
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
                          onTap: () {
                            final originalIndex = _result.tracks.indexOf(track);
                            _play(originalIndex);
                          },
                          child: Padding(
                            padding: const EdgeInsets.only(
                              left: 14,
                              right: 14,
                              top: 7,
                              bottom: 7,
                            ),
                            child: Row(
                              children: [
                                LocalArtwork(
                                  track: track,
                                  size: 50,
                                  borderRadius: 13,
                                ),
                                const SizedBox(width: 13),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Row(
                                        children: [
                                          if (current) ...[
                                            const PlayingEqualizer(),
                                            const SizedBox(width: 8),
                                          ],
                                          Expanded(
                                            child: Text(
                                              track.title,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: TextStyle(
                                                color: current
                                                    ? _cloveMint
                                                    : Colors.white,
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
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                },
              );
            },
          );
        },
      ),
    );
  }

  Widget _emptyState(
    IconData icon,
    String title,
    String message, {
    required String action,
    required VoidCallback onAction,
  }) => Center(
    child: Padding(
      padding: const EdgeInsets.all(28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 54, color: const Color(0xFF1DE9B6)),
          const SizedBox(height: 16),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Color(0xFFB7B5BE), height: 1.5),
          ),
          const SizedBox(height: 18),
          FilledButton(
            onPressed: onAction,
            style: FilledButton.styleFrom(
              foregroundColor: const Color(0xFF0B0B0B),
              backgroundColor: const Color(0xFF1DE9B6),
            ),
            child: Text(action),
          ),
        ],
      ),
    ),
  );

  String _formatDuration(Duration duration) =>
      '${duration.inMinutes}:${duration.inSeconds.remainder(60).toString().padLeft(2, '0')}';
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
