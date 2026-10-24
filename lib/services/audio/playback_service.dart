import 'dart:ui' show Color;

import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';

import '../../models/clove_track.dart';
import '../online_music_provider.dart';
import 'audio_handler.dart';

bool isTrackActiveInPlaybackSource({
  required String? activeSourceId,
  required String expectedSourceId,
  required String? currentTrackId,
  required String trackId,
}) => activeSourceId == expectedSourceId && currentTrackId == trackId;

String? trackIdFromMediaItem(MediaItem? item) {
  final trackId = item?.extras?['trackId'];
  return trackId is String ? trackId : item?.id;
}

class PlaybackService {
  PlaybackService._();

  static late CloveAudioHandler handler;
  static bool _initialized = false;
  static Future<void>? _initialization;
  static OnlineMusicProvider? _onlineMusicProvider;
  static Object? initializationError;

  static const String localMusicSourceId = 'local_music';
  static const String likedSongsSourceId = 'liked_songs';

  static String playlistSourceId(int playlistId) => 'playlist:$playlistId';

  static String? get activeSourceId =>
      _initialized ? handler.activeSourceId : null;
  static bool get isPlaying => _initialized && handler.isPlaying;

  static Stream<MediaItem?> get mediaItemStream =>
      _afterInitialization((audioHandler) => audioHandler.mediaItem);
  static Stream<List<MediaItem>> get queueStream =>
      _afterInitialization((audioHandler) => audioHandler.queue);
  static bool get isInitialized => _initialized;
  static Stream<PlaybackState> get playbackStateStream =>
      _afterInitialization((audioHandler) => audioHandler.playbackState);
  static Stream<bool> get isPlayingStream =>
      playbackStateStream.map((state) => state.playing).distinct();
  static Stream<Duration> get positionStream =>
      _afterInitialization((audioHandler) => audioHandler.positionStream);
  static Stream<String?> get playbackSourceStream =>
      _afterInitialization((audioHandler) async* {
        yield audioHandler.activeSourceId;
        yield* audioHandler.playbackSourceStream;
      });

  static List<int> get effectiveQueueIndices =>
      _initialized ? handler.effectiveQueueIndices : const [];

  static int? get currentQueueIndex =>
      _initialized ? handler.currentIndex : null;

  static Stream<T> _afterInitialization<T>(
    Stream<T> Function(CloveAudioHandler audioHandler) selectStream,
  ) async* {
    await initialize();
    yield* selectStream(handler);
  }

  static Future<void> initialize({OnlineMusicProvider? onlineMusicProvider}) {
    if (onlineMusicProvider != null) {
      _onlineMusicProvider = onlineMusicProvider;
      if (_initialized) handler.onlineMusicProvider = onlineMusicProvider;
    }
    return _initialization ??= _initialize();
  }

  static Future<void> _initialize() async {
    if (_initialized) return;

    try {
      final session = await AudioSession.instance;
      await session.configure(const AudioSessionConfiguration.music());

      final audioHandler = await AudioService.init(
        builder: () =>
            CloveAudioHandler(onlineMusicProvider: _onlineMusicProvider),
        config: const AudioServiceConfig(
          androidNotificationChannelId: 'com.shvnix.clove.audio',
          androidNotificationChannelName: 'Clove Playback',
          androidNotificationIcon: 'drawable/clove_notification',
          notificationColor: Color(0xFF1DE9B6),
          androidNotificationOngoing: true,
          androidStopForegroundOnPause: true,
        ),
      );

      handler = audioHandler;
      await audioHandler.restorePersistentSession();
      _initialized = true;
      initializationError = null;
    } catch (error) {
      initializationError = error;
      rethrow;
    }
  }

  static Future<void> playTracks(
    List<CloveTrack> tracks, {
    int initialIndex = 0,
    required String sourceId,
  }) async {
    await initialize();
    return handler.playTracks(
      tracks,
      initialIndex: initialIndex,
      sourceId: sourceId,
    );
  }

  /// Starts a new track or queue without waiting for playback to finish.
  static Future<void> startTracks(
    List<CloveTrack> tracks, {
    int initialIndex = 0,
    required String sourceId,
    void Function(Object error, StackTrace stackTrace)? onPlaybackError,
    bool Function()? shouldStart,
  }) async {
    await initialize();
    return handler.startTracks(
      tracks,
      initialIndex: initialIndex,
      sourceId: sourceId,
      onPlaybackError: onPlaybackError,
      shouldStart: shouldStart,
    );
  }

  static Future<void> addTracksToQueue(
    List<CloveTrack> tracks, {
    String? sourceId,
    List<int>? sourcePositions,
    bool expandSourceContext = false,
  }) async {
    if (tracks.isEmpty) return;
    await initialize();
    await handler.addTracksToQueue(
      tracks,
      sourceId: sourceId,
      sourcePositions: sourcePositions,
      expandSourceContext: expandSourceContext,
    );
  }

  /// Starts a playlist only when no valid current media item is loaded.
  /// A paused but loaded track remains an existing session and only receives
  /// the playlist at the end of its current queue.
  static Future<bool> queueTracksOrStart(
    List<CloveTrack> tracks, {
    required String sourceId,
    List<int>? sourcePositions,
  }) async {
    if (tracks.isEmpty) return false;
    await initialize();
    return handler.queueTracksOrStart(
      tracks,
      sourceId: sourceId,
      sourcePositions: sourcePositions,
    );
  }

  static Future<void> playQueueEntry(MediaItem item) async {
    await initialize();
    await handler.playQueueEntry(item);
  }

  static Future<bool> removeUpcomingQueueItem(MediaItem item) async {
    await initialize();
    return handler.removeUpcomingQueueItem(item);
  }

  static void clearActiveSourceIfMatches(String sourceId) {
    if (_initialized) handler.clearActiveSourceIfMatches(sourceId);
  }

  static Future<void> play() async {
    await initialize();
    await handler.play();
  }

  static Future<void> pause() async {
    await initialize();
    await handler.pause();
  }

  static Future<void> stop() async {
    await initialize();
    await handler.stop();
  }

  /// Clears the active session and queue while keeping the handler reusable.
  static Future<void> dismissMiniPlayer() async {
    await initialize();
    await handler.stop();
  }

  static Future<void> seek(Duration position) async {
    await initialize();
    await handler.seek(position);
  }

  static Future<void> next() async {
    await initialize();
    await handler.skipToNext();
  }

  static Future<void> previous() async {
    await initialize();
    await handler.skipToPrevious();
  }

  static Future<void> setShuffleEnabled(bool enabled) async {
    await initialize();
    await handler.setShuffleEnabled(enabled);
  }

  static Future<void> setRepeatMode(AudioServiceRepeatMode mode) async {
    await initialize();
    await handler.setRepeatMode(mode);
  }

  static Future<void> addToLibrary() async {
    await initialize();
    await handler.addCurrentTrackToLikedSongs();
  }
}
