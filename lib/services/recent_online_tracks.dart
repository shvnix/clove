import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../models/clove_track.dart';
import '../models/online_music_track.dart';
import 'offline_track_artwork.dart';

/// Persists the most recently played online tracks for the Search screen.
class RecentOnlineTracks {
  static const int limit = 50;
  static const String _fileName = 'recent_online_tracks.json';
  Future<void> _writeTail = Future<void>.value();

  Future<File> _file() async {
    final directory = await getApplicationSupportDirectory();
    return File('${directory.path}/$_fileName');
  }

  Future<List<OnlineMusicTrack>> load() async {
    try {
      final file = await _file();
      if (!await file.exists()) return const [];
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! List) return const [];
      return decoded
          .whereType<Map>()
          .map((entry) => _decode(Map<String, dynamic>.from(entry)))
          .whereType<OnlineMusicTrack>()
          .take(limit)
          .toList(growable: false);
    } on FormatException {
      return const [];
    } on FileSystemException {
      return const [];
    }
  }

  Future<List<OnlineMusicTrack>> record(
    OnlineMusicTrack track, {
    bool moveToTop = true,
  }) async {
    final localized = await _withOfflineArtwork(track);
    return _serializeWrite(() async {
      final tracks = await load();
      final key = _key(localized);
      final existingIndex = tracks.indexWhere((item) => _key(item) == key);
      if (!moveToTop && existingIndex >= 0) {
        if (tracks[existingIndex].artworkUri == localized.artworkUri) {
          return tracks;
        }
        final updated = [...tracks];
        updated[existingIndex] = localized;
        await _write(updated);
        return updated;
      }
      final withoutTrack = tracks.where((item) => _key(item) != key).toList();
      final updated =
          (moveToTop
                  ? [localized, ...withoutTrack]
                  : [...withoutTrack, localized])
              .take(limit)
              .toList(growable: false);
      await _write(updated);
      return updated;
    });
  }

  /// Downloads and stores artwork for an older recent entry when needed.
  Future<OnlineMusicTrack> cacheArtwork(OnlineMusicTrack track) async {
    final localized = await _withOfflineArtwork(track);
    if (localized.artworkUri == track.artworkUri) return track;
    await _serializeWrite(() async {
      final tracks = await load();
      final index = tracks.indexWhere((item) => _key(item) == _key(track));
      if (index < 0) return;
      final updated = [...tracks];
      updated[index] = localized;
      await _write(updated);
    });
    return localized;
  }

  Future<List<OnlineMusicTrack>> remove(OnlineMusicTrack track) =>
      _serializeWrite(() async {
        final tracks = await load();
        final updated = tracks
            .where((item) => _key(item) != _key(track))
            .toList(growable: false);
        await _write(updated);
        return updated;
      });

  Future<OnlineMusicTrack> _withOfflineArtwork(OnlineMusicTrack track) async {
    final imageUri = track.artworkUri;
    if (imageUri == null || imageUri.scheme == 'file') return track;
    final sourcePage = track.sourcePage.toString();
    final localTrack = await withOfflineTrackArtwork(
      CloveTrack(
        path: sourcePage,
        mediaId: sourcePage,
        title: track.title,
        artist: track.artist ?? track.creatorName ?? 'Unknown artist',
        album: track.album ?? '',
        duration: track.duration ?? Duration.zero,
        artworkUri: imageUri,
      ),
    );
    if (localTrack.artworkUri == imageUri) return track;
    return _copyWithArtwork(track, localTrack.artworkUri);
  }

  Future<T> _serializeWrite<T>(Future<T> Function() operation) {
    final result = _writeTail.then((_) => operation());
    _writeTail = result.then<void>((_) {}).catchError((Object _) {});
    return result;
  }

  Future<void> _write(List<OnlineMusicTrack> tracks) async {
    final file = await _file();
    await file.writeAsString(
      jsonEncode(tracks.map(_encode).toList(growable: false)),
      flush: true,
    );
  }

  String _key(OnlineMusicTrack track) => '${track.providerId}:${track.id}';

  Map<String, Object?> _encode(OnlineMusicTrack track) => {
    'providerId': track.providerId,
    'id': track.id,
    'title': track.title,
    'artist': track.artist,
    'creatorName': track.creatorName,
    'uploaderName': track.uploaderName,
    'album': track.album,
    'artworkUri': track.artworkUri?.toString(),
    'sourcePageUri': track.sourcePageUri?.toString(),
    'durationMs': track.duration?.inMilliseconds,
    'tags': track.tags,
  };

  OnlineMusicTrack? _decode(Map<String, dynamic> data) {
    final providerId = data['providerId'];
    final id = data['id'];
    final title = data['title'];
    if (providerId is! String || id is! String || title is! String) {
      return null;
    }
    final duration = data['durationMs'];
    final tags = data['tags'];
    return OnlineMusicTrack(
      providerId: providerId,
      id: id,
      title: title,
      artist: data['artist'] as String?,
      creatorName: data['creatorName'] as String?,
      uploaderName: data['uploaderName'] as String?,
      album: data['album'] as String?,
      artworkUri: _parseUri(data['artworkUri']),
      sourcePageUri: _parseUri(data['sourcePageUri']),
      duration: duration is num
          ? Duration(milliseconds: duration.toInt())
          : null,
      tags: tags is List ? tags.whereType<String>().toList() : const [],
    );
  }

  Uri? _parseUri(Object? value) => value is String ? Uri.tryParse(value) : null;

  OnlineMusicTrack _copyWithArtwork(OnlineMusicTrack track, Uri? artworkUri) =>
      OnlineMusicTrack(
        providerId: track.providerId,
        id: track.id,
        title: track.title,
        artist: track.artist,
        creatorName: track.creatorName,
        uploaderName: track.uploaderName,
        album: track.album,
        artworkUri: artworkUri,
        sourcePageUri: track.sourcePageUri,
        duration: track.duration,
        tags: track.tags,
      );
}
