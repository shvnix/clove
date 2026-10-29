import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';
import 'package:ytdlp_flutter/ytdlp_flutter.dart';

import '../data/database.dart';
import '../models/online_music_track.dart';
import 'audio/smart_music_queue.dart';
import 'audio/playback_service.dart';
import 'online_music_provider.dart';
import 'serial_task_queue.dart';

const _audioOnlyTargetBitrate = 160000;
const _maxCachedStreamUrls = 20;
const _maxCachedAudioFiles = 50;
const _androidAudioDownloadTimeout = Duration(minutes: 2);
const _ytdlpCancelTimeout = Duration(seconds: 5);

class _CachedStream {
  const _CachedStream(this.url, this.expiresAt);

  final Uri url;
  final DateTime? expiresAt;

  bool get isUsable =>
      url.scheme == 'https' &&
      url.host.isNotEmpty &&
      (expiresAt == null || expiresAt!.isAfter(DateTime.now()));
}

class YoutubeMusicProvider
    implements
        OnlineMusicProvider,
        OnlineMusicDiscoveryProvider,
        CancellableOnlineRecommendationProvider,
        OnlineMusicStreamResolver,
        CancellableOnlineMusicProvider,
        OfflineMusicDownloader {
  YoutubeMusicProvider({YoutubeExplode? youtube})
    : _youtube = youtube ?? YoutubeExplode();

  final YoutubeExplode _youtube;
  final Map<String, _CachedStream> _streamCache = {};
  final Map<int, YoutubeExplode> _recommendationClients = {};
  final Map<int, String> _recommendationTaskIds = {};
  final Map<int, Completer<void>> _recommendationCancellations = {};
  final Set<int> _cancelledRecommendationRequests = {};
  final Map<String, String> _audioFileCache = {};
  final Map<String, int> _audioPlayCounts = {};
  Future<void>? _ytdlpInitialization;
  Future<void>? _audioCacheInitialization;
  final SerialTaskQueue _androidDownloadQueue = SerialTaskQueue();
  Future<void> _metadataWriteTail = Future<void>.value();
  StreamSubscription? _mediaItemSubscription;
  StreamSubscription? _playbackStateSubscription;
  Directory? _audioCacheDirectory;
  String? _activeTaskId;
  String? _lastCountedQueueEntryId;
  String? _currentQueueEntryId;
  String? _currentSourceId;
  String? _currentTrackId;
  bool _isPlaybackPlaying = false;
  int _requestCounter = 0;

  bool get _isAndroid =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  @override
  String get id => 'youtube';

  @override
  Future<OnlineMusicPage> search(String query, {String? pageToken}) async {
    final normalized = query.trim();
    if (normalized.isEmpty || pageToken != null) {
      return const OnlineMusicPage(tracks: []);
    }

    try {
      final videos = await _youtube.search
          .search(normalized)
          .timeout(const Duration(seconds: 35));
      final results = videos
          .take(20)
          .map(
            (video) => OnlineMusicTrack(
              providerId: 'youtube',
              id: video.id.value,
              title: video.title,
              artist: video.author,
              uploaderName: video.author,
              artworkUri: Uri.tryParse(video.thumbnails.highResUrl),
              sourcePageUri: Uri.https('www.youtube.com', '/watch', {
                'v': video.id.value,
              }),
              duration: video.duration,
            ),
          )
          .toList(growable: false);
      if (results.isNotEmpty || !_isAndroid) {
        return OnlineMusicPage(tracks: results);
      }
    } on Exception {
      if (!_isAndroid) {
        throw const OnlineMusicProviderFailure(
          kind: OnlineMusicFailureKind.searchFailed,
          message: 'Search is temporarily unavailable. Check your connection and try again.',
        );
      }
    }

    if (_isAndroid) {
      try {
        await (_ytdlpInitialization ??= Ytdlp.init());
        final info = await Ytdlp.getVideoInfo('ytsearch1:$normalized');
        if (info.id.isNotEmpty) {
          return OnlineMusicPage(
            tracks: [
              OnlineMusicTrack(
                providerId: 'youtube',
                id: info.id,
                title: info.title,
                artist: info.uploader ?? 'Unknown artist',
                uploaderName: info.uploader,
                artworkUri: Uri.tryParse(
                  info.thumbnailUrl ??
                      'https://i.ytimg.com/vi/${info.id}/hqdefault.jpg',
                ),
                sourcePageUri: Uri.https('www.youtube.com', '/watch', {
                  'v': info.id,
                }),
                duration: info.durationSeconds == null
                    ? null
                    : Duration(seconds: info.durationSeconds!.round()),
              ),
            ],
          );
        }
      } on Exception {
        throw const OnlineMusicProviderFailure(
          kind: OnlineMusicFailureKind.searchFailed,
          message: 'Search is temporarily unavailable. Check your connection and try again.',
        );
      }
    }
    return const OnlineMusicPage(tracks: []);
  }

  @override
  Future<List<OnlineMusicTrack>> discoverRelated(OnlineMusicTrack track) async {
    final results = await Future.wait([
      _discoverRelatedVideos(track),
      _discoverBySearch(track),
    ]);
    final seen = <String>{};
    return results
        .expand((tracks) => tracks)
        .where(
          (candidate) => seen.add('${candidate.providerId}:${candidate.id}'),
        )
        .toList(growable: false);
  }

  @override
  Future<List<OnlineMusicTrack>> discoverRecommendations(
    OnlineMusicTrack track, {
    required int requestId,
  }) async {
    if (_cancelledRecommendationRequests.contains(requestId)) return const [];
    final client = YoutubeExplode();
    _recommendationClients[requestId] = client;
    try {
      final results = await Future.wait([
        _discoverRelatedVideos(track, youtube: client),
        _discoverBySearch(track, youtube: client),
      ]);
      if (_cancelledRecommendationRequests.contains(requestId)) return const [];
      final seen = <String>{};
      return results
          .expand((tracks) => tracks)
          .where(
            (candidate) => seen.add('${candidate.providerId}:${candidate.id}'),
          )
          .toList(growable: false);
    } finally {
      if (identical(_recommendationClients[requestId], client)) {
        _recommendationClients.remove(requestId);
        client.close();
      }
      _cancelledRecommendationRequests.remove(requestId);
    }
  }

  Future<List<OnlineMusicTrack>> _discoverRelatedVideos(
    OnlineMusicTrack track, {
    YoutubeExplode? youtube,
  }) async {
    final client = youtube ?? _youtube;
    try {
      final seed = await client.videos
          .get(VideoId(track.id))
          .timeout(const Duration(seconds: 20));
      final related = await client.videos
          .getRelatedVideos(seed)
          .timeout(const Duration(seconds: 25));
      return related
              ?.take(30)
              .map(
                (video) => OnlineMusicTrack(
                  providerId: 'youtube',
                  id: video.id.value,
                  title: video.title,
                  artist: video.author,
                  uploaderName: video.author,
                  artworkUri: Uri.tryParse(video.thumbnails.highResUrl),
                  sourcePageUri: Uri.https('www.youtube.com', '/watch', {
                    'v': video.id.value,
                  }),
                  duration: video.duration,
                  tags: video.keywords.toList(growable: false),
                ),
              )
              .toList(growable: false) ??
          const [];
    } on Exception {
      if (kDebugMode) {
        debugPrint('CLOVE: YouTube related-video discovery failed.');
      }
      return const [];
    }
  }

  Future<List<OnlineMusicTrack>> _discoverBySearch(
    OnlineMusicTrack track, {
    YoutubeExplode? youtube,
  }) async {
    final queries = recommendationSearchQueries(track);
    final pages = await Future.wait(
      queries.map((query) async {
        try {
          final videos = await (youtube ?? _youtube).search
              .search(query)
              .timeout(const Duration(seconds: 22));
          return OnlineMusicPage(
            tracks: videos.take(20).map(_videoToTrack).toList(growable: false),
          );
        } on Exception {
          if (kDebugMode) {
            debugPrint(
              'CLOVE: an online recommendation search request failed.',
            );
          }
          return const OnlineMusicPage(tracks: []);
        }
      }),
    );
    return pages.expand((page) => page.tracks).toList(growable: false);
  }

  OnlineMusicTrack _videoToTrack(Video video) => OnlineMusicTrack(
    providerId: 'youtube',
    id: video.id.value,
    title: video.title,
    artist: video.author,
    uploaderName: video.author,
    artworkUri: Uri.tryParse(video.thumbnails.highResUrl),
    sourcePageUri: Uri.https('www.youtube.com', '/watch', {
      'v': video.id.value,
    }),
    duration: video.duration,
    tags: video.keywords.toList(growable: false),
  );

  @override
  Future<DirectAudioSource> resolveRecommendationSource(
    OnlineMusicTrack track, {
    required int requestId,
  }) async {
    if (_cancelledRecommendationRequests.contains(requestId)) {
      throw const OnlineMusicProviderFailure(
        kind: OnlineMusicFailureKind.sourceResolutionFailed,
        message: 'Recommendation preparation was cancelled.',
      );
    }
    _recommendationCancellations.putIfAbsent(requestId, Completer<void>.new);
    try {
      if (_isAndroid) {
        try {
          return await _downloadAndroidAudio(
            track,
            recommendationRequestId: requestId,
          );
        } on Exception {
          if (_cancelledRecommendationRequests.contains(requestId)) rethrow;
        }
      }
      final client = YoutubeExplode();
      _recommendationClients[requestId] = client;
      try {
        final source = await _resolveStream(track, youtube: client);
        if (_cancelledRecommendationRequests.contains(requestId)) {
          throw const OnlineMusicProviderFailure(
            kind: OnlineMusicFailureKind.sourceResolutionFailed,
            message: 'Recommendation preparation was cancelled.',
          );
        }
        return source;
      } finally {
        if (identical(_recommendationClients[requestId], client)) {
          _recommendationClients.remove(requestId);
          client.close();
        }
      }
    } finally {
      _cancelledRecommendationRequests.remove(requestId);
      _recommendationCancellations.remove(requestId);
    }
  }

  @override
  Future<void> cancelRecommendationRequest(int requestId) async {
    final hasPendingWork =
        _recommendationClients.containsKey(requestId) ||
        _recommendationTaskIds.containsKey(requestId) ||
        _recommendationCancellations.containsKey(requestId);
    if (!hasPendingWork) return;
    _cancelledRecommendationRequests.add(requestId);
    final cancellation = _recommendationCancellations[requestId];
    if (cancellation != null && !cancellation.isCompleted) {
      cancellation.complete();
    }
    _recommendationClients.remove(requestId)?.close();
    final taskId = _recommendationTaskIds.remove(requestId);
    if (taskId != null) {
      if (_activeTaskId == taskId) _activeTaskId = null;
      await _cancelYtdlpTask(taskId);
    }
  }

  @override
  Future<DirectAudioSource> resolveStreamingSource(OnlineMusicTrack track) =>
      _resolveStream(track);

  @override
  Future<DirectAudioSource> resolvePlaybackSource(
    OnlineMusicTrack track,
  ) async {
    if (_isAndroid) {
      try {
        return await _downloadAndroidAudio(track);
      } on Exception {
        // A direct stream still lets queued songs play when the Android
        // download runtime is unavailable or cannot prepare a temporary file.
        return _resolveStream(track);
      }
    }
    return _resolveStream(track);
  }

  @override
  Future<DirectAudioSource> refreshPlaybackSource(
    OnlineMusicTrack track,
  ) async {
    _streamCache.remove(track.id);
    _audioFileCache.remove(track.id);
    return resolvePlaybackSource(track);
  }

  @override
  Future<DirectAudioSource> downloadForOffline(OnlineMusicTrack track) async {
    return _downloadAndroidAudio(track);
  }

  @override
  Future<String?> findOfflineAudioPath(OnlineMusicTrack track) async {
    await (_audioCacheInitialization ??= _initializeAudioCache());
    final path = _audioFileCache[track.id];
    if (path == null || !await File(path).exists()) return null;
    return path;
  }

  Future<DirectAudioSource> _downloadAndroidAudio(
    OnlineMusicTrack track, {
    int? recommendationRequestId,
  }) async {
    // Check the local cache before entering the serialized download queue. A
    // stalled download must never block playback of an already cached song.
    await (_audioCacheInitialization ??= _initializeAudioCache());
    final cachedPath = _audioFileCache[track.id];
    if (cachedPath != null && await File(cachedPath).exists()) {
      return DirectAudioSource(
        uri: Uri.file(cachedPath),
        isAppManagedFile: true,
      );
    }

    if (recommendationRequestId != null &&
        _cancelledRecommendationRequests.contains(recommendationRequestId)) {
      throw const OnlineMusicProviderFailure(
        kind: OnlineMusicFailureKind.sourceResolutionFailed,
        message: 'Recommendation preparation was cancelled.',
      );
    }
    return _androidDownloadQueue.run(() {
      if (recommendationRequestId != null &&
          _cancelledRecommendationRequests.contains(recommendationRequestId)) {
        throw const OnlineMusicProviderFailure(
          kind: OnlineMusicFailureKind.sourceResolutionFailed,
          message: 'Recommendation preparation was cancelled.',
        );
      }
      return _downloadAndroidAudioNow(
        track,
        recommendationRequestId: recommendationRequestId,
      );
    });
  }

  Future<DirectAudioSource> _downloadAndroidAudioNow(
    OnlineMusicTrack track, {
    int? recommendationRequestId,
  }) async {
    await (_ytdlpInitialization ??= Ytdlp.init());
    await (_audioCacheInitialization ??= _initializeAudioCache());
    _startPlaybackTracking();
    final audioDirectory = _audioCacheDirectory;
    if (audioDirectory == null) {
      throw const OnlineMusicProviderFailure(
        kind: OnlineMusicFailureKind.sourceResolutionFailed,
        message: 'Could not open the persistent audio cache.',
      );
    }
    final cachedPath = _audioFileCache[track.id];
    if (cachedPath != null && await File(cachedPath).exists()) {
      return DirectAudioSource(
        uri: Uri.file(cachedPath),
        isAppManagedFile: true,
      );
    }

    if (!await _makeRoomForDownload(track.id)) {
      throw const OnlineMusicProviderFailure(
        kind: OnlineMusicFailureKind.sourceResolutionFailed,
        message: 'The online audio cache is full of queued songs.',
      );
    }
    final taskId = 'clove_${track.id}_${++_requestCounter}';
    _activeTaskId = taskId;
    if (recommendationRequestId != null) {
      _recommendationTaskIds[recommendationRequestId] = taskId;
      _recommendationCancellations.putIfAbsent(
        recommendationRequestId,
        Completer<void>.new,
      );
    }
    try {
      final nativeDownload = Ytdlp.downloadAudio(
        url: track.sourcePage.toString(),
        outputDir: audioDirectory.path,
        taskId: taskId,
      );
      late final String path;
      try {
        final download = nativeDownload.timeout(_androidAudioDownloadTimeout);
        final cancellation = recommendationRequestId == null
            ? null
            : _recommendationCancellations[recommendationRequestId];
        path = cancellation == null
            ? await download
            : await Future.any([
                download,
                cancellation.future.then<String>((_) {
                  throw const OnlineMusicProviderFailure(
                    kind: OnlineMusicFailureKind.sourceResolutionFailed,
                    message: 'Recommendation preparation was cancelled.',
                  );
                }),
              ]);
      } on TimeoutException {
        if (_activeTaskId == taskId) _activeTaskId = null;
        unawaited(
          nativeDownload.then<void>(
            (latePath) => _deleteFile(latePath),
            onError: (Object _) {},
          ),
        );
        await _cancelYtdlpTask(taskId);
        throw const OnlineMusicProviderFailure(
          kind: OnlineMusicFailureKind.sourceResolutionFailed,
          message: 'Audio preparation timed out. Retrying with a stream.',
        );
      }
      if (_activeTaskId != taskId) {
        await _deleteFile(path);
        throw const OnlineMusicProviderFailure(
          kind: OnlineMusicFailureKind.sourceResolutionFailed,
          message: 'Playback request was cancelled.',
        );
      }
      _audioFileCache[track.id] = path;
      _audioPlayCounts.putIfAbsent(track.id, () => 0);
      await _saveAudioCacheMetadata();
      return DirectAudioSource(uri: Uri.file(path), isAppManagedFile: true);
    } on OnlineMusicProviderFailure {
      rethrow;
    } on Exception {
      throw const OnlineMusicProviderFailure(
        kind: OnlineMusicFailureKind.sourceResolutionFailed,
        message:
            'Could not prepare audio. Check your connection and try again.',
      );
    } finally {
      if (_activeTaskId == taskId) _activeTaskId = null;
      if (recommendationRequestId != null &&
          _recommendationTaskIds[recommendationRequestId] == taskId) {
        _recommendationTaskIds.remove(recommendationRequestId);
      }
    }
  }

  Future<DirectAudioSource> _resolveStream(
    OnlineMusicTrack track, {
    YoutubeExplode? youtube,
  }) async {
    final cached = _streamCache.remove(track.id);
    if (cached != null && cached.isUsable) {
      _streamCache[track.id] = cached;
      return DirectAudioSource(uri: cached.url, expiresAt: cached.expiresAt);
    }

    try {
      final manifest = await (youtube ?? _youtube).videos.streams
          .getManifest(VideoId(track.id))
          .timeout(const Duration(seconds: 35));
      final streams = manifest.audioOnly.toList()
        ..sort((left, right) {
          final leftRate = left.bitrate.bitsPerSecond;
          final rightRate = right.bitrate.bitsPerSecond;
          final leftInRange = leftRate <= _audioOnlyTargetBitrate;
          final rightInRange = rightRate <= _audioOnlyTargetBitrate;
          if (leftInRange != rightInRange) return leftInRange ? -1 : 1;
          return leftInRange
              ? rightRate.compareTo(leftRate)
              : leftRate.compareTo(rightRate);
        });
      if (streams.isEmpty) {
        throw const OnlineMusicProviderFailure(
          kind: OnlineMusicFailureKind.sourceResolutionFailed,
          message: 'No playable audio stream is available for this result.',
        );
      }
      final stream = streams.firstWhere(
        (candidate) =>
            _streamExpiry(candidate.url)?.isAfter(DateTime.now()) ?? true,
        orElse: () => throw const OnlineMusicProviderFailure(
          kind: OnlineMusicFailureKind.sourceResolutionFailed,
          message:
              'No unexpired audio stream is available. Try the song again.',
        ),
      );
      final expiry = _streamExpiry(stream.url);
      if (expiry != null) {
        _streamCache[track.id] = _CachedStream(stream.url, expiry);
        while (_streamCache.length > _maxCachedStreamUrls) {
          _streamCache.remove(_streamCache.keys.first);
        }
      }
      return DirectAudioSource(uri: stream.url, expiresAt: expiry);
    } on OnlineMusicProviderFailure {
      rethrow;
    } on Exception {
      throw const OnlineMusicProviderFailure(
        kind: OnlineMusicFailureKind.sourceResolutionFailed,
        message: 'Could not resolve audio. Try playing another song.',
      );
    }
  }

  DateTime? _streamExpiry(Uri uri) {
    final expiry = int.tryParse(uri.queryParameters['expire'] ?? '');
    return expiry == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(expiry * 1000);
  }

  Future<void> _initializeAudioCache() async {
    try {
      final appDirectory = await getApplicationSupportDirectory();
      final audioDirectory = Directory(
        '${appDirectory.path}/clove_online_audio',
      );
      await audioDirectory.create(recursive: true);
      _audioCacheDirectory = audioDirectory;

      final metadataFile = File('${audioDirectory.path}/cache_metadata.json');
      if (await metadataFile.exists()) {
        final decoded = jsonDecode(await metadataFile.readAsString());
        if (decoded is Map<String, dynamic>) {
          final files = decoded['files'];
          if (files is Map) {
            for (final entry in files.entries) {
              if (entry.key is! String || entry.value is! Map) continue;
              final data = Map<String, dynamic>.from(entry.value as Map);
              final path = data['path'];
              if (path is! String || !await File(path).exists()) continue;
              _audioFileCache[entry.key as String] = path;
              _audioPlayCounts[entry.key as String] =
                  (data['plays'] as num?)?.toInt() ?? 0;
            }
          }
        }
      }
      await _makeRoomForDownload(null, reserveSlot: false);
    } on Exception {
      // Cache metadata cleanup is best-effort; downloads can still proceed.
    }
  }

  Future<bool> _makeRoomForDownload(
    String? keepTrackId, {
    bool reserveSlot = true,
  }) async {
    final currentPaths = <String>{};
    if (PlaybackService.isInitialized) {
      currentPaths.addAll(
        PlaybackService.handler.tracks
            .where((track) => track.sourceUri?.scheme == 'file')
            .map((track) => track.sourceUri!.toFilePath()),
      );
    }

    final targetCount = _maxCachedAudioFiles - (reserveSlot ? 1 : 0);
    while (_audioFileCache.length > targetCount && _audioFileCache.isNotEmpty) {
      final candidates = <MapEntry<String, String>>[];
      for (final entry in _audioFileCache.entries) {
        if (entry.key == keepTrackId || currentPaths.contains(entry.value)) {
          continue;
        }
        if (await _isSavedInCollections(entry.value)) continue;
        candidates.add(entry);
      }
      candidates.sort((a, b) {
        final playOrder = (_audioPlayCounts[a.key] ?? 0).compareTo(
          _audioPlayCounts[b.key] ?? 0,
        );
        if (playOrder != 0) return playOrder;
        return a.key.compareTo(b.key);
      });
      if (candidates.isEmpty) break;
      final leastPlayed = candidates.first;
      await _deleteFile(leastPlayed.value);
      final id = leastPlayed.key.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
      final directory = _audioCacheDirectory;
      if (directory != null) {
        await for (final entity in directory.list()) {
          if (entity is File &&
              entity.uri.pathSegments.last.startsWith('${id}_artwork.')) {
            await _deleteFile(entity.path);
          }
        }
      }
      _audioFileCache.remove(leastPlayed.key);
      _audioPlayCounts.remove(leastPlayed.key);
    }
    await _saveAudioCacheMetadata();
    return _audioFileCache.length < _maxCachedAudioFiles || !reserveSlot;
  }

  Future<bool> _isSavedInCollections(String audioPath) async {
    final database = AppDatabase.instance;
    final liked =
        await (database.select(database.likedTracks)
              ..where((entry) => entry.trackId.equals(audioPath))
              ..limit(1))
            .getSingleOrNull();
    if (liked != null) return true;
    final playlist =
        await (database.select(database.playlistTracks)
              ..where((entry) => entry.trackId.equals(audioPath))
              ..limit(1))
            .getSingleOrNull();
    return playlist != null;
  }

  void _startPlaybackTracking() {
    if (_mediaItemSubscription != null || !PlaybackService.isInitialized) {
      return;
    }
    _mediaItemSubscription = PlaybackService.mediaItemStream.listen((item) {
      _currentQueueEntryId = item?.extras?['queueEntryId'] as String?;
      _currentSourceId = item?.extras?['sourceId'] as String?;
      _currentTrackId = item?.extras?['trackId'] as String?;
      _recordCurrentOnlinePlayIfNeeded();
    });
    _playbackStateSubscription = PlaybackService.playbackStateStream.listen((
      state,
    ) {
      _isPlaybackPlaying = state.playing;
      _recordCurrentOnlinePlayIfNeeded();
    });
  }

  void _recordCurrentOnlinePlayIfNeeded() {
    if (!_isPlaybackPlaying || _currentQueueEntryId == null) return;
    final entryId = _currentQueueEntryId!;
    if (entryId == _lastCountedQueueEntryId) return;
    if (_currentSourceId != 'online_youtube' &&
        _currentSourceId != 'search_recents') {
      return;
    }
    final trackId = _currentTrackId;
    if (trackId == null) return;
    final uri = Uri.tryParse(trackId);
    final id = uri?.queryParameters['v'];
    if (id == null || !_audioFileCache.containsKey(id)) return;
    _lastCountedQueueEntryId = entryId;
    _audioPlayCounts[id] = (_audioPlayCounts[id] ?? 0) + 1;
    unawaited(_saveAudioCacheMetadata());
  }

  Future<void> _saveAudioCacheMetadata() {
    final directory = _audioCacheDirectory;
    if (directory == null) return Future<void>.value();
    final data = <String, Object>{
      'files': {
        for (final entry in _audioFileCache.entries)
          entry.key: {
            'path': entry.value,
            'plays': _audioPlayCounts[entry.key] ?? 0,
          },
      },
    };
    final file = File('${directory.path}/cache_metadata.json');
    final result = _metadataWriteTail.then((_) async {
      await file.writeAsString(jsonEncode(data), flush: true);
    });
    _metadataWriteTail = result.catchError((Object _) {});
    return result;
  }

  Future<void> _deleteFile(String path) async {
    try {
      final file = File(path);
      if (await file.exists()) await file.delete();
    } on Exception {
      // A cache file may already have been removed by the operating system.
    }
  }

  @override
  Future<void> cancelPendingPlayback() async {
    final taskId = _activeTaskId;
    _activeTaskId = null;
    if (taskId == null) return;
    try {
      await Ytdlp.cancel(taskId).timeout(_ytdlpCancelTimeout);
    } on Exception {
      // The task may have completed before cancellation reached the plugin.
    }
  }

  Future<void> _cancelYtdlpTask(String taskId) async {
    try {
      await Ytdlp.cancel(taskId).timeout(_ytdlpCancelTimeout);
    } on Exception {
      // Cancellation is best-effort; timeout still releases the Dart queue.
    }
  }

  @override
  void dispose() {
    _mediaItemSubscription?.cancel();
    _playbackStateSubscription?.cancel();
    _youtube.close();
  }
}
