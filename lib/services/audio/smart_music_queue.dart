import '../../models/online_music_track.dart';

class SmartMusicQueueConfig {
  const SmartMusicQueueConfig({
    this.targetUpcoming = 3,
    this.refillThreshold = 1,
    this.refillBatchSize = 2,
    this.sourcePreparationConcurrency = 2,
    this.candidatePoolSize = 30,
    this.maxSameArtist = 1,
    this.recentHistoryWindow = 30,
    this.earlyRefillRemaining,
  });

  final int targetUpcoming;
  final int refillThreshold;
  final int refillBatchSize;
  final int sourcePreparationConcurrency;
  final int candidatePoolSize;
  final int maxSameArtist;
  final int recentHistoryWindow;
  final Duration? earlyRefillRemaining;
}

const defaultSmartMusicQueueConfig = SmartMusicQueueConfig();

/// Produces real provider search queries; this does not assume a radio API.
List<String> recommendationSearchQueries(OnlineMusicTrack track) {
  final artist = (track.artist ?? track.creatorName ?? '').trim();
  final title = track.title.trim();
  final values = <String>[
    if (artist.isNotEmpty) '$artist $title official audio',
    if (artist.isNotEmpty) '$artist $title official music video',
    if (artist.isNotEmpty) '$artist $title topic',
    '$title official audio',
    '$title official music video',
  ];
  final seen = <String>{};
  return values
      .where((value) => value.trim().isNotEmpty)
      .where((value) => seen.add(normalizeRecommendationText(value)))
      .toList(growable: false);
}

bool shouldRefillAutomaticQueue({
  required int upcomingAutomaticCount,
  required int target,
  required int threshold,
  Duration? currentTrackRemaining,
  Duration? earlyRefillRemaining,
}) {
  if (upcomingAutomaticCount >= target) return false;
  if (upcomingAutomaticCount <= threshold) return true;
  return currentTrackRemaining != null &&
      earlyRefillRemaining != null &&
      currentTrackRemaining <= earlyRefillRemaining;
}

List<OnlineMusicTrack> rankRecommendationCandidates({
  required OnlineMusicTrack current,
  required Iterable<OnlineMusicTrack> candidates,
  Iterable<OnlineMusicTrack> queued = const [],
  Iterable<OnlineMusicTrack> automaticQueue = const [],
  Iterable<OnlineMusicTrack> recentHistory = const [],
  Set<String> previouslyPlayedIds = const {},
  Set<String> preferredArtists = const {},
  int limit = 6,
  int maxSameArtist = 1,
  int recentHistoryWindow = 30,
}) {
  final excludedIds = <String>{_trackKey(current)};
  excludedIds.addAll(previouslyPlayedIds.map((id) => id.trim().toLowerCase()));
  final excludedRecordings = <String>{_recordingKey(current)};
  for (final track in [...queued, ...recentHistory.take(recentHistoryWindow)]) {
    excludedIds.add(_trackKey(track));
    excludedRecordings.add(_recordingKey(track));
  }

  final seenIds = <String>{};
  final ranked = <_ScoredTrack>[];
  final artistCounts = <String, int>{};
  for (final track in automaticQueue) {
    final artist = _artistKey(track);
    if (artist.isNotEmpty) {
      artistCounts.update(artist, (count) => count + 1, ifAbsent: () => 1);
    }
  }
  var sourceOrder = 0;
  for (final track in candidates) {
    final order = sourceOrder++;
    final id = _trackKey(track);
    final recording = _recordingKey(track);
    if (id.isEmpty || excludedIds.contains(id) || !seenIds.add(id)) {
      continue;
    }
    if (recording.isNotEmpty && excludedRecordings.contains(recording)) {
      continue;
    }
    final artist = _artistKey(track);
    if (artist.isNotEmpty && artist == _artistKey(current)) continue;
    if (!_isOfficialUpload(current, track) || _isInappropriateVersion(track)) {
      continue;
    }
    ranked.add(
      _ScoredTrack(track, _score(current, track, order, preferredArtists)),
    );
  }
  ranked.sort((left, right) => right.score.compareTo(left.score));

  final selected = <OnlineMusicTrack>[];
  for (final candidate in ranked) {
    final artist = _artistKey(candidate.track);
    if (artist.isNotEmpty && (artistCounts[artist] ?? 0) >= maxSameArtist) {
      continue;
    }
    selected.add(candidate.track);
    if (artist.isNotEmpty) {
      artistCounts.update(artist, (count) => count + 1, ifAbsent: () => 1);
    }
    if (selected.length >= limit) {
      break;
    }
  }
  return List.unmodifiable(selected);
}

