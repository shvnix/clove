import 'dart:math';

import 'package:audio_service/audio_service.dart';
import 'package:clove/models/clove_track.dart';
import 'package:clove/services/audio/playback_queue.dart';
import 'package:clove/widgets/queue_swipe.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

MediaItem _queueItem({
  required String entryId,
  required String trackId,
  required String sourceId,
}) => MediaItem(
  id: entryId,
  title: trackId,
  extras: {
    'queueEntryId': entryId,
    'trackId': trackId,
    ...queueSourceExtras(sourceId),
  },
);

void main() {
  test('append preserves order and allows intentional duplicates', () {
    const first = CloveTrack(
      path: '/music/first.mp3',
      title: 'First',
      artist: 'Artist',
      album: '',
      duration: Duration.zero,
    );
    const second = CloveTrack(
      path: '/music/second.mp3',
      title: 'Second',
      artist: 'Artist',
      album: '',
      duration: Duration.zero,
    );
    final existing = [first, second];
    final appended = appendQueueTracks(existing, [first, second]);

    expect(appended, [first, second, first, second]);
    expect(existing, [first, second]);
    expect(() => appended.add(first), throwsUnsupportedError);
  });

  test(
    'shuffle order leaves current order intact and appends in playlist order',
    () {
      final order = AppendOnlyShuffleOrder(random: Random(7));
      order.insert(0, 4);
      order.shuffle(initialIndex: 2);
      final oldOrder = List<int>.of(order.indices);

      order.insert(4, 2);

      expect(order.indices.take(4).toList(), oldOrder);
      expect(order.indices.skip(4).toList(), [4, 5]);
    },
  );

  test(
    'shuffle insertion keeps manual additions before the automatic tail',
    () {
      final order = AppendOnlyShuffleOrder(random: Random(7));
      order.insert(0, 4);
      order.shuffle(initialIndex: 2);
      final before = List<int>.of(order.indices);
      final insertAt = 3;
      final insertionPosition = before.indexWhere((index) => index >= insertAt);

      order.insert(insertAt, 1);

      final adjustedBefore = before.map(
        (index) => index >= insertAt ? index + 1 : index,
      );
      expect(order.indices, [
        ...adjustedBefore.take(insertionPosition),
        insertAt,
        ...adjustedBefore.skip(insertionPosition),
      ]);
    },
  );

  test(
    'upcoming indexes follow effective order and exclude the current item',
    () {
      expect(upcomingQueueIndices(2, [3, 2, 0, 1]), [0, 1]);
      expect(upcomingQueueIndices(1, [3, 2, 0, 1]), isEmpty);
      expect(upcomingQueueIndices(null, [0, 1]), isEmpty);
      expect(upcomingQueueIndices(8, [0, 1]), isEmpty);
      expect(isQueueIndexUpcoming(2, 2, [2, 0, 1]), isFalse);
    },
  );

  test('queue entry IDs identify one duplicate occurrence', () {
    final items = [
      const MediaItem(
        id: 'queue-1',
        title: 'Same song',
        extras: {'queueEntryId': 'entry-1'},
      ),
      const MediaItem(
        id: 'queue-2',
        title: 'Same song',
        extras: {'queueEntryId': 'entry-2'},
      ),
      const MediaItem(
        id: 'queue-3',
        title: 'Same song',
        extras: {'queueEntryId': 'entry-3'},
      ),
    ];
    final targetIndex = queueEntryIndex(items, 'entry-2');

    expect(targetIndex, 1);
    expect(isQueueIndexUpcoming(targetIndex, 0, [0, 1, 2]), isTrue);
    expect(isQueueIndexUpcoming(targetIndex, 1, [0, 1, 2]), isFalse);
  });

  test('a valid paused current item is still an active playback session', () {
    const current = MediaItem(
      id: 'queue-2',
      title: 'Current',
      extras: {'trackId': '/music/current.mp3', 'queueEntryId': 'queue-2'},
    );

    expect(
      hasValidCurrentQueueEntry(
        currentMediaItem: current,
        currentQueueIndex: 1,
        queue: [
          const MediaItem(id: 'queue-1', title: 'Previous'),
          current,
          const MediaItem(id: 'queue-3', title: 'Next'),
        ],
      ),
      isTrue,
    );
  });

  test('missing or invalid current item does not indicate a session', () {
    const queued = MediaItem(
      id: 'queue-1',
      title: 'Track',
      extras: {'trackId': '/music/track.mp3', 'queueEntryId': 'queue-1'},
    );

    expect(
      hasValidCurrentQueueEntry(
        currentMediaItem: null,
        currentQueueIndex: 0,
        queue: [queued],
      ),
      isFalse,
    );
    expect(
      hasValidCurrentQueueEntry(
        currentMediaItem: queued,
        currentQueueIndex: null,
        queue: [queued],
      ),
      isFalse,
    );
    expect(
      hasValidCurrentQueueEntry(
        currentMediaItem: queued,
        currentQueueIndex: 1,
        queue: [queued],
      ),
      isFalse,
    );
  });

  test(
    'queue source metadata keeps playlist identity separate from track ID',
    () {
      final playlistOne = queueSourceExtras('playlist:11', position: 2);
      final playlistTwo = queueSourceExtras('playlist:24', position: 0);
      final liked = queueSourceExtras('liked_songs', position: 4);
      final local = queueSourceExtras('local_music', position: 7);
      final recents = queueSourceExtras(searchRecentsSourceId, position: 0);

      expect(playlistOne, {
        'sourceId': 'playlist:11',
        'sourceType': 'playlist',
        'sourcePlaylistId': 11,
        'sourcePosition': 2,
        'expandSourceContext': false,
      });
      expect(playlistTwo['sourcePlaylistId'], 24);
      expect(playlistTwo['sourcePosition'], 0);
      expect(liked['sourceType'], 'liked_songs');
      expect(local['sourceType'], 'local_music');
      expect(recents['sourceType'], 'online_youtube');
      expect(
        automaticRecommendationsEnabledForSource(searchRecentsSourceId),
        isFalse,
      );
      expect(
        automaticRecommendationsEnabledForSource('online_youtube'),
        isTrue,
      );
    },
  );

  test('current source is read from the active queue occurrence metadata', () {
    const playlistEntry = MediaItem(
      id: 'queue-entry-1',
      title: 'Shared song',
      extras: {
        'trackId': '/music/shared.mp3',
        'queueEntryId': 'queue-entry-1',
        'sourceId': 'playlist:24',
        'sourcePlaylistId': 24,
        'sourceType': 'playlist',
      },
    );
    const duplicateFromAnotherPlaylist = MediaItem(
      id: 'queue-entry-2',
      title: 'Shared song',
      extras: {
        'trackId': '/music/shared.mp3',
        'queueEntryId': 'queue-entry-2',
        'sourceId': 'playlist:11',
        'sourcePlaylistId': 11,
        'sourceType': 'playlist',
      },
    );

    expect(queueItemSourceId(playlistEntry), 'playlist:24');
    expect(queueItemSourceId(duplicateFromAnotherPlaylist), 'playlist:11');
    expect(playlistEntry.id, isNot(duplicateFromAnotherPlaylist.id));
  });

  test(
    'queued playlist track plays next without expanding its source playlist',
    () {
      final queue = [
        _queueItem(
          entryId: 'p1-a',
          trackId: '/music/p1-a.mp3',
          sourceId: 'playlist:1',
        ),
        _queueItem(
          entryId: 'queued-x',
          trackId: '/music/x.mp3',
          sourceId: 'playlist:2',
        ),
      ];
      final originalQueue = List<MediaItem>.of(queue);

      expect(activeSourceForQueueIndex(queue, 1), 'playlist:2');
      expect(queue, originalQueue);
      expect(queue.map((item) => item.extras!['trackId']), [
        '/music/p1-a.mp3',
        '/music/x.mp3',
      ]);
    },
  );

  test(
    'multiple queued entries from different playlists retain queue order',
    () {
      final queue = [
        _queueItem(
          entryId: 'p1-a',
          trackId: '/music/p1-a.mp3',
          sourceId: 'playlist:1',
        ),
        _queueItem(
          entryId: 'queued-x',
          trackId: '/music/x.mp3',
          sourceId: 'playlist:2',
        ),
        _queueItem(
          entryId: 'queued-z',
          trackId: '/music/z.mp3',
          sourceId: 'playlist:3',
        ),
      ];

      expect(activeSourceForQueueIndex(queue, 1), 'playlist:2');
      expect(activeSourceForQueueIndex(queue, 2), 'playlist:3');
      expect(queue.map((item) => item.extras!['trackId']), [
        '/music/p1-a.mp3',
        '/music/x.mp3',
        '/music/z.mp3',
      ]);
    },
  );

  test(
    'changing active source from current queue entry does not mutate queue',
    () {
      final queue = [
        _queueItem(
          entryId: 'current',
          trackId: '/music/current.mp3',
          sourceId: 'playlist:1',
        ),
        _queueItem(
          entryId: 'next',
          trackId: '/music/next.mp3',
          sourceId: 'playlist:2',
        ),
      ];
      final before = List<MediaItem>.of(queue);
      final activeSource = activeSourceForQueueIndex(queue, 1);

      expect(activeSource, 'playlist:2');
      expect(queue, before);
    },
  );

  test('duplicate queued tracks retain distinct IDs and source contexts', () {
    final queue = [
      _queueItem(
        entryId: 'duplicate-from-p2',
        trackId: '/music/shared.mp3',
        sourceId: 'playlist:2',
      ),
      _queueItem(
        entryId: 'duplicate-from-p3',
        trackId: '/music/shared.mp3',
        sourceId: 'playlist:3',
      ),
    ];

    expect(queue.map((item) => item.extras!['queueEntryId']), [
      'duplicate-from-p2',
      'duplicate-from-p3',
    ]);
    expect(activeSourceForQueueIndex(queue, 0), 'playlist:2');
    expect(activeSourceForQueueIndex(queue, 1), 'playlist:3');
  });

  test('queue remains authoritative across source context changes', () {
    final queue = [
      _queueItem(
        entryId: 'p1-a',
        trackId: '/music/a.mp3',
        sourceId: 'playlist:1',
      ),
      _queueItem(
        entryId: 'queued-x',
        trackId: '/music/x.mp3',
        sourceId: 'playlist:2',
      ),
      _queueItem(
        entryId: 'queued-z',
        trackId: '/music/z.mp3',
        sourceId: 'playlist:3',
      ),
    ];
    final before = List<MediaItem>.of(queue);
    final visited = <String?>[
      for (var index = 0; index < queue.length; index++)
        activeSourceForQueueIndex(queue, index),
    ];

    expect(visited, ['playlist:1', 'playlist:2', 'playlist:3']);
    expect(queue, before);
    expect(queue.length, 3);
  });

  testWidgets('short swipe does not queue and threshold swipe queues once', (
    tester,
  ) async {
    var queueCalls = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: QueueSwipe(
              successMessage: 'Queued',
              onQueue: () async {
                queueCalls++;
                return true;
              },
              child: const SizedBox(
                width: 280,
                height: 72,
                child: ColoredBox(color: Color(0xFF202020)),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.drag(find.byType(QueueSwipe), const Offset(35, 0));
    await tester.pumpAndSettle();
    expect(queueCalls, 0);

    await tester.drag(find.byType(QueueSwipe), const Offset(100, 0));
    await tester.pumpAndSettle();
    expect(queueCalls, 1);
  });
}
