import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';
import 'package:ytdlp_flutter/ytdlp_flutter.dart';

import '../data/database.dart';
import '../models/online_music_track.dart';
import 'audio/playback_service.dart';
import 'online_music_provider.dart';

const _audioOnlyTargetBitrate = 160000;
const _maxCachedStreamUrls = 20;
const _maxCachedAudioFiles = 50;

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
        CancellableOnlineMusicProvider,
        OfflineMusicDownloader {
  YoutubeMusicProvider({YoutubeExplode? youtube})
    : _youtube = youtube ?? YoutubeExplode();

  final YoutubeExplode _youtube;
  final Map<String, _CachedStream> _streamCache = {};
  final Map<String, String> _audioFileCache = {};
  final Map<String, int> _audioPlayCounts = {};
  Future<void>? _ytdlpInitialization;
  Future<void>? _audioCacheInitialization;
  Future<void> _androidDownloadTail = Future<void>.value();
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

  Future<DirectAudioSource> _downloadAndroidAudio(OnlineMusicTrack track) {
    final download = _androidDownloadTail.then(
      (_) => _downloadAndroidAudioNow(track),
    );
    _androidDownloadTail = download
        .then<void>((_) {})
        .catchError((Object _) {});
    return download;
  }

  Future<DirectAudioSource> _downloadAndroidAudioNow(
    OnlineMusicTrack track,
  ) async {
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
    try {
      final path = await Ytdlp.downloadAudio(
        url: track.sourcePage.toString(),
        outputDir: audioDirectory.path,
        taskId: taskId,
      );
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
    }
  }

  Future<DirectAudioSource> _resolveStream(OnlineMusicTrack track) async {
    final cached = _streamCache.remove(track.id);
    if (cached != null && cached.isUsable) {
      _streamCache[track.id] = cached;
      return DirectAudioSource(uri: cached.url, expiresAt: cached.expiresAt);
    }

    try {
      final manifest = await _youtube.videos.streams
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
        message:
            'Could not resolve audio. Check your connection and try again.',
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
    if (_currentSourceId != 'online_youtube') return;
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
      await Ytdlp.cancel(taskId);
    } on Exception {
      // The task may have completed before cancellation reached the plugin.
    }
  }

  @override
  void dispose() {
    _mediaItemSubscription?.cancel();
    _playbackStateSubscription?.cancel();
    _youtube.close();
  }
}
