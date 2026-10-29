import 'dart:async';
import 'dart:convert';

import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';

import '../../models/clove_track.dart';
import '../../models/online_music_track.dart';
import '../../data/database.dart';
import '../online_library_track_resolver.dart';
import '../online_music_provider.dart';
import '../offline_track_artwork.dart';
import '../online_play_history.dart';
import '../playlist_repository.dart';
import 'previous_track_policy.dart';
import 'player_formatters.dart';
import 'playback_queue.dart';
import 'playback_session_codec.dart';
import 'smart_music_queue.dart';

class CloveAudioHandler extends BaseAudioHandler
    with QueueHandler, SeekHandler {
  AudioPlayer _player = AudioPlayer(
    maxSkipsOnError: defaultSmartMusicQueueConfig.targetUpcoming,
  );
  StreamSubscription<PlayerException>? _playerErrorSubscription;
  StreamSubscription<PlaybackEvent>? _playbackEventSubscription;
  StreamSubscription<PlayerState>? _playerStateSubscription;
  StreamSubscription<int?>? _currentIndexSubscription;
  StreamSubscription<List<LikedTrack>>? _likedTracksSubscription;
  final StreamController<String?> _playbackSourceController =
      StreamController<String?>.broadcast();

  List<CloveTrack> _tracks = [];
  List<String> _queueEntryIds = [];
  List<MediaItem> _queueItems = [];
  int _queueEntryCounter = 0;
  String? _activeSourceId;
  bool _loadingQueue = false;
  Future<void>? _taskRemoval;
  Future<void> _lifecycleTail = Future<void>.value();
  Future<void> _previousCommandTail = Future<void>.value();
  Future<void> _queueMutationTail = Future<void>.value();
  int? _previousRestartIndex;
  bool _playerDisposed = false;
  bool _restoringSession = false;
  final Set<String> _likedTrackIds = {};
  Future<void> _sessionWriteTail = Future<void>.value();
  int _sessionWriteVersion = 0;
  Timer? _positionSaveTimer;
  Timer? _recommendationRetryTimer;
  final Map<int, Future<void>> _recommendationRefills = {};
  final List<OnlineMusicTrack> _recommendationHistory = [];
  final _onlinePlayHistory = OnlinePlayHistory();
  int _recommendationGeneration = 0;
  int _recommendationRetryAttempt = 0;
  int _recommendationBatchAdded = 0;
  String? _observedRecommendationTrackKey;
  static const _smartQueueConfig = defaultSmartMusicQueueConfig;

  CloveAudioHandler({this.onlineMusicProvider}) {
    _listenToPlayer();
    _startPositionSaveTimer();
  }

  OnlineMusicProvider? onlineMusicProvider;

  void _logPlaybackError(String operation, Object error) {
    if (kDebugMode) debugPrint('CLOVE: $operation failed: $error');
  }

  void _startPositionSaveTimer() {
    _positionSaveTimer ??= Timer.periodic(
      const Duration(seconds: 5),
      (_) => _scheduleSessionSave(),
    );
  }

  void _listenToPlayer() {
    _likedTracksSubscription ??= AppDatabase.instance
        .select(AppDatabase.instance.likedTracks)
        .watch()
        .listen(
          (likedTracks) {
            _likedTrackIds
              ..clear()
              ..addAll(
                likedTracks.expand(
                  (track) => [
                    track.trackId,
                    if (track.canonicalId != null) track.canonicalId!,
                  ],
                ),
              );
            if (!_loadingQueue) _broadcastPlaybackState();
          },
          onError: (Object error) {
            _logPlaybackError('liked songs stream', error);
          },
        );
    _playerErrorSubscription = _player.errorStream.listen((error) {
      if (kDebugMode) {
        debugPrint(
          'CLOVE: player source failed (${error.code}) at queue index ${error.index}.',
        );
      }
    });
    _playbackEventSubscription = _player.playbackEventStream.listen((_) {
      if (!_loadingQueue) _broadcastPlaybackState();
    });

    // Keep the UI synchronized with playing and completed states.
    _playerStateSubscription = _player.playerStateStream.listen((_) {
      if (!_loadingQueue) _broadcastPlaybackState();
    });

    _currentIndexSubscription = _player.currentIndexStream.listen((index) {
      if (_previousRestartIndex != null && index != _previousRestartIndex) {
        _previousRestartIndex = null;
      }
      if (!_loadingQueue &&
          index != null &&
          index >= 0 &&
          index < _queueItems.length) {
        final currentItem = _queueItems[index];
        mediaItem.add(currentItem);
        _setActiveSource(activeSourceForQueueIndex(_queueItems, index));
      }
      if (!_loadingQueue) _broadcastPlaybackState();
      if (!_loadingQueue && !_restoringSession) _scheduleSessionSave();
      if (!_loadingQueue && !_restoringSession) {
        _observeRecommendationTrack(index);
      }
    });
  }

  void _ensurePlayer() {
    if (!_playerDisposed) return;
    _player = AudioPlayer(
      maxSkipsOnError: defaultSmartMusicQueueConfig.targetUpcoming,
    );
    _playerDisposed = false;
    _taskRemoval = null;
    _listenToPlayer();
    _startPositionSaveTimer();
  }

  Stream<Duration> get positionStream {
    _ensurePlayer();
    return _player.positionStream;
  }

  Stream<Duration?> get durationStream {
    _ensurePlayer();
    return _player.durationStream;
  }

  Stream<bool> get shuffleModeStream {
    _ensurePlayer();
    return _player.shuffleModeEnabledStream;
  }

  Stream<LoopMode> get loopModeStream {
    _ensurePlayer();
    return _player.loopModeStream;
  }

  List<CloveTrack> get tracks => List.unmodifiable(_tracks);
  CloveTrack? get _currentTrack {
    final index = _player.currentIndex;
    if (index == null || index < 0 || index >= _tracks.length) return null;
    return _tracks[index];
  }

  String? get activeSourceId => _activeSourceId;
  bool get isPlaying =>
      _player.playing && _player.processingState != ProcessingState.completed;
  Stream<String?> get playbackSourceStream => _playbackSourceController.stream;

  void _setActiveSource(String? sourceId) {
    if (_activeSourceId == sourceId) return;
    if (!automaticRecommendationsEnabledForSource(sourceId)) {
      _invalidateRecommendationGeneration();
      _observedRecommendationTrackKey = null;
    }
    _activeSourceId = sourceId;
    _playbackSourceController.add(sourceId);
  }

  void _invalidateRecommendationGeneration() {
    final oldGeneration = _recommendationGeneration;
    _recommendationGeneration++;
    _recommendationRetryTimer?.cancel();
    _recommendationRetryTimer = null;
    _recommendationRetryAttempt = 0;
    _recommendationBatchAdded = 0;
    final provider = onlineMusicProvider;
    if (provider is CancellableOnlineRecommendationProvider) {
      unawaited(
        (provider as CancellableOnlineRecommendationProvider)
            .cancelRecommendationRequest(oldGeneration),
      );
    }
  }

  void _observeRecommendationTrack(int? index) {
    final track = index != null && index >= 0 && index < _tracks.length
        ? _onlineTrackFor(_tracks[index])
        : null;
    final key = track == null ? null : '${track.providerId}:${track.id}';
    final changed = key != _observedRecommendationTrackKey;
    if (changed) {
      // Each newly active track owns a fresh two-track recommendation batch.
      // Invalidating the old generation also cancels only its recommendation
      // requests; it does not stop the current/manual playback source.
      _invalidateRecommendationGeneration();
      _observedRecommendationTrackKey = key;
      if (track != null) {
        _recommendationHistory.removeWhere(
          (recent) =>
              recent.providerId == track.providerId && recent.id == track.id,
        );
        _recommendationHistory.insert(0, track);
        if (_recommendationHistory.length >
            _smartQueueConfig.recentHistoryWindow) {
          _recommendationHistory.removeRange(
            _smartQueueConfig.recentHistoryWindow,
            _recommendationHistory.length,
          );
        }
        unawaited(_onlinePlayHistory.record(track).catchError((Object _) {}));
      }
    }
    if (changed && track != null) {
      unawaited(_maybeRefillAutomaticQueue());
    }
  }

  OnlineMusicTrack? _onlineTrackFor(CloveTrack track) {
    final identity = Uri.tryParse(track.mediaId ?? track.path);
    if (identity == null) return null;
    final host = identity.host.toLowerCase();
    String? id;
    if (host == 'youtu.be' && identity.pathSegments.isNotEmpty) {
      id = identity.pathSegments.first;
    } else if (host == 'youtube.com' || host.endsWith('.youtube.com')) {
      id = identity.queryParameters['v'];
      if ((id == null || id.isEmpty) && identity.pathSegments.length > 1) {
        id = identity.pathSegments[1];
      }
    }
    if (id == null || id.isEmpty) return null;
    return OnlineMusicTrack(
      providerId: 'youtube',
      id: id,
      title: track.title,
      artist: track.artist,
      uploaderName: track.artist,
      album: track.album,
      artworkUri: track.artworkUri,
      sourcePageUri: identity,
      duration: track.duration,
    );
  }

  List<OnlineMusicTrack> _queuedOnlineTracks() =>
      upcomingQueueIndices(_player.currentIndex, _player.effectiveIndices)
          .map((index) => _onlineTrackFor(_tracks[index]))
          .whereType<OnlineMusicTrack>()
          .toList(growable: false);

  List<OnlineMusicTrack> _upcomingAutomaticOnlineTracks() =>
      upcomingQueueIndices(_player.currentIndex, _player.effectiveIndices)
          .where(
            (index) =>
                _queueItems[index].extras?['automaticRecommendation'] == true,
          )
          .map((index) => _onlineTrackFor(_tracks[index]))
          .whereType<OnlineMusicTrack>()
          .toList(growable: false);

  Future<Set<String>> _likedArtistNames() async {
    try {
      final likedTracks = await AppDatabase.instance
          .select(AppDatabase.instance.likedTracks)
          .get();
      return likedTracks
          .map((track) => normalizeRecommendationText(track.artist))
          .where((artist) => artist.isNotEmpty)
          .toSet();
    } on Exception {
      return const {};
    }
  }

  Future<void> _maybeRefillAutomaticQueue() async {
    final provider = onlineMusicProvider;
    final index = _player.currentIndex;
    if (provider == null ||
        index == null ||
        index < 0 ||
        index >= _tracks.length ||
        _player.loopMode == LoopMode.one) {
      return;
    }
    if (!automaticRecommendationsEnabledForSource(
      queueItemSourceId(_queueItems[index]),
    )) {
      return;
    }
    if (provider is! OnlineMusicDiscoveryProvider) return;
    if (_recommendationRetryAttempt >= 3) return;
    final current = _onlineTrackFor(_tracks[index]);
    if (current == null) return;

    if (_recommendationBatchAdded >= _smartQueueConfig.refillBatchSize) return;

    final generation = _recommendationGeneration;
    if (_recommendationRefills.containsKey(generation)) return;
    final task = _runRecommendationRefill(
      provider: provider,
      current: current,
      generation: generation,
    );
    _recommendationRefills[generation] = task;
    try {
      await task;
    } finally {
      _recommendationRefills.remove(generation);
    }
  }

  Future<void> _runRecommendationRefill({
    required OnlineMusicDiscoveryProvider provider,
    required OnlineMusicTrack current,
    required int generation,
  }) async {
    try {
      final candidates = provider is CancellableOnlineRecommendationProvider
          ? await (provider as CancellableOnlineRecommendationProvider)
                .discoverRecommendations(current, requestId: generation)
                .timeout(const Duration(seconds: 25))
          : await provider
                .discoverRelated(current)
                .timeout(const Duration(seconds: 25));
      if (generation != _recommendationGeneration) return;
      final queueOnline = _queuedOnlineTracks();
      final automaticOnline = _upcomingAutomaticOnlineTracks();
      final likedArtists = await _likedArtistNames();
      final previouslyPlayedIds = await _onlinePlayHistory.loadPlayedIds();
      if (generation != _recommendationGeneration) return;
      final selected = rankRecommendationCandidates(
        current: current,
        candidates: candidates.take(_smartQueueConfig.candidatePoolSize),
        queued: queueOnline,
        automaticQueue: automaticOnline,
        recentHistory: _recommendationHistory,
        previouslyPlayedIds: previouslyPlayedIds,
        preferredArtists: likedArtists,
        // Rank a wider pool than the requested batch so a failed/unplayable
        // result can be replaced by another candidate.
        limit: _smartQueueConfig.candidatePoolSize,
        maxSameArtist: _smartQueueConfig.maxSameArtist,
        recentHistoryWindow: _smartQueueConfig.recentHistoryWindow,
      );
      if (kDebugMode) {
        final remainingToAdd =
            _smartQueueConfig.refillBatchSize - _recommendationBatchAdded;
        debugPrint(
          'CLOVE: online recommendations found ${candidates.length} candidates; ${selected.length} passed filters (need $remainingToAdd).',
        );
      }
      for (final candidate in selected) {
        if (generation != _recommendationGeneration ||
            _recommendationBatchAdded >= _smartQueueConfig.refillBatchSize) {
          return;
        }
        final recommendation = await _resolveRecommendation(
          provider,
          candidate,
          requestId: generation,
        );
        if (generation != _recommendationGeneration) return;
        if (recommendation != null &&
            await _appendAutomaticRecommendations(
              [recommendation],
              current: current,
              generation: generation,
            )) {
          _recommendationBatchAdded++;
        }
      }

      if (_recommendationBatchAdded >= _smartQueueConfig.refillBatchSize) {
        _recommendationRetryAttempt = 0;
      } else {
        _scheduleRecommendationRetry(generation);
      }
    } on Exception catch (error) {
      _logPlaybackError('online recommendation refill', error);
      _scheduleRecommendationRetry(generation);
    }
  }

  Future<_ResolvedRecommendation?> _resolveRecommendation(
    OnlineMusicProvider provider,
    OnlineMusicTrack candidate, {
    required int requestId,
  }) async {
    try {
      // Use the provider's normal playable source path. On Android this
      // downloads the candidate into the existing managed audio cache before
      // adding it to just_audio, avoiding queue entries with short-lived
      // extractor URLs that may not load when playback reaches them.
      final track = CloveTrack(
        path: candidate.sourcePage.toString(),
        title: candidate.title,
        artist: candidate.artist ?? candidate.creatorName ?? 'Unknown artist',
        album: candidate.album ?? '',
        duration: candidate.duration ?? Duration.zero,
        artworkUri: candidate.artworkUri,
        mediaId: candidate.sourcePage.toString(),
      );
      final sourceFuture = provider is CancellableOnlineRecommendationProvider
          ? (provider as CancellableOnlineRecommendationProvider)
                .resolveRecommendationSource(candidate, requestId: requestId)
          : provider.resolvePlaybackSource(candidate);
      final artworkFuture = withOfflineTrackArtwork(track);
      final source = await sourceFuture;
      final freshSource = await _freshRecommendationSource(
        provider,
        candidate,
        source,
      );
      final trackWithLocalArtwork = await artworkFuture;
      return _ResolvedRecommendation(
        candidate,
        CloveTrack(
          path: trackWithLocalArtwork.path,
          title: trackWithLocalArtwork.title,
          artist: trackWithLocalArtwork.artist,
          album: trackWithLocalArtwork.album,
          duration: trackWithLocalArtwork.duration,
          audioHeaders: freshSource.headers,
          artworkUri: trackWithLocalArtwork.artworkUri,
          mediaId: trackWithLocalArtwork.mediaId,
          sourceUri: freshSource.uri,
        ),
      );
    } on Exception catch (error) {
      _logPlaybackError('recommended track source resolution', error);
      return null;
    }
  }

  Future<DirectAudioSource> _freshRecommendationSource(
    OnlineMusicProvider provider,
    OnlineMusicTrack track,
    DirectAudioSource source,
  ) async {
    final expiry = source.expiresAt;
    if (expiry == null ||
        expiry.isAfter(DateTime.now().add(const Duration(seconds: 30)))) {
      return source;
    }
    final refreshed = provider is OnlineMusicStreamResolver
        ? await (provider as OnlineMusicStreamResolver).resolveStreamingSource(
            track,
          )
        : await provider.refreshPlaybackSource(track);
    if (refreshed.expiresAt != null &&
        !refreshed.expiresAt!.isAfter(DateTime.now())) {
      throw const OnlineMusicProviderFailure(
        kind: OnlineMusicFailureKind.sourceResolutionFailed,
        message: 'The recommended audio source expired before playback.',
      );
    }
    return refreshed;
  }

  Future<bool> _appendAutomaticRecommendations(
    List<_ResolvedRecommendation> recommendations, {
    required OnlineMusicTrack current,
    required int generation,
  }) => _serializeQueueMutation(() async {
    if (generation != _recommendationGeneration || recommendations.isEmpty) {
      return false;
    }
    final currentIndex = _player.currentIndex;
    final liveCurrent =
        currentIndex != null &&
            currentIndex >= 0 &&
            currentIndex < _tracks.length
        ? _onlineTrackFor(_tracks[currentIndex]) ?? current
        : current;
    final currentQueue = _queuedOnlineTracks();
    final automaticQueue = _upcomingAutomaticOnlineTracks();
    final previouslyPlayedIds = await _onlinePlayHistory.loadPlayedIds();
    final fresh = rankRecommendationCandidates(
      current: liveCurrent,
      candidates: recommendations.map((entry) => entry.onlineTrack),
      queued: currentQueue,
      automaticQueue: automaticQueue,
      recentHistory: _recommendationHistory,
      previouslyPlayedIds: previouslyPlayedIds,
      limit: recommendations.length,
      maxSameArtist: _smartQueueConfig.maxSameArtist,
      recentHistoryWindow: _smartQueueConfig.recentHistoryWindow,
    );
    final allowedIds = fresh
        .map((track) => '${track.providerId}:${track.id}')
        .toSet();
    final liveAdditions = recommendations
        .where(
          (entry) => allowedIds.contains(
            '${entry.onlineTrack.providerId}:${entry.onlineTrack.id}',
          ),
        )
        .toList(growable: false);
    if (liveAdditions.isEmpty) return false;
    final oldLength = _tracks.length;
    await _appendTracksToQueue(
      liveAdditions.map((entry) => entry.track).toList(growable: false),
      sourceId: 'online_youtube',
      automaticRecommendation: true,
      isStillValid: () => generation == _recommendationGeneration,
    );
    if (_tracks.length > oldLength && generation == _recommendationGeneration) {
      await _saveSessionImmediately();
    }
    return generation == _recommendationGeneration &&
        _tracks.length > oldLength;
  });

  void _scheduleRecommendationRetry(int generation) {
    if (generation != _recommendationGeneration ||
        _recommendationRetryAttempt >= 3) {
      return;
    }
    _recommendationRetryTimer?.cancel();
    const delays = [
      Duration(seconds: 3),
      Duration(seconds: 10),
      Duration(seconds: 25),
    ];
    final delay = delays[_recommendationRetryAttempt++];
    _recommendationRetryTimer = Timer(delay, () {
      if (generation == _recommendationGeneration) {
        unawaited(_maybeRefillAutomaticQueue());
      }
    });
  }

  void clearActiveSourceIfMatches(String sourceId) {
    if (_activeSourceId == sourceId) _setActiveSource(null);
  }

  int? get currentIndex {
    _ensurePlayer();
    return _player.currentIndex;
  }

  List<int> get effectiveQueueIndices {
    _ensurePlayer();
    return _player.effectiveIndices;
  }

  bool get shuffleEnabled {
    _ensurePlayer();
    return _player.shuffleModeEnabled;
  }

  LoopMode get loopMode {
    _ensurePlayer();
    return _player.loopMode;
  }

  Future<void> playTracks(
    List<CloveTrack> tracks, {
    int initialIndex = 0,
    required String sourceId,
  }) {
    late final Future<void> playback;
    final queueReady = _serializeQueueMutation(() async {
      await _replaceQueue(
        tracks,
        initialIndex: initialIndex,
        sourceId: sourceId,
        sourcePositions: List<int>.generate(tracks.length, (index) => index),
      );
      // Begin playback before releasing the mutation lock, but don't hold it
      // until the long-running play future completes.
      playback = play();
    });
    return queueReady.then((_) => playback);
  }

  /// Replaces the active queue and begins playback, returning once the queue
  /// is prepared instead of waiting for the selected track to finish.
  Future<void> startTracks(
    List<CloveTrack> tracks, {
    int initialIndex = 0,
    required String sourceId,
    void Function(Object error, StackTrace stackTrace)? onPlaybackError,
    bool Function()? shouldStart,
  }) => _serializeQueueMutation(() async {
    if (shouldStart?.call() == false) return;
    await _replaceQueue(
      tracks,
      initialIndex: initialIndex,
      sourceId: sourceId,
      sourcePositions: List<int>.generate(tracks.length, (index) => index),
    );
    if (shouldStart?.call() == false) return;
    unawaited(
      play().catchError((Object error, StackTrace stackTrace) {
        onPlaybackError?.call(error, stackTrace);
        if (kDebugMode) {
          debugPrint('CLOVE: track playback failed: $error');
        }
      }),
    );
  });

  /// Replaces the active track's remote artwork URI with its cached file URI.
  /// The track identity check prevents a late artwork download from changing
  /// the artwork for a newer song selected in the meantime.
  Future<void> updateCurrentTrackArtwork(String trackId, Uri artworkUri) =>
      _serializeQueueMutation(() async {
        final index = _player.currentIndex;
        if (index == null || index < 0 || index >= _tracks.length) return;
        final currentTrack = _tracks[index];
        if (currentTrack.path != trackId && currentTrack.mediaId != trackId) {
          return;
        }

        final updatedTrack = CloveTrack(
          path: currentTrack.path,
          title: currentTrack.title,
          artist: currentTrack.artist,
          album: currentTrack.album,
          duration: currentTrack.duration,
          albumId: currentTrack.albumId,
          dateAdded: currentTrack.dateAdded,
          audioHeaders: currentTrack.audioHeaders,
          artworkUri: artworkUri,
          mediaId: currentTrack.mediaId,
          sourceUri: currentTrack.sourceUri,
        );
        final updatedItem = _queueItems[index].copyWith(artUri: artworkUri);
        final tracks = [..._tracks]..[index] = updatedTrack;
        final items = [..._queueItems]..[index] = updatedItem;
        _tracks = List.unmodifiable(tracks);
        _queueItems = List.unmodifiable(items);
        queue.add(_queueItems);
        mediaItem.add(updatedItem);
        _scheduleSessionSave();
      });

  Future<void> _replaceQueue(
    List<CloveTrack> tracks, {
    required int initialIndex,
    required String sourceId,
    required List<int> sourcePositions,
  }) async {
    _ensurePlayer();
    _invalidateRecommendationGeneration();
    if (tracks.isEmpty) {
      throw ArgumentError('The playback queue cannot be empty.');
    }

    if (initialIndex < 0 || initialIndex >= tracks.length) {
      throw RangeError.index(initialIndex, tracks, 'initialIndex');
    }

    final nextTracks = List<CloveTrack>.unmodifiable(tracks);
    if (sourcePositions.length != nextTracks.length) {
      throw ArgumentError('sourcePositions must match the number of tracks.');
    }
    final items = _createQueueItems(
      nextTracks,
      sourceId: sourceId,
      sourcePositions: sourcePositions,
    );
    final sources = nextTracks
        .asMap()
        .entries
        .map(
          (entry) => AudioSource.uri(
            entry.value.audioUri,
            headers: entry.value.audioHeaders.isEmpty
                ? null
                : entry.value.audioHeaders,
            tag: items[entry.key],
          ),
        )
        .toList();

    _loadingQueue = true;
    _previousRestartIndex = null;
    try {
      await _player.setAudioSources(
        sources,
        initialIndex: initialIndex,
        shuffleOrder: AppendOnlyShuffleOrder(),
      );
      _tracks = nextTracks;
      _queueItems = items;
      _queueEntryIds = items
          .map((item) => item.extras!['queueEntryId']! as String)
          .toList(growable: false);
      _setActiveSource(sourceId);
      queue.add(items);
      final currentIndex = _player.currentIndex ?? initialIndex;
      mediaItem.add(items[currentIndex]);
      _scheduleSessionSave();
    } catch (_) {
      _tracks = [];
      _queueItems = [];
      _queueEntryIds = [];
      _previousRestartIndex = null;
      _setActiveSource(null);
      queue.add(const []);
      mediaItem.add(null);
      rethrow;
    } finally {
      _loadingQueue = false;
    }
    _observeRecommendationTrack(_player.currentIndex);
  }

  /// Appends one or more tracks without replacing or seeking the active queue.
  /// Duplicate entries are retained as intentional queue entries.
  Future<void> addTracksToQueue(
    List<CloveTrack> tracks, {
    String? sourceId,
    List<int>? sourcePositions,
    bool expandSourceContext = false,
  }) {
    if (tracks.isEmpty) return Future<void>.value();
    final additions = List<CloveTrack>.unmodifiable(tracks);
    return _serializeQueueMutation(() {
      _invalidateRecommendationGeneration();
      final result = _appendTracksToQueue(
        additions,
        sourceId: sourceId,
        sourcePositions: sourcePositions,
        expandSourceContext: expandSourceContext,
      );
      return result.whenComplete(
        () => _observeRecommendationTrack(_player.currentIndex),
      );
    });
  }

  /// Appends tracks when a current queue entry is loaded (also while paused),
  /// otherwise replaces the inactive queue and starts the playlist. The
  /// decision and mutation share the queue lock to avoid stream timing races.
  Future<bool> queueTracksOrStart(
    List<CloveTrack> tracks, {
    required String sourceId,
    List<int>? sourcePositions,
  }) {
    if (tracks.isEmpty) return Future<bool>.value(false);
    final additions = List<CloveTrack>.unmodifiable(tracks);
    final positions =
        sourcePositions ??
        List<int>.generate(additions.length, (index) => index);
    if (positions.length != additions.length) {
      throw ArgumentError('sourcePositions must match the number of tracks.');
    }
    return _serializeQueueMutation(() async {
      _ensurePlayer();
      final currentSourceTag = _player.sequenceState.currentSource?.tag;
      if (hasValidCurrentQueueEntry(
        currentMediaItem: currentSourceTag is MediaItem
            ? currentSourceTag
            : null,
        currentQueueIndex: _player.currentIndex,
        queue: _queueItems,
      )) {
        _invalidateRecommendationGeneration();
        await _appendTracksToQueue(
          additions,
          sourceId: sourceId,
          sourcePositions: positions,
          expandSourceContext: false,
        );
        _observeRecommendationTrack(_player.currentIndex);
        return true;
      }

      Object? lastError;
      StackTrace? lastStackTrace;
      for (
        var initialIndex = 0;
        initialIndex < additions.length;
        initialIndex++
      ) {
        try {
          await _replaceQueue(
            additions,
            initialIndex: initialIndex,
            sourceId: sourceId,
            sourcePositions: positions,
          );
          // play() completes when the track ends, so start it without making
          // the swipe operation wait for the entire song.
          unawaited(
            play().catchError((Object error, StackTrace stackTrace) {
              if (kDebugMode) {
                debugPrint('CLOVE: playlist playback failed: $error');
              }
            }),
          );
          return true;
        } catch (error, stackTrace) {
          lastError = error;
          lastStackTrace = stackTrace;
        }
      }

      Error.throwWithStackTrace(
        lastError ?? StateError('No playable playlist tracks were found.'),
        lastStackTrace ?? StackTrace.current,
      );
    });
  }

  Future<void> _appendTracksToQueue(
    List<CloveTrack> additions, {
    String? sourceId,
    List<int>? sourcePositions,
    bool expandSourceContext = false,
    bool automaticRecommendation = false,
    bool Function()? isStillValid,
  }) async {
    _ensurePlayer();
    final hadCurrentQueue = _tracks.isNotEmpty;
    final positions =
        sourcePositions ??
        List<int>.generate(additions.length, (index) => index);
    if (positions.length != additions.length) {
      throw ArgumentError('sourcePositions must match the number of tracks.');
    }
    final items = _createQueueItems(
      additions,
      sourceId: sourceId,
      sourcePositions: positions,
      expandSourceContext: expandSourceContext,
      automaticRecommendation: automaticRecommendation,
    );
    final sources = additions
        .asMap()
        .entries
        .map(
          (entry) => AudioSource.uri(
            entry.value.audioUri,
            headers: entry.value.audioHeaders.isEmpty
                ? null
                : entry.value.audioHeaders,
            tag: items[entry.key],
          ),
        )
        .toList(growable: false);

    final firstAutomaticIndex = _queueItems.indexWhere(
      (item) => item.extras?['automaticRecommendation'] == true,
    );
    final insertIndex = automaticRecommendation || firstAutomaticIndex < 0
        ? _tracks.length
        : firstAutomaticIndex;
    if (isStillValid?.call() == false) return;
    final oldCurrentIndex = _player.currentIndex;
    final oldCurrentEntryId =
        oldCurrentIndex != null &&
            oldCurrentIndex >= 0 &&
            oldCurrentIndex < _queueEntryIds.length
        ? _queueEntryIds[oldCurrentIndex]
        : null;
    _loadingQueue = true;
    try {
      try {
        await _player.insertAudioSources(insertIndex, sources);
      } catch (_) {
        // ConcatenatingAudioSource may have updated its local child list
        // before a deleted or unreadable source fails to load. Roll that
        // partial append back so the player and audio_service queue agree.
        try {
          await _player.removeAudioSourceRange(
            insertIndex,
            insertIndex + additions.length,
          );
        } catch (_) {
          // Preserve the original source-load error for the caller.
        }
        rethrow;
      }
      final currentSourceTag = _player.sequenceState.currentSource?.tag;
      Object? currentQueueEntryId;
      if (currentSourceTag is MediaItem) {
        currentQueueEntryId = currentSourceTag.extras?['queueEntryId'];
      }
      final liveEntryId = currentQueueEntryId is String
          ? currentQueueEntryId
          : null;
      if (liveEntryId != oldCurrentEntryId) {
        _invalidateRecommendationGeneration();
      }
      if (isStillValid?.call() == false) {
        try {
          await _player.removeAudioSourceRange(
            insertIndex,
            insertIndex + additions.length,
          );
        } catch (error) {
          _logPlaybackError('stale recommendation queue rollback', error);
        }
        return;
      }
      _tracks = List<CloveTrack>.unmodifiable([
        ..._tracks.take(insertIndex),
        ...additions,
        ..._tracks.skip(insertIndex),
      ]);
      _queueItems = List<MediaItem>.unmodifiable([
        ..._queueItems.take(insertIndex),
        ...items,
        ..._queueItems.skip(insertIndex),
      ]);
      _queueEntryIds = List<String>.unmodifiable([
        ..._queueEntryIds.take(insertIndex),
        ...items.map((item) => item.extras!['queueEntryId']! as String),
        ..._queueEntryIds.skip(insertIndex),
      ]);
      queue.add(_queueItems);
    } finally {
      _loadingQueue = false;
      _observeRecommendationTrack(_player.currentIndex);
    }
    final index = _player.currentIndex;
    if (hadCurrentQueue &&
        index != null &&
        index >= 0 &&
        index < _queueItems.length) {
      mediaItem.add(_queueItems[index]);
    }
    _broadcastPlaybackState();
    _scheduleSessionSave();
  }

  Future<T> _serializeQueueMutation<T>(Future<T> Function() operation) {
    final result = _queueMutationTail.then((_) => operation());
    _queueMutationTail = result.then<void>((_) {}).catchError((Object _) {});
    return result;
  }

  List<MediaItem> _createQueueItems(
    List<CloveTrack> tracks, {
    required String? sourceId,
    required List<int> sourcePositions,
    bool expandSourceContext = false,
    bool automaticRecommendation = false,
  }) => List<MediaItem>.unmodifiable(
    tracks.asMap().entries.map((entry) {
      final track = entry.value;
      final entryId = 'clove-queue-${++_queueEntryCounter}';
      final item = track.toMediaItem();
      return item.copyWith(
        id: entryId,
        extras: {
          ...?item.extras,
          'trackId': track.path,
          'canonicalTrackId': track.mediaId ?? track.path,
          if (automaticRecommendation) 'automaticRecommendation': true,
          'queueEntryId': entryId,
          ...queueSourceExtras(
            sourceId,
            position: sourcePositions[entry.key],
            expandSourceContext: expandSourceContext,
          ),
        },
      );
    }),
  );

  void _broadcastPlaybackState() {
    final playing =
        _player.playing && _player.processingState != ProcessingState.completed;
    final currentTrack = _currentTrack;
    final currentTrackIsLiked =
        currentTrack != null && _isTrackLiked(currentTrack);

    playbackState.add(
      PlaybackState(
        controls: [
          MediaControl.skipToPrevious,
          if (playing) MediaControl.pause else MediaControl.play,
          MediaControl.skipToNext,
          if (currentTrack != null)
            MediaControl.custom(
              androidIcon: currentTrackIsLiked
                  ? 'drawable/clove_notification_liked'
                  : 'drawable/clove_notification_add',
              label: currentTrackIsLiked
                  ? 'Remove from Liked Songs'
                  : 'Add to Liked Songs',
              name: 'clove_like_current_track',
              extras: {'trackId': currentTrack.path},
            ),
        ],
        androidCompactActionIndices: currentTrack == null
            ? const [0, 1, 2]
            : const [0, 1, 3],
        systemActions: const {
          MediaAction.seek,
          MediaAction.seekForward,
          MediaAction.seekBackward,
        },
        processingState: switch (_player.processingState) {
          ProcessingState.idle => AudioProcessingState.idle,
          ProcessingState.loading => AudioProcessingState.loading,
          ProcessingState.buffering => AudioProcessingState.buffering,
          ProcessingState.ready => AudioProcessingState.ready,
          ProcessingState.completed => AudioProcessingState.completed,
        },
        playing: playing,
        shuffleMode: _player.shuffleModeEnabled
            ? AudioServiceShuffleMode.all
            : AudioServiceShuffleMode.none,
        repeatMode: switch (_player.loopMode) {
          LoopMode.off => AudioServiceRepeatMode.none,
          LoopMode.one => AudioServiceRepeatMode.one,
          LoopMode.all => AudioServiceRepeatMode.all,
        },
        updatePosition: _player.position,
        bufferedPosition: _player.bufferedPosition,
        speed: _player.speed,
        queueIndex: _player.currentIndex,
      ),
    );
  }

  @override
  Future<void> play() async {
    _ensurePlayer();
    if (_tracks.isEmpty) return;

    // A completed player must seek back to the start before replaying.
    if (_player.processingState == ProcessingState.completed) {
      await _player.seek(Duration.zero);
    }

    unawaited(_maybeRefillAutomaticQueue());
    await _player.play();
    _scheduleSessionSave();
  }

  @override
  Future<void> pause() {
    _ensurePlayer();
    return _player.pause().then((_) => _scheduleSessionSave());
  }

  @override
  Future<void> customAction(String name, [Map<String, dynamic>? extras]) async {
    if (name != 'clove_like_current_track') {
      await super.customAction(name, extras);
      return;
    }

    final requestedTrackId = extras?['trackId'];
    await toggleCurrentTrackLiked(
      trackId: requestedTrackId is String ? requestedTrackId : null,
    );
  }

  Future<void> toggleCurrentTrackLiked({String? trackId}) async {
    final track = trackId == null
        ? _currentTrack
        : _tracks.where((candidate) => candidate.path == trackId).firstOrNull;
    if (track == null) return;

    final repository = PlaylistRepository(AppDatabase.instance);
    final collections = await repository
        .watchCollections(track.path, canonicalId: track.mediaId)
        .first;
    if (collections.isLiked) {
      await repository.setLiked(track, false);
      _likedTrackIds.removeAll([track.path, track.mediaId].whereType<String>());
    } else {
      final libraryTrack = await _resolveTrackForLibrary(track);
      await repository.setLiked(libraryTrack, true);
      _likedTrackIds.addAll(
        [
          track.path,
          libraryTrack.path,
          track.mediaId,
          libraryTrack.mediaId,
        ].whereType<String>(),
      );
    }
    _broadcastPlaybackState();
  }

  Future<void> addCurrentTrackToLikedSongs({String? trackId}) async {
    final track = trackId == null
        ? _currentTrack
        : _tracks.where((candidate) => candidate.path == trackId).firstOrNull;
    if (track == null || _isTrackLiked(track)) return;

    final libraryTrack = await _resolveTrackForLibrary(track);
    await PlaylistRepository(AppDatabase.instance).setLiked(libraryTrack, true);
    _likedTrackIds.addAll(
      [
        track.path,
        libraryTrack.path,
        track.mediaId,
        libraryTrack.mediaId,
      ].whereType<String>(),
    );
    _broadcastPlaybackState();
  }

  bool _isTrackLiked(CloveTrack track) =>
      _likedTrackIds.contains(track.path) ||
      (track.mediaId != null && _likedTrackIds.contains(track.mediaId));

  Future<CloveTrack> _resolveTrackForLibrary(CloveTrack track) {
    final provider = onlineMusicProvider;
    return provider == null
        ? Future.value(track)
        : resolvePlayableLibraryTrack(track, provider);
  }

  @override
  Future<void> click([MediaButton button = MediaButton.media]) {
    if (kDebugMode) {
      debugPrint('CLOVE: audio_service media button received: $button');
    }
    return super.click(button);
  }

  @override
  Future<void> stop() {
    final taskRemoval = _taskRemoval;
    if (taskRemoval != null) return taskRemoval;

    return _serializeLifecycle(() async {
      _invalidateRecommendationGeneration();
      _observedRecommendationTrackKey = null;
      await _player.stop();
      _tracks = [];
      _queueItems = [];
      _queueEntryIds = [];
      _previousRestartIndex = null;
      _setActiveSource(null);
      queue.add(const []);
      mediaItem.add(null);
      await _clearPersistedSession();
      await super.stop();
    });
  }

  /// audio_service calls this from Android's Service.onTaskRemoved callback
  /// when the user dismisses Clove's task from Recents. Save the session first,
  /// then pause and stop the media service so the task and its media controls
  /// can be removed. The database snapshot remains available for the next app
  /// launch, and Android may still kill the process without this callback.
  @override
  Future<void> onTaskRemoved() =>
      _taskRemoval ??= _serializeLifecycle(() async {
        _invalidateRecommendationGeneration();
        _observedRecommendationTrackKey = null;
        await _saveSessionImmediately();
        await _shutdownAfterTaskRemoval();
      });

  /// Restores the last queue without starting playback. Existing service state
  /// wins when Android has kept the media service alive across the activity.
  Future<void> restorePersistentSession() async {
    _ensurePlayer();
    if (_tracks.isNotEmpty) return;
    String? payload;
    try {
      payload = await AppDatabase.instance.loadPlaybackSession();
    } catch (error) {
      if (kDebugMode) {
        debugPrint('CLOVE: Could not load playback session: $error');
      }
      return;
    }
    if (payload == null || payload.isEmpty) return;

    Map<String, dynamic> saved;
    try {
      saved = jsonDecode(payload) as Map<String, dynamic>;
    } catch (_) {
      await AppDatabase.instance.clearPlaybackSession();
      return;
    }
    final savedQueue = saved['queue'];
    if (savedQueue is! List || savedQueue.isEmpty) return;

    final tracks = <CloveTrack>[];
    final queueItems = <MediaItem>[];
    final oldToNew = <int, int>{};
    for (var oldIndex = 0; oldIndex < savedQueue.length; oldIndex++) {
      try {
        final entry = Map<String, dynamic>.from(savedQueue[oldIndex] as Map);
        final trackData = Map<String, dynamic>.from(entry['track'] as Map);
        final track = trackFromPlaybackSessionJson(trackData);
        if (!canRestorePlaybackTrack(track)) continue;
        final extras = Map<String, dynamic>.from(
          (entry['extras'] as Map?)?.cast<String, dynamic>() ?? const {},
        );
        final queueId =
            entry['queueId'] as String? ?? 'clove-restored-${oldIndex + 1}';
        tracks.add(track);
        queueItems.add(
          track.toMediaItem().copyWith(
            id: queueId,
            extras: {
              ...?track.toMediaItem().extras,
              ...extras,
              'trackId': track.path,
              'canonicalTrackId': track.mediaId ?? track.path,
              'queueEntryId': queueId,
            },
          ),
        );
        oldToNew[oldIndex] = tracks.length - 1;
      } catch (_) {
        // Skip malformed entries while keeping the valid queue in order.
      }
    }
    if (tracks.isEmpty) {
      await AppDatabase.instance.clearPlaybackSession();
      return;
    }

    final storedIndex = (saved['index'] as num?)?.toInt() ?? 0;
    final selectedIndex =
        oldToNew[storedIndex] ??
        oldToNew.entries
            .where((entry) => entry.key >= storedIndex)
            .firstOrNull
            ?.value ??
        0;
    final rawShuffle = saved['shuffleIndices'];
    final shuffleIndices = <int>[];
    if (rawShuffle is List) {
      for (final oldIndex in rawShuffle.whereType<num>().map(
        (n) => n.toInt(),
      )) {
        final mapped = oldToNew[oldIndex];
        if (mapped != null && !shuffleIndices.contains(mapped)) {
          shuffleIndices.add(mapped);
        }
      }
    }
    for (var i = 0; i < tracks.length; i++) {
      if (!shuffleIndices.contains(i)) shuffleIndices.add(i);
    }

    _restoringSession = true;
    _loadingQueue = true;
    try {
      await _player.setAudioSources(
        queueItems
            .asMap()
            .entries
            .map(
              (entry) => AudioSource.uri(
                tracks[entry.key].audioUri,
                headers: tracks[entry.key].audioHeaders.isEmpty
                    ? null
                    : tracks[entry.key].audioHeaders,
                tag: entry.value,
              ),
            )
            .toList(growable: false),
        initialIndex: selectedIndex,
        initialPosition: Duration(
          milliseconds: ((saved['positionMs'] as num?)?.toInt() ?? 0).clamp(
            0,
            tracks[selectedIndex].duration.inMilliseconds > 0
                ? tracks[selectedIndex].duration.inMilliseconds
                : 1 << 31,
          ),
        ),
        shuffleOrder: _RestoredShuffleOrder(shuffleIndices),
      );
      _tracks = List.unmodifiable(tracks);
      _queueItems = List.unmodifiable(queueItems);
      _queueEntryIds = queueItems
          .map((item) => item.extras!['queueEntryId']! as String)
          .toList(growable: false);
      _queueEntryCounter = queueItems.fold<int>(0, (maximum, item) {
        final id = item.id;
        final suffix = int.tryParse(id.substring(id.lastIndexOf('-') + 1));
        return suffix != null && suffix > maximum ? suffix : maximum;
      });
      queue.add(_queueItems);
      mediaItem.add(_queueItems[selectedIndex]);
      _setActiveSource(activeSourceForQueueIndex(_queueItems, selectedIndex));
      final repeatIndex = ((saved['repeatMode'] as num?)?.toInt() ?? 0).clamp(
        0,
        LoopMode.values.length - 1,
      );
      await _player.setLoopMode(LoopMode.values[repeatIndex]);
      await _player.setShuffleModeEnabled(saved['shuffleEnabled'] == true);
      _broadcastPlaybackState();
    } catch (error) {
      _tracks = [];
      _queueItems = [];
      _queueEntryIds = [];
      queue.add(const []);
      mediaItem.add(null);
      if (kDebugMode) {
        debugPrint('CLOVE: Could not restore playback session: $error');
      }
    } finally {
      _loadingQueue = false;
      _restoringSession = false;
    }
    if (_tracks.isNotEmpty) {
      _scheduleSessionSave();
      _observeRecommendationTrack(_player.currentIndex);
    }
  }

  Map<String, dynamic>? _sessionSnapshot() {
    if (_tracks.isEmpty || _queueItems.length != _tracks.length) return null;
    final index = _player.currentIndex;
    if (index == null || index < 0 || index >= _tracks.length) return null;
    return {
      'queue': [
        for (var i = 0; i < _tracks.length; i++)
          {
            'track': trackToPlaybackSessionJson(_tracks[i]),
            'queueId': _queueItems[i].id,
            'extras': _queueItems[i].extras ?? const {},
          },
      ],
      'index': index,
      'positionMs': _player.position.inMilliseconds,
      'shuffleEnabled': _player.shuffleModeEnabled,
      'shuffleIndices': _player.shuffleIndices,
      'repeatMode': _player.loopMode.index,
    };
  }

  void _scheduleSessionSave() {
    if (_restoringSession) return;
    final snapshot = _sessionSnapshot();
    if (snapshot == null) return;
    _enqueueSessionWrite(
      () => AppDatabase.instance.savePlaybackSession(jsonEncode(snapshot)),
    );
  }

  Future<void> _saveSessionImmediately() {
    final snapshot = _sessionSnapshot();
    if (snapshot == null) return _sessionWriteTail;
    return _enqueueSessionWrite(
      () => AppDatabase.instance.savePlaybackSession(jsonEncode(snapshot)),
    );
  }

  Future<void> _clearPersistedSession() =>
      _enqueueSessionWrite(AppDatabase.instance.clearPlaybackSession);

  Future<void> _enqueueSessionWrite(Future<void> Function() write) {
    final version = ++_sessionWriteVersion;
    final next = _sessionWriteTail.then((_) async {
      if (version != _sessionWriteVersion) return;
      await write();
    });
    _sessionWriteTail = next.catchError((Object error) {
      if (kDebugMode) {
        debugPrint('CLOVE: Playback session persistence failed: $error');
      }
    });
    return _sessionWriteTail;
  }

  Future<void> _serializeLifecycle(Future<void> Function() operation) {
    final result = _lifecycleTail.then((_) => operation());
    _lifecycleTail = result.catchError((Object _) {});
    return result;
  }

  Future<void> _shutdownAfterTaskRemoval() async {
    // Keep the already-saved database session, but clear live media state so
    // Android removes the playback notification and releases the service.
    _tracks = [];
    _positionSaveTimer?.cancel();
    _positionSaveTimer = null;
    _queueItems = [];
    _queueEntryIds = [];
    _previousRestartIndex = null;
    _setActiveSource(null);
    queue.add(const []);
    mediaItem.add(null);

    await _cleanupStep('stop player', _player.stop);
    await _cleanupStep('cancel player subscriptions', () async {
      await _playbackEventSubscription?.cancel();
      await _playerStateSubscription?.cancel();
      await _playerErrorSubscription?.cancel();
      await _currentIndexSubscription?.cancel();
      await _likedTracksSubscription?.cancel();
      _playbackEventSubscription = null;
      _playerStateSubscription = null;
      _playerErrorSubscription = null;
      _currentIndexSubscription = null;
      _likedTracksSubscription = null;
    });
    await _cleanupStep('dispose player', _player.dispose);
    _playerDisposed = true;
    await _cleanupStep('deactivate audio session', () async {
      final session = await AudioSession.instance;
      await session.setActive(false);
    });
    await _cleanupStep('stop audio service', super.stop);
  }

  Future<void> _cleanupStep(
    String label,
    Future<void> Function() action,
  ) async {
    try {
      await action();
    } catch (error, stackTrace) {
      if (kDebugMode) {
        debugPrint('CLOVE: Failed to $label after task removal: $error');
        debugPrintStack(stackTrace: stackTrace);
      }
    }
  }

  @override
  Future<void> seek(Duration position) {
    _ensurePlayer();
    return _player.seek(position).then((_) => _scheduleSessionSave());
  }

  @override
  Future<void> skipToQueueItem(int index) => _serializeQueueMutation(() async {
    _ensurePlayer();
    await _playQueueItemAt(index);
  });

  Future<void> playQueueEntry(MediaItem item) async {
    final queueEntryId = item.extras?['queueEntryId'];
    if (queueEntryId is! String) return;
    await _serializeQueueMutation(() async {
      final index = queueEntryIndex(_queueItems, queueEntryId);
      await _playQueueItemAt(index);
    });
  }

  Future<void> _playQueueItemAt(int index) async {
    _ensurePlayer();
    if (!isQueueIndexValid(index, _tracks.length)) return;
    _previousRestartIndex = null;
    await _player.seek(Duration.zero, index: index);
    await _player.play();
  }

  @override
  Future<void> removeQueueItem(MediaItem mediaItem) async {
    final queueEntryId = mediaItem.extras?['queueEntryId'];
    if (queueEntryId is! String) return;
    await _removeUpcomingQueueEntry(queueEntryId);
  }

  @override
  Future<void> removeQueueItemAt(int index) async {
    final queueEntryId = index >= 0 && index < _queueEntryIds.length
        ? _queueEntryIds[index]
        : null;
    if (queueEntryId == null) return;
    await _removeUpcomingQueueEntry(queueEntryId);
  }

  Future<bool> removeUpcomingQueueItem(MediaItem item) async {
    final queueEntryId = item.extras?['queueEntryId'];
    if (queueEntryId is! String) return false;
    return _removeUpcomingQueueEntry(queueEntryId);
  }

  Future<bool> _removeUpcomingQueueEntry(String queueEntryId) =>
      _serializeQueueMutation(() async {
        _ensurePlayer();
        final currentIndex = _player.currentIndex;
        if (currentIndex == null ||
            !isQueueIndexValid(currentIndex, _queueItems.length)) {
          return false;
        }
        final targetIndex = queueEntryIndex(_queueItems, queueEntryId);
        if (targetIndex < 0 ||
            targetIndex == currentIndex ||
            !isQueueIndexUpcoming(
              targetIndex,
              currentIndex,
              _player.effectiveIndices,
            )) {
          return false;
        }

        _invalidateRecommendationGeneration();
        final currentEntryId = _queueEntryIds[currentIndex];
        _loadingQueue = true;
        try {
          await _player.removeAudioSourceAt(targetIndex);
          _tracks = List<CloveTrack>.unmodifiable([
            ..._tracks.take(targetIndex),
            ..._tracks.skip(targetIndex + 1),
          ]);
          _queueItems = List<MediaItem>.unmodifiable([
            ..._queueItems.take(targetIndex),
            ..._queueItems.skip(targetIndex + 1),
          ]);
          _queueEntryIds = List<String>.unmodifiable([
            ..._queueEntryIds.take(targetIndex),
            ..._queueEntryIds.skip(targetIndex + 1),
          ]);
          queue.add(_queueItems);

          final liveCurrentIndex = _player.currentIndex;
          if (liveCurrentIndex != null &&
              isQueueIndexValid(liveCurrentIndex, _queueItems.length)) {
            mediaItem.add(_queueItems[liveCurrentIndex]);
          } else {
            mediaItem.add(null);
          }
          return _queueEntryIds.contains(currentEntryId);
        } finally {
          _loadingQueue = false;
          _broadcastPlaybackState();
          _scheduleSessionSave();
          _observeRecommendationTrack(_player.currentIndex);
        }
      });

  @override
  Future<void> skipToNext() => _serializeQueueMutation(() async {
    _ensurePlayer();
    if (_tracks.isEmpty || _player.currentIndex == null) return;
    await _player.seekToNext();
  });

  @override
  Future<void> skipToPrevious() {
    _ensurePlayer();
    final operation = _previousCommandTail.then(
      (_) => _serializeQueueMutation(_handlePrevious),
    );
    _previousCommandTail = operation.catchError((Object _) {});
    return operation;
  }

  Future<void> _handlePrevious() async {
    if (_loadingQueue || _tracks.isEmpty) return;

    final currentIndex = _player.currentIndex;
    if (currentIndex == null ||
        !isQueueIndexValid(currentIndex, _tracks.length)) {
      return;
    }

    final alreadyRestarted = _previousRestartIndex == currentIndex;
    final previousIndex = _player.previousIndex;
    final action = decidePreviousTrackAction(
      hasCurrentTrack: true,
      hasPreviousTrack: previousIndex != null,
      position: _player.position,
      currentTrackWasRestartedByPrevious: alreadyRestarted,
    );

    switch (action) {
      case PreviousTrackAction.none:
        return;
      case PreviousTrackAction.restartCurrent:
        // just_audio updates its position synchronously when seek begins. Keep
        // this index armed as well, so a rapid/repeated command cannot use a
        // stale position and restart this same item indefinitely.
        await _player.seek(Duration.zero, index: currentIndex);
        _previousRestartIndex = currentIndex;
        return;
      case PreviousTrackAction.previousTrack:
        if (previousIndex == null) {
          await _player.seek(Duration.zero, index: currentIndex);
          _previousRestartIndex = currentIndex;
          return;
        }
        await _player.seek(Duration.zero, index: previousIndex);
        _previousRestartIndex = null;
    }
  }

  @override
  Future<void> playFromMediaId(
    String mediaId, [
    Map<String, dynamic>? extras,
  ]) async {
    final queueIndex = _queueItems.indexWhere((item) => item.id == mediaId);
    final index = queueIndex >= 0
        ? queueIndex
        : _tracks.indexWhere((track) => track.path == mediaId);
    if (index < 0) return;
    await skipToQueueItem(index);
  }

  @override
  Future<void> playMediaItem(MediaItem mediaItem) async {
    await playFromMediaId(mediaItem.id);
  }

  @override
  Future<void> seekForward(bool begin) async {
    if (!begin) return;
    final target = _player.position + const Duration(seconds: 10);
    final duration = _player.duration;
    await seek(duration != null && target > duration ? duration : target);
  }

  @override
  Future<void> seekBackward(bool begin) async {
    if (!begin) return;
    final target = _player.position - const Duration(seconds: 10);
    await seek(target.isNegative ? Duration.zero : target);
  }

  Future<void> setShuffleEnabled(bool enabled) async {
    _ensurePlayer();
    if (enabled && !_player.shuffleModeEnabled) await _player.shuffle();
    await _player.setShuffleModeEnabled(enabled);
    _broadcastPlaybackState();
    _scheduleSessionSave();
  }

  Future<void> setLoopMode(LoopMode mode) async {
    _ensurePlayer();
    await _player.setLoopMode(mode);
    _broadcastPlaybackState();
    _scheduleSessionSave();
  }

  @override
  Future<void> setRepeatMode(AudioServiceRepeatMode repeatMode) =>
      setLoopMode(switch (repeatMode) {
        AudioServiceRepeatMode.one => LoopMode.one,
        AudioServiceRepeatMode.all => LoopMode.all,
        _ => LoopMode.off,
      });

  @override
  Future<void> setShuffleMode(AudioServiceShuffleMode shuffleMode) =>
      setShuffleEnabled(shuffleMode != AudioServiceShuffleMode.none);
}

class _ResolvedRecommendation {
  const _ResolvedRecommendation(this.onlineTrack, this.track);

  final OnlineMusicTrack onlineTrack;
  final CloveTrack track;
}

class _RestoredShuffleOrder extends DefaultShuffleOrder {
  _RestoredShuffleOrder(this._savedIndices);

  final List<int> _savedIndices;
  bool _restoringFirstInsert = true;

  @override
  void clear() {
    indices.clear();
    _restoringFirstInsert = true;
  }

  @override
  void insert(int index, int count) {
    if (_restoringFirstInsert && index == 0) {
      _restoringFirstInsert = false;
      indices.addAll(
        _savedIndices.where((value) => value >= 0 && value < count),
      );
      for (var value = 0; value < count; value++) {
        if (!indices.contains(value)) indices.add(value);
      }
      return;
    }
    super.insert(index, count);
  }
}
