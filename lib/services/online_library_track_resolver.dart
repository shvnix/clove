import 'dart:io';

import '../models/clove_track.dart';
import '../models/online_music_track.dart';
import 'online_music_provider.dart';

/// Resolves an online player item to the same app-managed audio file used by
/// Search before saving it to Liked Songs or a playlist.
Future<CloveTrack> resolvePlayableLibraryTrack(
  CloveTrack track,
  OnlineMusicProvider provider,
) async {
  final canonicalId = track.mediaId ?? track.path;
  final pageUri = Uri.tryParse(canonicalId);
  final videoId = _youtubeId(pageUri);
  if (videoId == null) return track;

  final onlineTrack = OnlineMusicTrack(
    providerId: 'youtube',
    id: videoId,
    title: track.title,
    artist: track.artist,
    creatorName: track.artist,
    album: track.album,
    artworkUri: track.artworkUri,
    sourcePageUri: pageUri,
    duration: track.duration,
  );

  if (provider is! OfflineMusicDownloader) {
    throw const OnlineMusicProviderFailure(
      kind: OnlineMusicFailureKind.sourceResolutionFailed,
      message: 'Offline saving is not available for this online song.',
    );
  }
  final downloader = provider as OfflineMusicDownloader;

  var offlinePath = await downloader.findOfflineAudioPath(onlineTrack);
  if (offlinePath == null || !await File(offlinePath).exists()) {
    final source = await downloader.downloadForOffline(onlineTrack);
    if (source.uri.scheme != 'file' || source.uri.host.isNotEmpty) {
      throw const OnlineMusicProviderFailure(
        kind: OnlineMusicFailureKind.sourceResolutionFailed,
        message: 'Could not prepare an offline copy of this song.',
      );
    }
    offlinePath = source.uri.toFilePath();
  }

  if (!await File(offlinePath).exists()) {
    throw const OnlineMusicProviderFailure(
      kind: OnlineMusicFailureKind.sourceResolutionFailed,
      message: 'The downloaded song could not be found.',
    );
  }

  return CloveTrack(
    path: offlinePath,
    title: track.title,
    artist: track.artist,
    album: track.album,
    duration: track.duration,
    albumId: track.albumId,
    artworkUri: track.artworkUri,
    mediaId: canonicalId,
  );
}

String? _youtubeId(Uri? uri) {
  if (uri == null) return null;
  final host = uri.host.toLowerCase();
  final youtubeHost =
      host == 'youtube.com' ||
      host.endsWith('.youtube.com') ||
      host == 'youtu.be';
  if (!youtubeHost) return null;

  final queryId = uri.queryParameters['v'];
  if (queryId != null && queryId.isNotEmpty) return queryId;
  if (host == 'youtu.be' && uri.pathSegments.isNotEmpty) {
    return uri.pathSegments.first;
  }
  final segments = uri.pathSegments;
  if (segments.length >= 2 &&
      {'shorts', 'live', 'embed'}.contains(segments.first)) {
    return segments[1];
  }
  return null;
}
