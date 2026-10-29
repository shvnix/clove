import 'dart:io';

import '../../models/clove_track.dart';

Map<String, dynamic> trackToPlaybackSessionJson(CloveTrack track) => {
  'path': track.path,
  'title': track.title,
  'artist': track.artist,
  'album': track.album,
  'durationMs': track.duration.inMilliseconds,
  'albumId': track.albumId,
  'dateAdded': track.dateAdded?.toIso8601String(),
  'audioHeaders': track.audioHeaders,
  'artworkUri': track.artworkUri?.toString(),
  'mediaId': track.mediaId,
  // Extracted provider URLs expire and must be resolved again for playback.
  'sourceUri': _stableSessionSourceUri(track)?.toString(),
};

CloveTrack trackFromPlaybackSessionJson(Map<String, dynamic> data) =>
    CloveTrack(
      path: data['path'] as String,
      title: data['title'] as String? ?? 'Unknown title',
      artist: data['artist'] as String? ?? 'Unknown artist',
      album: data['album'] as String? ?? '',
      duration: Duration(
        milliseconds: (data['durationMs'] as num?)?.toInt() ?? 0,
      ),
      albumId: (data['albumId'] as num?)?.toInt(),
      dateAdded: data['dateAdded'] == null
          ? null
          : DateTime.tryParse(data['dateAdded'] as String),
      audioHeaders: Map<String, String>.from(
        (data['audioHeaders'] as Map?)?.map(
              (key, value) => MapEntry('$key', '$value'),
            ) ??
            const {},
      ),
      artworkUri: _uriFromJson(data['artworkUri']),
      mediaId: data['mediaId'] as String?,
      sourceUri: _uriFromJson(data['sourceUri']),
    );

/// Online tracks keep their stable page URL as [CloveTrack.path] and their
/// cached, playable file URI as [CloveTrack.sourceUri].
bool canRestorePlaybackTrack(CloveTrack track) {
  final sourceUri = track.sourceUri;
  if (sourceUri != null) {
    if (sourceUri.scheme == 'file') {
      return File.fromUri(sourceUri).existsSync();
    }
    if (sourceUri.scheme == 'content') return true;
    if ((sourceUri.scheme == 'http' || sourceUri.scheme == 'https') &&
        sourceUri.host.isNotEmpty) {
      final host = sourceUri.host.toLowerCase();
      return host != 'youtube.com' &&
          !host.endsWith('.youtube.com') &&
          host != 'youtu.be' &&
          host != 'googlevideo.com' &&
          !host.endsWith('.googlevideo.com') &&
          sourceUri.queryParameters['expire'] == null;
    }
    return false;
  }

  final pathUri = Uri.tryParse(track.path);
  if (pathUri == null || !pathUri.hasScheme) {
    return File(track.path).existsSync();
  }
  if (pathUri.scheme == 'file') return File.fromUri(pathUri).existsSync();
  return pathUri.scheme == 'content';
}

Uri? _stableSessionSourceUri(CloveTrack track) {
  final uri = track.sourceUri;
  if (uri == null) return null;
  final host = uri.host.toLowerCase();
  if (host == 'googlevideo.com' ||
      host.endsWith('.googlevideo.com') ||
      uri.queryParameters['expire'] != null) {
    return null;
  }
  return uri;
}

Uri? _uriFromJson(Object? value) {
  if (value is! String || value.trim().isEmpty) return null;
  return Uri.tryParse(value);
}
