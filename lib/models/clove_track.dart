import 'package:audio_service/audio_service.dart';

class CloveTrack {
  final String path;
  final String title;
  final String artist;
  final String album;
  final Duration duration;
  final int? albumId;
  final DateTime? dateAdded;
  final Map<String, String> audioHeaders;
  final Uri? artworkUri;
  final String? mediaId;
  final Uri? sourceUri;

  const CloveTrack({
    required this.path,
    required this.title,
    required this.artist,
    required this.album,
    required this.duration,
    this.albumId,
    this.dateAdded,
    this.audioHeaders = const {},
    this.artworkUri,
    this.mediaId,
    this.sourceUri,
  });

  Uri get audioUri {
    if (sourceUri != null) return sourceUri!;
    final uri = Uri.tryParse(path);
    if (uri != null && uri.hasScheme) return uri;
    return Uri.file(path);
  }

  MediaItem toMediaItem() {
    return MediaItem(
      id: mediaId ?? path,
      title: title,
      artist: artist,
      album: album,
      duration: duration,
      artUri: albumArtworkUri ?? artworkUri,
      extras: albumId == null ? null : {'albumId': albumId},
    );
  }

  Uri? get albumArtworkUri => albumId == null
      ? null
      : Uri.parse('content://media/external/audio/albumart/$albumId');
}
