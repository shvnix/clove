class OnlineMusicTrack {
  const OnlineMusicTrack({
    required this.providerId,
    required this.id,
    required this.title,
    this.artist,
    this.creatorName,
    this.uploaderName,
    this.album,
    this.artworkUri,
    this.sourcePageUri,
    this.duration,
    this.tags = const [],
  });

  final String providerId;
  final String id;
  final String title;
  final String? artist;
  final String? creatorName;
  final String? uploaderName;
  final String? album;
  final Uri? artworkUri;
  final Uri? sourcePageUri;
  final Duration? duration;
  final List<String> tags;

  Uri get sourcePage =>
      sourcePageUri ?? Uri.https('www.youtube.com', '/watch', {'v': id});
}

class OnlineMusicPage {
  const OnlineMusicPage({required this.tracks, this.nextPageToken});

  final List<OnlineMusicTrack> tracks;
  final String? nextPageToken;
}

class DirectAudioSource {
  const DirectAudioSource({
    required this.uri,
    this.headers = const {},
    this.expiresAt,
    this.isAppManagedFile = false,
  });

  final Uri uri;
  final Map<String, String> headers;
  final DateTime? expiresAt;
  final bool isAppManagedFile;
}
