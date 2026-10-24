import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';

import '../models/clove_track.dart';
import '../screens/now_playing_screen.dart';
import '../services/audio/playback_service.dart';
import '../services/clove_notifications.dart';
import '../services/playlist_repository.dart';
import 'juggle_icon_button.dart';
import 'local_artwork.dart';
import 'marquee_text.dart';
import '../screens/add_to_playlist_sheet.dart';

const Color _cloveMint = Color(0xFF1DE9B6);
const Color _primaryText = Color(0xFFFFFFFF);

class CloveMiniPlayer extends StatefulWidget {
  const CloveMiniPlayer({
    super.key,
    required this.playlistRepository,
    this.notificationAnchor = false,
  });

  final PlaylistRepository playlistRepository;
  final bool notificationAnchor;

  @override
  State<CloveMiniPlayer> createState() => _CloveMiniPlayerState();
}

class _CloveMiniPlayerState extends State<CloveMiniPlayer> {
  double _offset = 0;
  bool _dragging = false;
  bool _dismissing = false;

  Future<void> _finishDismissal() async {
    await PlaybackService.dismissMiniPlayer();
    if (!mounted) return;
    setState(() {
      _offset = 0;
      _dismissing = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<MediaItem?>(
      stream: PlaybackService.mediaItemStream,
      builder: (context, itemSnapshot) {
        final item = itemSnapshot.data;
        if (item == null) return const SizedBox.shrink();
        final tracks = PlaybackService.isInitialized
            ? PlaybackService.handler.tracks
            : const [];
        final trackId = trackIdFromMediaItem(item) ?? item.id;
        CloveTrack? track;
        for (final candidate in tracks) {
          if (candidate.path == trackId) {
            track = candidate;
            break;
          }
        }
        track ??= CloveTrack(
          path: trackId,
          title: item.title,
          artist: item.artist ?? 'Unknown artist',
          album: item.album ?? '',
          duration: item.duration ?? Duration.zero,
          albumId: item.extras?['albumId'] is int
              ? item.extras!['albumId'] as int
              : null,
          artworkUri: item.artUri,
        );
        final currentTrack = track;

        return Transform.translate(
          offset: Offset(0, _offset),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onVerticalDragStart: _dismissing
                ? null
                : (_) => setState(() => _dragging = true),
            onVerticalDragUpdate: _dismissing
                ? null
                : (details) => setState(() {
                    _offset = (_offset + details.delta.dy).clamp(0.0, 500.0);
                  }),
            onVerticalDragEnd: _dismissing
                ? null
                : (details) {
                    final dismiss =
                        _offset > 75 || (details.primaryVelocity ?? 0) > 700;
                    if (dismiss) {
                      setState(() {
                        _dragging = false;
                        _dismissing = true;
                        _offset = MediaQuery.sizeOf(context).height;
                      });
                      Future<void>.delayed(
                        const Duration(milliseconds: 180),
                        _finishDismissal,
                      );
                    } else {
                      setState(() {
                        _dragging = false;
                        _offset = 0;
                      });
                    }
                  },
            child: AnimatedContainer(
              duration: _dragging
                  ? Duration.zero
                  : const Duration(milliseconds: 180),
              curve: Curves.easeOutCubic,
              child: Material(
                key: widget.notificationAnchor
                    ? CloveNotifications.miniPlayerAnchorKey
                    : null,
                color: const Color(0xFF202322),
                borderRadius: BorderRadius.circular(16),
                child: InkWell(
                  borderRadius: BorderRadius.circular(16),
                  onTap: () {
                    Navigator.of(context).push(
                      PageRouteBuilder<void>(
                        opaque: false,
                        pageBuilder: (context, animation, secondaryAnimation) {
                          return const NowPlayingScreen();
                        },
                        transitionsBuilder:
                            (context, animation, secondaryAnimation, child) {
                              final slide = Tween<Offset>(
                                begin: const Offset(0, 1),
                                end: Offset.zero,
                              ).chain(CurveTween(curve: Curves.easeOutCubic));

                              return SlideTransition(
                                position: animation.drive(slide),
                                child: child,
                              );
                            },
                        transitionDuration: const Duration(milliseconds: 280),
                        reverseTransitionDuration: const Duration(
                          milliseconds: 220,
                        ),
                      ),
                    );
                  },
                  child: SizedBox(
                    height: 62,
                    child: Stack(
                      children: [
                        Row(
                          children: [
                            const SizedBox(width: 8),
                            LocalArtwork(
                              track: currentTrack,
                              size: 46,
                              borderRadius: 10,
                              iconSize: 22,
                            ),
                            const SizedBox(width: 11),
                            Expanded(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  MarqueeText(
                                    text: item.title,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 13,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  const SizedBox(height: 3),
                                  Text(
                                    item.artist ?? 'Unknown artist',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: Color(0xFFAAA9B1),
                                      fontSize: 11,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            StreamBuilder<TrackCollections>(
                              stream: widget.playlistRepository
                                  .watchCollections(
                                    currentTrack.path,
                                    canonicalId: currentTrack.mediaId,
                                  ),
                              builder: (context, snapshot) {
                                final collections = snapshot.data;
                                final isSaved =
                                    collections != null &&
                                    (collections.isLiked ||
                                        collections.playlistIds.isNotEmpty);

                                return JuggleIconButton(
                                  tooltip: isSaved
                                      ? 'Saved to playlists'
                                      : 'Save to playlists',
                                  size: 42,
                                  onPressed: () => showAddToPlaylistSheet(
                                    context,
                                    repository: widget.playlistRepository,
                                    track: currentTrack,
                                  ),
                                  icon: Icon(
                                    isSaved
                                        ? Icons.check_circle_rounded
                                        : Icons.add_circle_outline_rounded,
                                    color: isSaved ? _cloveMint : _primaryText,
                                    size: 26,
                                  ),
                                );
                              },
                            ),
                            StreamBuilder<PlaybackState>(
                              stream: PlaybackService.playbackStateStream,
                              builder: (context, stateSnapshot) {
                                final playing =
                                    stateSnapshot.data?.playing ?? false;

                                return JuggleIconButton(
                                  tooltip: playing ? 'Pause' : 'Play',
                                  size: 48,
                                  onPressed: () => playing
                                      ? PlaybackService.pause()
                                      : PlaybackService.play(),
                                  icon: Icon(
                                    playing
                                        ? Icons.pause_rounded
                                        : Icons.play_arrow_rounded,
                                    color: _primaryText,
                                    size: 32,
                                  ),
                                );
                              },
                            ),
                            const SizedBox(width: 2),
                          ],
                        ),
                        Positioned(
                          left: 10,
                          right: 10,
                          bottom: 1,
                          child: StreamBuilder<Duration>(
                            stream: PlaybackService.positionStream,
                            builder: (context, positionSnapshot) {
                              final duration = item.duration ?? Duration.zero;
                              final totalMs = duration.inMilliseconds;
                              final positionMs =
                                  (positionSnapshot.data ?? Duration.zero)
                                      .inMilliseconds;
                              final progress = totalMs > 0
                                  ? (positionMs / totalMs).clamp(0.0, 1.0)
                                  : 0.0;

                              return ClipRRect(
                                borderRadius: BorderRadius.circular(50),
                                child: SizedBox(
                                  height: 1,
                                  child: LinearProgressIndicator(
                                    value: progress,
                                    backgroundColor: Colors.white12,
                                    valueColor:
                                        const AlwaysStoppedAnimation<Color>(
                                          _primaryText,
                                        ),
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
