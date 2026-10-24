import 'package:clove/services/audio/playback_service.dart';
import 'package:clove/models/clove_track.dart';
import 'package:clove/models/online_music_track.dart';
import 'package:clove/services/online_playback_bridge.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'playback source IDs distinguish local, liked, and individual playlists',
    () {
      final playlistA = PlaybackService.playlistSourceId(12);
      final playlistB = PlaybackService.playlistSourceId(13);

      expect(playlistA, isNot(playlistB));
      expect(playlistA, isNot(PlaybackService.localMusicSourceId));
      expect(playlistA, isNot(PlaybackService.likedSongsSourceId));
    },
  );

  test('a shared track is active only in the matching playback source', () {
    const trackId = '/music/shared-track.mp3';

    expect(
      isTrackActiveInPlaybackSource(
        activeSourceId: PlaybackService.playlistSourceId(12),
        expectedSourceId: PlaybackService.playlistSourceId(12),
        currentTrackId: trackId,
        trackId: trackId,
      ),
      isTrue,
    );
    expect(
      isTrackActiveInPlaybackSource(
        activeSourceId: PlaybackService.playlistSourceId(12),
        expectedSourceId: PlaybackService.playlistSourceId(13),
        currentTrackId: trackId,
        trackId: trackId,
      ),
      isFalse,
    );
    expect(
      isTrackActiveInPlaybackSource(
        activeSourceId: PlaybackService.localMusicSourceId,
        expectedSourceId: PlaybackService.localMusicSourceId,
        currentTrackId: '/music/other-track.mp3',
        trackId: trackId,
      ),
      isFalse,
    );
  });

  test('online audio source stays ephemeral and local paths stay local', () {
    final online = OnlineMusicTrack(
      providerId: 'youtube',
      id: 'video-123',
      title: 'Online song',
      artist: 'Artist',
      sourcePageUri: Uri(
        scheme: 'https',
        host: 'www.youtube.com',
        path: '/watch',
        query: 'v=video-123',
      ),
    );
    final onlineTrack = cloveTrackFromOnlineSource(
      online,
      DirectAudioSource(
        uri: Uri.https('audio.example', '/stream', {'expire': '123456'}),
      ),
    );

    expect(onlineTrack.path, online.sourcePage.toString());
    expect(onlineTrack.audioUri.host, 'audio.example');
    expect(onlineTrack.toMediaItem().id, online.sourcePage.toString());

    const localTrack = CloveTrack(
      path: '/music/local-song.mp3',
      title: 'Local song',
      artist: 'Artist',
      album: '',
      duration: Duration.zero,
    );
    expect(localTrack.sourceUri, isNull);
    expect(localTrack.audioUri, Uri.file('/music/local-song.mp3'));
  });
}
