import '../models/online_music_track.dart';

abstract interface class OnlineMusicProvider {
  String get id;

  Future<OnlineMusicPage> search(String query, {String? pageToken});

  Future<DirectAudioSource> resolvePlaybackSource(OnlineMusicTrack track);

  Future<DirectAudioSource> refreshPlaybackSource(OnlineMusicTrack track);

  void dispose();
}

abstract interface class CancellableOnlineMusicProvider {
  Future<void> cancelPendingPlayback();
}

/// Optional discovery API for providers that can find music related to a
/// currently playing track using their supported search capabilities.
abstract interface class OnlineMusicDiscoveryProvider
    implements OnlineMusicProvider {
  Future<List<OnlineMusicTrack>> discoverRelated(OnlineMusicTrack track);
}

/// Optional request-scoped hooks for recommendation work. Cancelling these
/// requests must not cancel the source currently being played by the provider.
abstract interface class CancellableOnlineRecommendationProvider {
  Future<List<OnlineMusicTrack>> discoverRecommendations(
    OnlineMusicTrack track, {
    required int requestId,
  });

  Future<DirectAudioSource> resolveRecommendationSource(
    OnlineMusicTrack track, {
    required int requestId,
  });

  Future<void> cancelRecommendationRequest(int requestId);
}

/// Optional fast resolver used to prepare queue entries without downloading a
/// complete offline copy. Temporary stream URLs must be treated as expiring.
abstract interface class OnlineMusicStreamResolver {
  Future<DirectAudioSource> resolveStreamingSource(OnlineMusicTrack track);
}

abstract interface class OfflineMusicDownloader {
  Future<DirectAudioSource> downloadForOffline(OnlineMusicTrack track);

  Future<String?> findOfflineAudioPath(OnlineMusicTrack track);
}

class UnavailableOnlineMusicProvider implements OnlineMusicProvider {
  const UnavailableOnlineMusicProvider({
    this.id = 'unconfigured',
    this.message = 'No online music provider is configured.',
  });

  @override
  final String id;
  final String message;

  @override
  Future<OnlineMusicPage> search(String query, {String? pageToken}) =>
      Future.error(OnlineMusicProviderUnavailable(message));

  @override
  Future<DirectAudioSource> resolvePlaybackSource(OnlineMusicTrack track) =>
      Future.error(OnlineMusicProviderUnavailable(message));

  @override
  Future<DirectAudioSource> refreshPlaybackSource(OnlineMusicTrack track) =>
      Future.error(OnlineMusicProviderUnavailable(message));

  @override
  void dispose() {}
}

enum OnlineMusicFailureKind {
  runtimeUnavailable,
  searchFailed,
  sourceResolutionFailed,
  sourceNotPlayable,
}

class OnlineMusicProviderFailure implements Exception {
  const OnlineMusicProviderFailure({
    required this.message,
    this.kind = OnlineMusicFailureKind.searchFailed,
  });

  final String message;
  final OnlineMusicFailureKind kind;

  @override
  String toString() => message;
}

class OnlineMusicProviderUnavailable extends OnlineMusicProviderFailure {
  const OnlineMusicProviderUnavailable([
    String message = 'No online music provider is configured.',
  ]) : super(kind: OnlineMusicFailureKind.runtimeUnavailable, message: message);
}

bool isAllowedDirectAudioUri(Uri uri) {
  if (uri.scheme != 'https' && uri.scheme != 'http') return false;
  final host = uri.host.toLowerCase();
  return host != 'youtube.com' &&
      !host.endsWith('.youtube.com') &&
      host != 'youtu.be' &&
      host != 'googlevideo.com' &&
      !host.endsWith('.googlevideo.com');
}

bool isAllowedOnlineAudioSource(DirectAudioSource source) =>
    isAllowedDirectAudioUri(source.uri) ||
    (source.isAppManagedFile &&
        source.uri.scheme == 'file' &&
        source.uri.host.isEmpty &&
        source.uri.path.isNotEmpty);

List<OnlineMusicTrack> rankMusicResults(
  String query,
  Iterable<OnlineMusicTrack> tracks,
) {
  final normalizedQuery = _normalize(query);
  final terms = normalizedQuery.split(' ').where((term) => term.isNotEmpty);
  final ranked = tracks.where(_looksLikeMusic).toList()
    ..sort((left, right) {
      final leftScore = _matchScore(left, normalizedQuery, terms);
      final rightScore = _matchScore(right, normalizedQuery, terms);
      return rightScore.compareTo(leftScore);
    });
  return List.unmodifiable(ranked);
}

const _nonMusicTerms = {
  'tutorial',
  'gameplay',
  'review',
  'reaction',
  'interview',
  'walkthrough',
  'commentary',
  'trailer',
  'podcast',
};

bool _looksLikeMusic(OnlineMusicTrack track) {
  final metadata = _normalize(
    '${track.title} ${track.artist ?? ''} ${track.creatorName ?? ''} '
    '${track.album ?? ''} ${track.tags.join(' ')}',
  );
  return !_nonMusicTerms.any((term) => _containsTerm(metadata, term));
}

int _matchScore(OnlineMusicTrack track, String query, Iterable<String> terms) {
  final title = _normalize(track.title);
  final artist = _normalize(track.artist ?? '');
  final combined = '$title $artist'.trim();
  var score = 0;
  if (title == query) score += 100;
  if (combined == query) score += 80;
  if (title.contains(query)) score += 40;
  if (artist.contains(query)) score += 30;
  for (final term in terms) {
    if (_containsTerm(title, term)) score += 4;
    if (_containsTerm(artist, term)) score += 6;
  }
  return score;
}

String _normalize(String value) =>
    value.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), ' ').trim();

bool _containsTerm(String value, String term) => ' $value '.contains(' $term ');
