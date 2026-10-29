import '../models/clove_track.dart';
import '../models/online_music_track.dart';

CloveTrack cloveTrackFromOnlineSource(
  OnlineMusicTrack track,
  DirectAudioSource source,
) => CloveTrack(
  // Keep a stable page identifier in saved metadata; the expiring stream URL
  // or temporary file URI exists only in memory for this playback session.
  path: track.sourcePage.toString(),
  sourceUri: source.uri,
  title: track.title,
  artist: track.artist ?? track.creatorName ?? 'Unknown artist',
  album: track.album ?? '',
  duration: track.duration ?? Duration.zero,
  audioHeaders: source.headers,
  artworkUri: track.artworkUri,
  mediaId: track.sourcePage.toString(),
);
