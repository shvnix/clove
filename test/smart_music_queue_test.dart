import 'package:clove/models/online_music_track.dart';
import 'package:clove/services/audio/smart_music_queue.dart';
import 'package:flutter_test/flutter_test.dart';

OnlineMusicTrack _track(
  String id,
  String title, {
  String? artist,
  int? seconds,
}) => OnlineMusicTrack(
  providerId: 'youtube',
  id: id,
  title: title,
  artist: artist,
  duration: seconds == null ? null : Duration(seconds: seconds),
);

void main() {
  test('uses three initial recommendations and refills in pairs', () {
    expect(defaultSmartMusicQueueConfig.targetUpcoming, 3);
    expect(defaultSmartMusicQueueConfig.refillThreshold, 1);
    expect(defaultSmartMusicQueueConfig.refillBatchSize, 2);
    expect(defaultSmartMusicQueueConfig.maxSameArtist, 1);
    expect(defaultSmartMusicQueueConfig.earlyRefillRemaining, isNull);
  });

  test(
    'discovery uses distinct real search queries without inventing APIs',
    () {
      expect(
        recommendationSearchQueries(
          _track('seed', 'Blue Morning', artist: 'Mira'),
        ),
        [
          'Mira Blue Morning official audio',
          'Mira Blue Morning official music video',
          'Mira Blue Morning topic',
          'Blue Morning official audio',
          'Blue Morning official music video',
        ],
      );
      expect(recommendationSearchQueries(_track('seed', 'Blue Morning')), [
        'Blue Morning official audio',
        'Blue Morning official music video',
      ]);
    },
  );

  test('refill threshold excludes current track and supports early refill', () {
    expect(
      shouldRefillAutomaticQueue(
        upcomingAutomaticCount: 10,
        target: 10,
        threshold: 3,
      ),
      isFalse,
    );
    expect(
      shouldRefillAutomaticQueue(
        upcomingAutomaticCount: 3,
        target: 10,
        threshold: 3,
      ),
      isTrue,
    );
    expect(
      shouldRefillAutomaticQueue(
        upcomingAutomaticCount: 6,
        target: 10,
        threshold: 3,
        currentTrackRemaining: const Duration(seconds: 40),
        earlyRefillRemaining: const Duration(seconds: 90),
      ),
      isTrue,
    );
  });

  test(
    'excludes current, duplicate uploads, queued, and recent recordings',
    () {
      final current = _track('current', 'Blue Morning', artist: 'Mira');
      final result = rankRecommendationCandidates(
        current: current,
        candidates: [
          current,
          _track('duplicate-video', 'Blue Morning', artist: 'Mira'),
          _track(
            'official-upload',
            'Blue Morning (Official Music Video)',
            artist: 'Mira - Topic',
          ),
          _track(
            'already-queued',
            'Amber Sky (Official Audio)',
            artist: 'Noah - VEVO',
          ),
          _track(
            'recent',
            'Silver Road (Official Audio)',
            artist: 'Ari - VEVO',
          ),
          _track('new', 'Green Light (Official Audio)', artist: 'Sol - VEVO'),
        ],
        queued: [
          _track(
            'already-queued',
            'Amber Sky (Official Audio)',
            artist: 'Noah - VEVO',
          ),
        ],
        recentHistory: [
          _track(
            'old-id',
            'Silver Road (Official Audio)',
            artist: 'Ari - VEVO',
          ),
        ],
      );

      expect(result.map((track) => track.id), ['new']);
    },
  );

  test('ranks related results and limits automatic artist repetition', () {
    final current = _track('seed', 'Anchor', artist: 'Anchor Artist');
    final candidates = [
      _track(
        'first',
        'Song One (Official Audio)',
        artist: 'Nova - VEVO',
        seconds: 180,
      ),
      _track(
        'second',
        'Song Two (Official Audio)',
        artist: 'Nova - VEVO',
        seconds: 181,
      ),
      _track(
        'third',
        'Song Three (Official Audio)',
        artist: 'Nova - VEVO',
        seconds: 182,
      ),
      _track(
        'fourth',
        'Song Four (Official Audio)',
        artist: 'Other - VEVO',
        seconds: 181,
      ),
      _track(
        'fifth',
        'Song Five (Official Audio)',
        artist: 'Elsewhere - VEVO',
        seconds: 400,
      ),
    ];

    final result = rankRecommendationCandidates(
      current: current,
      candidates: candidates,
      limit: 4,
      maxSameArtist: 2,
    );

    expect(result.map((track) => track.id), [
      'first',
      'second',
      'fourth',
      'fifth',
    ]);
  });

  test('artist limit includes already queued automatic recommendations', () {
    final result = rankRecommendationCandidates(
      current: _track('seed', 'Anchor', artist: 'Anchor Artist'),
      automaticQueue: [_track('queued', 'Queued Song', artist: 'Nova - VEVO')],
      candidates: [
        _track('one', 'Song One (Official Audio)', artist: 'Nova - VEVO'),
        _track('two', 'Song Two (Official Audio)', artist: 'Nova - VEVO'),
        _track('other', 'Song Three (Official Audio)', artist: 'Sol - VEVO'),
      ],
      limit: 3,
      maxSameArtist: 2,
    );

    expect(result.map((track) => track.id), ['one', 'other']);
  });

  test('recommendations skip the current artist and avoid artist repeats', () {
    final result = rankRecommendationCandidates(
      current: _track('seed', 'Seed Song', artist: 'Current Artist'),
      candidates: [
        _track('same', 'Another Song', artist: 'Current Artist'),
        _track('first-b', 'B Song (Official Audio)', artist: 'Artist B - VEVO'),
        _track(
          'second-b',
          'B Song Two (Official Audio)',
          artist: 'Artist B - VEVO',
        ),
        _track('first-c', 'C Song (Official Audio)', artist: 'Artist C - VEVO'),
      ],
      limit: 3,
    );

    expect(result.map((track) => track.id), ['first-b', 'first-c']);
  });

  test('filters unsuitable versions only when current context is original', () {
    final original = _track('original', 'Quiet River', artist: 'Mira');
    final originalRecommendations = rankRecommendationCandidates(
      current: original,
      candidates: [
        _track('live', 'Quiet River Live', artist: 'Mira'),
        _track('lyrics', 'Quiet River Lyrics', artist: 'Mira'),
        _track('studio', 'Another Song (Official Audio)', artist: 'Sol - VEVO'),
      ],
    );
    expect(originalRecommendations.map((track) => track.id), ['studio']);

    final live = _track('live-seed', 'Quiet River Live', artist: 'Mira');
    final liveRecommendations = rankRecommendationCandidates(
      current: live,
      candidates: [_track('live-alt', 'Other River Live', artist: 'Mira')],
    );
    expect(liveRecommendations, isEmpty);
  });

  test('unknown uploader metadata is excluded from official-only queue', () {
    final result = rankRecommendationCandidates(
      current: _track('seed', 'Anchor'),
      candidates: [_track('unknown-meta', 'Another Song')],
    );
    expect(result, isEmpty);
  });

  test('rejects third-party uploads and remix variants', () {
    final current = _track('seed', 'Anchor Song', artist: 'Anchor Artist');
    final result = rankRecommendationCandidates(
      current: current,
      candidates: [
        _track(
          'fan-upload',
          'Another Song (Official Audio)',
          artist: 'Fan Channel',
        ),
        _track('remix', 'Another Song Remix', artist: 'Anchor Artist'),
        _track(
          'slowed',
          'Another Song Slowed + Reverb',
          artist: 'Anchor Artist',
        ),
        _track(
          'official',
          'Another Song (Official Audio)',
          artist: 'Nova - VEVO',
        ),
      ],
    );

    expect(result.map((track) => track.id), ['official']);
  });

  test('accepts official channel uploads when channel names differ', () {
    final result = rankRecommendationCandidates(
      current: _track('seed', 'Anchor Song', artist: 'Anchor Artist'),
      candidates: [
        _track(
          'official-video',
          'New Song (Official Music Video)',
          artist: 'New Artist - VEVO',
        ),
        _track(
          'topic-upload',
          'Another Song',
          artist: 'Another Artist - Topic',
        ),
        _track(
          'artist-official-title',
          'Artist C - New Song (Official Audio)',
          artist: 'Artist C',
        ),
        _track(
          'third-party',
          'Other Song (Official Audio)',
          artist: 'Music Fan Channel',
        ),
      ],
    );

    expect(result.map((track) => track.id), [
      'official-video',
      'topic-upload',
      'artist-official-title',
    ]);
  });

  test('excludes every previously played provider ID', () {
    final result = rankRecommendationCandidates(
      current: _track('seed', 'Anchor Song', artist: 'Anchor Artist'),
      candidates: [
        _track('played', 'Played Song (Official Audio)', artist: 'Nova - VEVO'),
        _track('new', 'New Song (Official Audio)', artist: 'Sol - VEVO'),
      ],
      previouslyPlayedIds: {'youtube:played'},
    );

    expect(result.map((track) => track.id), ['new']);
  });
}
