import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../models/clove_track.dart';

/// Saves remote track artwork into the app's persistent artwork cache
/// and returns a track that points at the local copy. Artwork download failure
/// does not prevent a song from being saved to a collection.
Future<CloveTrack> withOfflineTrackArtwork(CloveTrack track) async {
  final artwork = track.artworkUri;
  if (artwork == null) return track;

  if (artwork.scheme == 'file') {
    try {
      if (await File.fromUri(artwork).exists()) return track;
    } on FileSystemException {
      return track;
    }
  }

  if (!{'http', 'https'}.contains(artwork.scheme) || artwork.host.isEmpty) {
    return track;
  }

  HttpClient? client;
  try {
    final supportDirectory = await getApplicationSupportDirectory();
    final directory = Directory('${supportDirectory.path}/clove_track_artwork');
    await directory.create(recursive: true);

    final identity = track.mediaId ?? track.path;
    final identityUri = Uri.tryParse(identity);
    final key = (_youtubeVideoId(identityUri) ?? identity).replaceAll(
      RegExp(r'[^A-Za-z0-9_-]'),
      '_',
    );
    final safeKey = key.length > 120 ? key.substring(0, 120) : key;
    final extension = switch (artwork.path.toLowerCase().split('.').last) {
      'png' => 'png',
      'webp' => 'webp',
      'jpeg' => 'jpeg',
      _ => 'jpg',
    };
    final imageFile = File('${directory.path}/${safeKey}_artwork.$extension');
    if (await imageFile.exists() && await imageFile.length() > 0) {
      return _withArtwork(track, imageFile.uri);
    }

    // Migrate images saved beside downloaded audio by earlier app versions.
    final oldImageFile = File(
      '${supportDirectory.path}/clove_online_audio/${safeKey}_artwork.$extension',
    );
    if (await oldImageFile.exists() && await oldImageFile.length() > 0) {
      await oldImageFile.copy(imageFile.path);
      return _withArtwork(track, imageFile.uri);
    }

    client = HttpClient()..connectionTimeout = const Duration(seconds: 15);
    final request = await client
        .getUrl(artwork)
        .timeout(const Duration(seconds: 20));
    final response = await request.close().timeout(const Duration(seconds: 20));
    if (response.statusCode < 200 || response.statusCode >= 300) return track;

    final bytes = await response
        .fold<List<int>>(<int>[], (buffer, chunk) {
          buffer.addAll(chunk);
          if (buffer.length > 12 * 1024 * 1024) {
            throw const HttpException('Artwork image is too large.');
          }
          return buffer;
        })
        .timeout(const Duration(seconds: 30));
    if (bytes.isEmpty) return track;
    await imageFile.writeAsBytes(bytes, flush: true);
    return _withArtwork(track, imageFile.uri);
  } on Exception {
    return track;
  } finally {
    client?.close(force: true);
  }
}

String? _youtubeVideoId(Uri? uri) {
  if (uri == null) return null;
  final host = uri.host.toLowerCase();
  if (host == 'youtu.be' && uri.pathSegments.isNotEmpty) {
    return uri.pathSegments.first;
  }
  if (host == 'youtube.com' || host.endsWith('.youtube.com')) {
    final videoId = uri.queryParameters['v'];
    if (videoId != null && videoId.isNotEmpty) return videoId;
  }
  return null;
}

CloveTrack _withArtwork(CloveTrack track, Uri artworkUri) => CloveTrack(
  path: track.path,
  title: track.title,
  artist: track.artist,
  album: track.album,
  duration: track.duration,
  albumId: track.albumId,
  dateAdded: track.dateAdded,
  audioHeaders: track.audioHeaders,
  artworkUri: artworkUri,
  mediaId: track.mediaId,
  sourceUri: track.sourceUri,
);