String normalizeRecommendationText(String value) =>
    value.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), ' ').trim();

String _trackKey(OnlineMusicTrack track) =>
    '${track.providerId}:${track.id.trim().toLowerCase()}';

String _recordingKey(OnlineMusicTrack track) {
  final title = _recordingTitleKey(track.title);
  final artist = _artistKey(track);
  return title.isEmpty || artist.isEmpty ? '' : '$artist|$title';
}

String _recordingTitleKey(String title) => normalizeRecommendationText(
  title
      .replaceAll(
        RegExp(
          r'\b(official audio|official music video|official video|lyrics?|lyric video|audio|video|hd|4k)\b',
          caseSensitive: false,
        ),
        ' ',
      )
      .replaceAll(RegExp(r'\[(official|audio|video|lyrics?)[^]]*\]'), ' '),
);

String _artistKey(OnlineMusicTrack track) => normalizeRecommendationText(
  (track.artist ?? track.creatorName ?? '')
      .replaceAll(RegExp(r'\s+(- topic|vevo)$', caseSensitive: false), '')
      .replaceAll(RegExp(r'\s+official$', caseSensitive: false), ''),
);

int _score(
  OnlineMusicTrack current,
  OnlineMusicTrack candidate,
  int order,
  Set<String> preferredArtists,
) {
  final currentArtist = _artistKey(current);
  final candidateArtist = _artistKey(candidate);
  var score = 1000 - order;
  if (candidateArtist.isNotEmpty && candidateArtist == currentArtist) {
    score += 30;
  }
  if (preferredArtists.contains(candidateArtist)) score += 12;
  if (current.duration case final currentDuration?) {
    if (candidate.duration case final candidateDuration?) {
      final difference =
          (currentDuration.inSeconds - candidateDuration.inSeconds).abs();
      if (difference <= 30) score += 12;
      if (difference <= 10) score += 8;
    }
  }
  return score;
}

bool _isInappropriateVersion(OnlineMusicTrack candidate) {
  const versionTerms = {
    'remix',
    'live',
    'instrumental',
    'slowed',
    'reversed',
    'reverse',
    'sped up',
    'speed up',
    'reverb',
    'nightcore',
    'cover',
    'karaoke',
    'lyrics',
    'lyric video',
    'reaction',
    'tutorial',
    'fan made',
    'fanmade',
    'unofficial',
    'mashup',
    'tribute',
    'bass boosted',
    '8d audio',
  };
  final candidateMetadata = normalizeRecommendationText(
    '${candidate.title} ${candidate.tags.join(' ')}',
  );
  return versionTerms.any((term) => _hasTerm(candidateMetadata, term));
}

bool _isOfficialUpload(OnlineMusicTrack current, OnlineMusicTrack candidate) {
  final currentUploader = normalizeRecommendationText(
    current.uploaderName ?? current.artist ?? current.creatorName ?? '',
  );
  final candidateUploader = normalizeRecommendationText(
    candidate.uploaderName ?? candidate.artist ?? candidate.creatorName ?? '',
  );
  if (currentUploader.isEmpty || candidateUploader.isEmpty) return false;
  if (currentUploader == candidateUploader) return true;

  final hasOfficialChannelMarker =
      _hasTerm(candidateUploader, 'vevo') ||
      _hasTerm(candidateUploader, 'topic') ||
      _hasTerm(candidateUploader, 'official');
  final normalizedTitle = normalizeRecommendationText(candidate.title);
  final normalizedArtist = _artistKey(candidate);
  final hasOfficialTitleMarker =
      _hasTerm(normalizedTitle, 'official audio') ||
      _hasTerm(normalizedTitle, 'official video') ||
      _hasTerm(normalizedTitle, 'official music video');
  // Topic and VEVO channels are YouTube's normal official artist channels;
  // their titles often omit the words "Official Audio" or "Official Video".
  // Some official artist channels have no marker, so accept an explicit
  // official title only when the artist name is also present in that title.
  return hasOfficialChannelMarker ||
      (hasOfficialTitleMarker &&
          normalizedArtist.isNotEmpty &&
          normalizedTitle.contains(normalizedArtist));
}

bool _hasTerm(String text, String term) =>
    ' $text '.contains(' ${normalizeRecommendationText(term)} ');

class _ScoredTrack {
  const _ScoredTrack(this.track, this.score);

  final OnlineMusicTrack track;
  final int score;
}
