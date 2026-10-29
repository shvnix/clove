import 'package:audio_service/audio_service.dart';

import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'playlist_detail_screen.dart';
import 'add_to_playlist_sheet.dart';
import '../models/clove_track.dart';
import '../services/audio/playback_service.dart';
import '../services/audio/player_formatters.dart';
import '../services/audio/playback_queue.dart';
import '../widgets/marquee_text.dart';
import '../widgets/local_artwork.dart';
import '../widgets/juggle_icon_button.dart';
import '../data/database.dart';
import '../services/playlist_repository.dart';

const Color _cloveMint = Color(0xFF1DE9B6);
const Color _muted = Color(0xFFAAA9B1);

class NowPlayingScreen extends StatefulWidget {
  const NowPlayingScreen({super.key});

  @override
  State<NowPlayingScreen> createState() => _NowPlayingScreenState();
}

class _NowPlayingScreenState extends State<NowPlayingScreen>
    with TickerProviderStateMixin {
  Duration? _scrubPosition;
  bool _scrubbing = false;
  final PlaylistRepository _playlistRepository = PlaylistRepository(
    AppDatabase.instance,
  );

  double _dragOffset = 0;

  late final AnimationController _settleController;

  Animation<double> _offsetAnimation = const AlwaysStoppedAnimation<double>(0);

  @override
  void initState() {
    super.initState();

    _settleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
    );

    _settleController.addListener(() {
      if (!mounted) return;

      setState(() {
        _dragOffset = _offsetAnimation.value;
      });
    });
  }

  Future<void> _settleDrag({
    required bool dismiss,
    required double screenHeight,
  }) async {
    _offsetAnimation =
        Tween<double>(
          begin: _dragOffset,
          end: dismiss ? screenHeight : 0,
        ).animate(
          CurvedAnimation(
            parent: _settleController,
            curve: Curves.easeOutCubic,
          ),
        );

    await _settleController.forward(from: 0);

    if (dismiss && mounted) {
      Navigator.of(context).maybePop();
    }
  }

  @override
  void dispose() {
    _settleController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.sizeOf(context).height;
    final progress = (_dragOffset / screenHeight).clamp(0.0, 1.0);
    final radius = 28.0 * progress;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Black overlay over the previous screen.
          IgnorePointer(
            child: ColoredBox(
              color: Colors.black.withValues(alpha: 0.90 * (1.0 - progress)),
            ),
          ),

          // Draggable ticket-style player.
          GestureDetector(
            behavior: HitTestBehavior.translucent,
            onVerticalDragStart: (_) {
              _settleController.stop();
            },
            onVerticalDragUpdate: (details) {
              setState(() {
                _dragOffset = (_dragOffset + details.delta.dy).clamp(
                  0.0,
                  screenHeight,
                );
              });
            },
            onVerticalDragEnd: (details) {
              if (_dragOffset >= screenHeight * 0.05) {
                _settleDrag(dismiss: true, screenHeight: screenHeight);
              } else {
                _settleDrag(dismiss: false, screenHeight: screenHeight);
              }
            },
            child: Transform.translate(
              offset: Offset(0, _dragOffset),
              child: ClipRRect(
                borderRadius: BorderRadius.vertical(
                  top: const Radius.circular(20),
                  bottom: Radius.circular(radius),
                ),
                child: Container(
                  color: const Color(0xFF202322),
                  child: SizedBox.expand(
                    child: SafeArea(
                      child: StreamBuilder<MediaItem?>(
                        stream: PlaybackService.mediaItemStream,
                        builder: (context, itemSnapshot) {
                          final item = itemSnapshot.data;

                          if (item == null) {
                            return _emptyState();
                          }

                          final track = _trackForItem(item);
                          return StreamBuilder<Duration?>(
                            stream: PlaybackService.durationStream,
                            builder: (context, durationSnapshot) {
                              final duration = resolvePlaybackDuration(
                                durationSnapshot.data,
                                item.duration,
                              );
                              return LayoutBuilder(
                                builder: (context, constraints) {
                                  final artSize = math.min(
                                    (constraints.maxWidth - 64).clamp(
                                      160.0,
                                      420.0,
                                    ),
                                    (constraints.maxHeight - 360).clamp(
                                      160.0,
                                      420.0,
                                    ),
                                  );

                                  return Padding(
                                    padding: const EdgeInsets.fromLTRB(
                                      24,
                                      8,
                                      24,
                                      12,
                                    ),
                                    child: Column(
                                      children: [
                                        // Header
                                        Row(
                                          children: [
                                            JuggleIconButton(
                                              tooltip: 'Close player',
                                              size: 48,
                                              onPressed: () =>
                                                  Navigator.maybePop(context),
                                              icon: const Icon(
                                                Icons
                                                    .keyboard_arrow_down_rounded,
                                                color: Colors.white,
                                                size: 30,
                                              ),
                                            ),
                                            const Expanded(
                                              child: Column(
                                                children: [
                                                  Text(
                                                    'NOW PLAYING',
                                                    style: TextStyle(
                                                      color: _muted,
                                                      fontSize: 10,
                                                      letterSpacing: 2,
                                                      fontWeight:
                                                          FontWeight.w700,
                                                    ),
                                                  ),
                                                  SizedBox(height: 4),
                                                  Text(
                                                    'Clove Library',
                                                    style: TextStyle(
                                                      color: Colors.white,
                                                      fontSize: 13,
                                                      fontWeight:
                                                          FontWeight.w700,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),

                                            // Queue button
                                            JuggleIconButton(
                                              tooltip: 'Show queue',
                                              size: 48,
                                              onPressed: _showQueue,
                                              icon: const Icon(
                                                Icons.queue_music_rounded,
                                                color: Colors.white,
                                                size: 24,
                                              ),
                                            ),
                                          ],
                                        ),

                                        const Spacer(),

                                        // Album artwork
                                        Center(
                                          child: LocalArtwork(
                                            track: track,
                                            size: artSize,
                                            borderRadius: 22,
                                            elevation: true,
                                            iconSize: 96,
                                          ),
                                        ),

                                        const Spacer(),

                                        // Track information
                                        Row(
                                          children: [
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  Row(
                                                    children: [
                                                      Expanded(
                                                        child: MarqueeText(
                                                          text: item.title,
                                                          pixelsPerSecond: 32,
                                                          style:
                                                              const TextStyle(
                                                                color: Colors
                                                                    .white,
                                                                fontSize: 23,
                                                                fontWeight:
                                                                    FontWeight
                                                                        .w800,
                                                              ),
                                                        ),
                                                      ),

                                                      const SizedBox(width: 8),

                                                      // Add to Playlist — matching MainShell mini-player
                                                      StreamBuilder<
                                                        TrackCollections
                                                      >(
                                                        stream: _playlistRepository
                                                            .watchCollections(
                                                              track.path,
                                                              canonicalId:
                                                                  track.mediaId,
                                                            ),
                                                        builder: (context, savedSnapshot) {
                                                          final collections =
                                                              savedSnapshot
                                                                  .data;

                                                          final isSaved =
                                                              collections !=
                                                                  null &&
                                                              (collections
                                                                      .isLiked ||
                                                                  collections
                                                                      .playlistIds
                                                                      .isNotEmpty);

                                                          return JuggleIconButton(
                                                            tooltip: isSaved
                                                                ? 'Saved to playlists'
                                                                : 'Add to playlists',
                                                            size: 42,
                                                            onPressed: () => showAddToPlaylistSheet(
                                                              context,
                                                              repository:
                                                                  _playlistRepository,
                                                              track: track,
                                                              animationStyle: const AnimationStyle(
                                                                curve: Curves
                                                                    .easeOutCubic,
                                                                reverseCurve: Curves
                                                                    .easeInCubic,
                                                                duration: Duration(
                                                                  milliseconds:
                                                                      420,
                                                                ),
                                                                reverseDuration:
                                                                    Duration(
                                                                      milliseconds:
                                                                          260,
                                                                    ),
                                                              ),
                                                            ),
                                                            icon: Icon(
                                                              isSaved
                                                                  ? Icons
                                                                        .check_circle_rounded
                                                                  : Icons
                                                                        .add_circle_outline_rounded,
                                                              color: isSaved
                                                                  ? _cloveMint
                                                                  : Colors
                                                                        .white,
                                                              size: 26,
                                                            ),
                                                          );
                                                        },
                                                      ),
                                                    ],
                                                  ),

                                                  const SizedBox(height: 7),

                                                  Text(
                                                    item.artist ??
                                                        'Unknown artist',
                                                    maxLines: 1,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                    style: const TextStyle(
                                                      color: _muted,
                                                      fontSize: 15,
                                                    ),
                                                  ),

                                                  if ((item.album ?? '')
                                                      .isNotEmpty) ...[
                                                    const SizedBox(height: 4),
                                                    Text(
                                                      item.album!,
                                                      maxLines: 1,
                                                      overflow:
                                                          TextOverflow.ellipsis,
                                                      style: const TextStyle(
                                                        color: Color(
                                                          0xFF77777E,
                                                        ),
                                                        fontSize: 12,
                                                      ),
                                                    ),
                                                  ],
                                                ],
                                              ),
                                            ),
                                          ],
                                        ),

                                        const SizedBox(height: 48),

                                        // Playback progress
                                        StreamBuilder<Duration>(
                                          stream:
                                              PlaybackService.positionStream,
                                          builder: (context, positionSnapshot) {
                                            final position = _scrubbing
                                                ? _scrubPosition ??
                                                      Duration.zero
                                                : positionSnapshot.data ??
                                                      Duration.zero;

                                            final maxMs =
                                                duration.inMilliseconds > 0
                                                ? duration.inMilliseconds
                                                : 1;

                                            final value = position
                                                .inMilliseconds
                                                .clamp(0, maxMs)
                                                .toDouble();

                                            return Column(
                                              children: [
                                                Padding(
                                                  padding:
                                                      const EdgeInsets.symmetric(
                                                        horizontal: 3,
                                                      ),
                                                  child: SliderTheme(
                                                    data: SliderTheme.of(context).copyWith(
                                                      trackHeight: 2,
                                                      thumbShape:
                                                          const RoundSliderThumbShape(
                                                            enabledThumbRadius:
                                                                5,
                                                          ),
                                                      overlayShape:
                                                          SliderComponentShape
                                                              .noOverlay,
                                                      activeTrackColor:
                                                          _cloveMint,
                                                      inactiveTrackColor:
                                                          Colors.white12,
                                                      thumbColor: _cloveMint,
                                                      overlayColor:
                                                          Colors.transparent,
                                                      trackShape:
                                                          const ExtendedSliderTrackShape(),
                                                    ),
                                                    child: Slider(
                                                      min: 0,
                                                      max: maxMs.toDouble(),
                                                      value: value,
                                                      onChangeStart: (_) {
                                                        setState(() {
                                                          _scrubbing = true;
                                                        });
                                                      },
                                                      onChanged:
                                                          duration ==
                                                              Duration.zero
                                                          ? null
                                                          : (newValue) {
                                                              setState(() {
                                                                _scrubPosition =
                                                                    Duration(
                                                                      milliseconds:
                                                                          newValue
                                                                              .round(),
                                                                    );
                                                              });
                                                            },
                                                      onChangeEnd:
                                                          duration ==
                                                              Duration.zero
                                                          ? null
                                                          : (newValue) {
                                                              final target =
                                                                  Duration(
                                                                    milliseconds:
                                                                        newValue
                                                                            .round(),
                                                                  );

                                                              setState(() {
                                                                _scrubbing =
                                                                    false;
                                                                _scrubPosition =
                                                                    null;
                                                              });

                                                              PlaybackService.seek(
                                                                target,
                                                              );
                                                            },
                                                    ),
                                                  ),
                                                ),
                                                Row(
                                                  mainAxisAlignment:
                                                      MainAxisAlignment
                                                          .spaceBetween,
                                                  children: [
                                                    Text(
                                                      formatPlaybackTime(
                                                        position,
                                                      ),
                                                      style: const TextStyle(
                                                        color: _muted,
                                                        fontSize: 11,
                                                      ),
                                                    ),
                                                    Text(
                                                      formatPlaybackTime(
                                                        duration,
                                                      ),
                                                      style: const TextStyle(
                                                        color: _muted,
                                                        fontSize: 11,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ],
                                            );
                                          },
                                        ),

                                        const SizedBox(height: 32),

                                        // Playback controls
                                        StreamBuilder<PlaybackState>(
                                          stream: PlaybackService
                                              .playbackStateStream,
                                          builder: (context, stateSnapshot) {
                                            final state = stateSnapshot.data;
                                            final playing =
                                                state?.playing ?? false;
                                            final shuffled =
                                                state?.shuffleMode ==
                                                AudioServiceShuffleMode.all;
                                            final repeat =
                                                state?.repeatMode ??
                                                AudioServiceRepeatMode.none;

                                            return Row(
                                              mainAxisAlignment:
                                                  MainAxisAlignment
                                                      .spaceBetween,
                                              children: [
                                                // Shuffle
                                                JuggleIconButton(
                                                  tooltip: shuffled
                                                      ? 'Turn shuffle off'
                                                      : 'Turn shuffle on',
                                                  size: 44,
                                                  onPressed: () =>
                                                      PlaybackService.setShuffleEnabled(
                                                        !shuffled,
                                                      ),
                                                  icon: Icon(
                                                    Icons.shuffle_rounded,
                                                    color: shuffled
                                                        ? _cloveMint
                                                        : _muted,
                                                  ),
                                                ),

                                                // Previous track
                                                JuggleIconButton(
                                                  tooltip: 'Previous track',
                                                  size: 48,
                                                  onPressed:
                                                      PlaybackService.previous,
                                                  icon: const Icon(
                                                    Icons.skip_previous_rounded,
                                                    size: 38,
                                                    color: Colors.white,
                                                  ),
                                                ),

                                                // Play / Pause
                                                JuggleIconButton(
                                                  tooltip: playing
                                                      ? 'Pause'
                                                      : 'Play',
                                                  size: 68,
                                                  onPressed: () => playing
                                                      ? PlaybackService.pause()
                                                      : PlaybackService.play(),
                                                  icon: Container(
                                                    width: 64,
                                                    height: 64,
                                                    decoration:
                                                        const BoxDecoration(
                                                          color: _cloveMint,
                                                          shape:
                                                              BoxShape.circle,
                                                        ),
                                                    child: Icon(
                                                      playing
                                                          ? Icons.pause_rounded
                                                          : Icons
                                                                .play_arrow_rounded,
                                                      size: 38,
                                                      color: const Color(
                                                        0xFF0B0B0B,
                                                      ),
                                                    ),
                                                  ),
                                                ),

                                                // Next track
                                                JuggleIconButton(
                                                  tooltip: 'Next track',
                                                  size: 48,
                                                  onPressed:
                                                      PlaybackService.next,
                                                  icon: const Icon(
                                                    Icons.skip_next_rounded,
                                                    size: 38,
                                                    color: Colors.white,
                                                  ),
                                                ),

                                                // Repeat
                                                JuggleIconButton(
                                                  tooltip: _repeatTooltip(
                                                    repeat,
                                                  ),
                                                  size: 44,
                                                  onPressed: () =>
                                                      PlaybackService.setRepeatMode(
                                                        nextRepeatMode(repeat),
                                                      ),
                                                  icon: Icon(
                                                    repeat ==
                                                            AudioServiceRepeatMode
                                                                .one
                                                        ? Icons
                                                              .repeat_one_rounded
                                                        : Icons.repeat_rounded,
                                                    color:
                                                        repeat ==
                                                            AudioServiceRepeatMode
                                                                .none
                                                        ? _muted
                                                        : _cloveMint,
                                                  ),
                                                ),
                                              ],
                                            );
                                          },
                                        ),

                                        const SizedBox(height: 8),
                                      ],
                                    ),
                                  );
                                },
                              );
                            },
                          );
                        },
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  CloveTrack _trackForItem(MediaItem item) {
    final trackId = trackIdFromMediaItem(item) ?? item.id;
    final tracks = PlaybackService.isInitialized
        ? PlaybackService.handler.tracks
        : const <CloveTrack>[];
    for (final track in tracks) {
      if (track.path == trackId) return track;
    }
    final albumId = item.extras?['albumId'];
    return CloveTrack(
      path: trackId,
      title: item.title,
      artist: item.artist ?? 'Unknown artist',
      album: item.album ?? '',
      duration: item.duration ?? Duration.zero,
      albumId: albumId is int ? albumId : null,
      artworkUri: item.artUri,
    );
  }

  String _repeatTooltip(AudioServiceRepeatMode mode) => switch (mode) {
    AudioServiceRepeatMode.none => 'Repeat off',
    AudioServiceRepeatMode.all => 'Repeat all',
    _ => 'Repeat one',
  };

  Widget _queueTrackRow({required MediaItem item, required bool isCurrent}) {
    final track = _trackForItem(item);

    return Material(
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
          onTap: isCurrent
              ? null
              : () {
                  Navigator.pop(context);
                  PlaybackService.playQueueEntry(item);
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
                // Song artwork — same as Playlist Details
                LocalArtwork(track: track, size: 50, borderRadius: 13),

                const SizedBox(width: 13),

                // Song title, playing indicator, artist and duration
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          if (isCurrent) ...[
                            const PlayingEqualizer(),
                            const SizedBox(width: 8),
                          ],
                          Expanded(
                            child: Text(
                              item.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: isCurrent ? _cloveMint : Colors.white,
                                fontWeight: FontWeight.w700,
                                fontSize: 15,
                              ),
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 4),

                      Text(
                        item.artist ?? 'Unknown artist',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        softWrap: false,
                        style: const TextStyle(color: _muted, fontSize: 12),
                      ),
                    ],
                  ),
                ),

                const SizedBox(width: 32),

                // Keep the existing cut/remove button and logic unchanged
                !isCurrent
                    ? JuggleIconButton(
                        tooltip: 'Remove from queue',
                        size: 42,
                        onPressed: () async {
                          await PlaybackService.removeUpcomingQueueItem(item);
                        },
                        icon: const Icon(
                          Icons.close_rounded,
                          color: Colors.white70,
                          size: 24,
                        ),
                      )
                    : const SizedBox(width: 42),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _showQueue() async {
    await PlaybackService.initialize();
    if (!mounted) return;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF181A19),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => SafeArea(
        child: SizedBox(
          height: MediaQuery.sizeOf(context).height * 0.65,
          child: StreamBuilder<List<MediaItem>>(
            stream: PlaybackService.queueStream,
            builder: (context, snapshot) {
              final items = snapshot.data ?? const <MediaItem>[];

              return StreamBuilder<PlaybackState>(
                stream: PlaybackService.playbackStateStream,
                builder: (context, _) {
                  final currentIndex = PlaybackService.currentQueueIndex ?? -1;

                  final upcoming = upcomingQueueIndices(
                    currentIndex,
                    PlaybackService.effectiveQueueIndices,
                  );

                  // Show the currently playing song first.
                  final queueIndices = <int>[
                    if (currentIndex >= 0 && currentIndex < items.length)
                      currentIndex,
                    ...upcoming.where((index) => index != currentIndex),
                  ];

                  final currentItemIndex =
                      currentIndex >= 0 && currentIndex < items.length
                      ? currentIndex
                      : -1;
                  return Column(
                    children: [
                      const SizedBox(height: 18),
                      Container(
                        width: 36,
                        height: 4,
                        decoration: BoxDecoration(
                          color: Colors.white24,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(22, 18, 22, 12),
                        child: Row(
                          children: [
                            const Expanded(
                              child: Text(
                                'Up next',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 20,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                            Text(
                              '${upcoming.length} tracks',
                              style: const TextStyle(color: _muted),
                            ),
                          ],
                        ),
                      ),
                      Expanded(
                        child: queueIndices.isEmpty
                            ? const Center(
                                child: Text(
                                  'No tracks in queue',
                                  style: TextStyle(color: _muted),
                                ),
                              )
                            : ListView.builder(
                                itemCount: queueIndices.length,
                                itemBuilder: (context, index) {
                                  final queueIndex = queueIndices[index];

                                  if (queueIndex < 0 ||
                                      queueIndex >= items.length) {
                                    return const SizedBox.shrink();
                                  }

                                  final item = items[queueIndex];
                                  final isCurrent =
                                      queueIndex == currentItemIndex;

                                  return _queueTrackRow(
                                    item: item,
                                    isCurrent: isCurrent,
                                  );
                                },
                              ),
                      ),
                    ],
                  );
                },
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _emptyState() => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.library_music_outlined, color: _cloveMint, size: 54),
        const SizedBox(height: 14),
        const Text(
          'Nothing is playing',
          style: TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          'Choose a song from your local library.',
          style: TextStyle(color: _muted),
        ),
        const SizedBox(height: 18),
        JuggleIconButton(
          tooltip: 'Back to library',
          size: 48,
          onPressed: () => Navigator.maybePop(context),
          icon: const Icon(
            Icons.arrow_back_rounded,
            color: _cloveMint,
            size: 24,
          ),
        ),
      ],
    ),
  );
}

class ExtendedSliderTrackShape extends RoundedRectSliderTrackShape {
  const ExtendedSliderTrackShape();

  @override
  Rect getPreferredRect({
    required RenderBox parentBox,
    Offset offset = Offset.zero,
    required SliderThemeData sliderTheme,
    bool isEnabled = false,
    bool isDiscrete = false,
  }) {
    final trackHeight = sliderTheme.trackHeight ?? 2;

    final left = offset.dx - 3;
    final right = offset.dx + parentBox.size.width + 3;
    final top = offset.dy + (parentBox.size.height - trackHeight) / 2;

    return Rect.fromLTRB(left, top, right, top + trackHeight);
  }
}
