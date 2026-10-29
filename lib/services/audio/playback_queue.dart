import 'package:just_audio/just_audio.dart';

import '../../models/clove_track.dart';

import 'package:audio_service/audio_service.dart';

const String searchRecentsSourceId = 'search_recents';

/// Appends entries without mutating the current queue or deduplicating tracks.
List<CloveTrack> appendQueueTracks(
  List<CloveTrack> current,
  List<CloveTrack> additions,
) => List<CloveTrack>.unmodifiable([...current, ...additions]);

/// Queue indexes in the real next-to-play order, excluding the current item.
List<int> upcomingQueueIndices(
  int? currentQueueIndex,
  List<int> effectiveQueueIndices,
) {
  if (currentQueueIndex == null || effectiveQueueIndices.isEmpty) {
    return const [];
  }
  final currentPosition = effectiveQueueIndices.indexOf(currentQueueIndex);
  if (currentPosition < 0) return const [];
  return List<int>.unmodifiable(
    effectiveQueueIndices.skip(currentPosition + 1),
  );
}

bool isQueueIndexUpcoming(
  int queueIndex,
  int? currentQueueIndex,
  List<int> effectiveQueueIndices,
) => upcomingQueueIndices(
  currentQueueIndex,
  effectiveQueueIndices,
).contains(queueIndex);

int queueEntryIndex(List<MediaItem> items, String queueEntryId) =>
    items.indexWhere((item) => item.extras?['queueEntryId'] == queueEntryId);

Map<String, Object> queueSourceExtras(
  String? sourceId, {
  int? position,
  bool expandSourceContext = false,
}) {
  final playlistId = sourceId != null && sourceId.startsWith('playlist:')
      ? int.tryParse(sourceId.substring('playlist:'.length))
      : null;
  final sourceType = playlistId != null
      ? 'playlist'
      : sourceId == 'liked_songs'
      ? 'liked_songs'
      : sourceId == 'local_music'
      ? 'local_music'
      : sourceId == 'online_youtube'
      ? 'online_youtube'
      : sourceId == searchRecentsSourceId
      ? 'online_youtube'
      : 'unknown';
  return {
    if (sourceId case final String id) 'sourceId': id,
    'sourceType': sourceType,
    if (playlistId case final int id) 'sourcePlaylistId': id,
    if (position case final int value) 'sourcePosition': value,
    'expandSourceContext': expandSourceContext,
  };
}

String? queueItemSourceId(MediaItem? item) {
  final sourceId = item?.extras?['sourceId'];
  return sourceId is String ? sourceId : null;
}

bool automaticRecommendationsEnabledForSource(String? sourceId) =>
    sourceId == 'online_youtube';

/// Returns the source context attached to the queue occurrence that actually
/// became current. Resolving this value never changes the playback queue.
String? activeSourceForQueueIndex(List<MediaItem> queue, int? currentIndex) {
  if (currentIndex == null ||
      currentIndex < 0 ||
      currentIndex >= queue.length) {
    return null;
  }
  return queueItemSourceId(queue[currentIndex]);
}

int? queueItemSourcePosition(MediaItem? item) {
  final position = item?.extras?['sourcePosition'];
  return position is int ? position : null;
}

/// A paused track still counts as an active session. The current item must
/// match the queue entry at the player's live index and carry stable IDs.
bool hasValidCurrentQueueEntry({
  required MediaItem? currentMediaItem,
  required int? currentQueueIndex,
  required List<MediaItem> queue,
}) {
  if (currentMediaItem == null ||
      currentQueueIndex == null ||
      currentQueueIndex < 0 ||
      currentQueueIndex >= queue.length) {
    return false;
  }

  final currentQueueItem = queue[currentQueueIndex];
  final queueEntryId = currentQueueItem.extras?['queueEntryId'];
  final trackId = currentQueueItem.extras?['trackId'];
  return queueEntryId is String &&
      queueEntryId.isNotEmpty &&
      trackId is String &&
      trackId.isNotEmpty &&
      currentMediaItem.id == currentQueueItem.id &&
      currentMediaItem.extras?['queueEntryId'] == queueEntryId;
}

/// Keeps the existing effective shuffle order intact and appends additions in
/// their original order, rather than just_audio's default random insertion.
class AppendOnlyShuffleOrder extends DefaultShuffleOrder {
  AppendOnlyShuffleOrder({super.random});

  @override
  void insert(int index, int count) {
    final insertionPosition = indices.indexWhere(
      (oldIndex) => oldIndex >= index,
    );
    for (var i = 0; i < indices.length; i++) {
      if (indices[i] >= index) indices[i] += count;
    }
    indices.insertAll(
      insertionPosition < 0 ? indices.length : insertionPosition,
      List<int>.generate(count, (offset) => index + offset),
    );
  }
}
