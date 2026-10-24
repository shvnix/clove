import 'package:clove/models/clove_track.dart';
import 'package:clove/services/local_audio_library.dart';
import 'package:clove/services/audio/player_formatters.dart';
import 'package:audio_service/audio_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:on_audio_query_pluse/on_audio_query.dart';
import 'package:permission_handler/permission_handler.dart';

void main() {
  group('Android audio permission selection', () {
    test('uses storage permission through Android 12L', () {
      expect(androidAudioPermissionForSdk(32), Permission.storage);
    });

    test('uses audio media permission on Android 13 and newer', () {
      expect(androidAudioPermissionForSdk(33), Permission.audio);
      expect(androidAudioPermissionForSdk(37), Permission.audio);
    });
  });

  test(
    'maps songs without discarding missing metadata and prefers content URI',
    () {
      final tracks = mapSongModelsToTracks([
        SongModel({
          '_data': '/storage/emulated/0/Music/song.mp3',
          '_uri': 'content://media/external/audio/media/7',
          'album_id': 42,
          'date_added': 1720000000,
          'title': '  Song  ',
          'artist': null,
          'album': null,
          'duration': null,
        }),
        SongModel({
          '_data': '/storage/emulated/0/Music/unknown.mp3',
          '_uri': null,
          'title': '',
          'artist': '',
          'album': '',
          'duration': 1200,
        }),
        SongModel({
          '_data': '',
          '_uri': null,
          'title': 'No path',
          'artist': null,
          'album': null,
          'duration': 1000,
        }),
      ]);

      expect(tracks, hasLength(2));
      expect(tracks.first.path, 'content://media/external/audio/media/7');
      expect(tracks.first.title, 'Song');
      expect(tracks.first.artist, 'Unknown artist');
      expect(tracks.first.duration, Duration.zero);
      expect(tracks.first.albumId, 42);
      expect(
        tracks.first.dateAdded,
        DateTime.fromMillisecondsSinceEpoch(1720000000000),
      );
      expect(
        tracks.first.toMediaItem().artUri,
        Uri.parse('content://media/external/audio/albumart/42'),
      );
      expect(tracks.first.toMediaItem().extras?['albumId'], 42);
      expect(tracks.last.title, 'Unknown title');
    },
  );

  test('creates supported file and content audio URIs', () {
    const fileTrack = CloveTrack(
      path: '/storage/emulated/0/Music/song.mp3',
      title: 'Song',
      artist: 'Artist',
      album: 'Album',
      duration: Duration.zero,
    );
    const contentTrack = CloveTrack(
      path: 'content://media/external/audio/media/7',
      title: 'Song',
      artist: 'Artist',
      album: 'Album',
      duration: Duration.zero,
    );

    expect(fileTrack.audioUri.scheme, 'file');
    expect(contentTrack.audioUri.scheme, 'content');
  });

  test('formats playback time without hour rollover', () {
    expect(formatPlaybackTime(Duration.zero), '0:00');
    expect(formatPlaybackTime(const Duration(minutes: 2, seconds: 9)), '2:09');
    expect(formatPlaybackTime(const Duration(hours: 1, seconds: 1)), '60:01');
  });

  test('cycles repeat modes and validates queue indexes', () {
    expect(
      nextRepeatMode(AudioServiceRepeatMode.none),
      AudioServiceRepeatMode.all,
    );
    expect(
      nextRepeatMode(AudioServiceRepeatMode.all),
      AudioServiceRepeatMode.one,
    );
    expect(
      nextRepeatMode(AudioServiceRepeatMode.one),
      AudioServiceRepeatMode.none,
    );
    expect(isQueueIndexValid(0, 1), isTrue);
    expect(isQueueIndexValid(1, 1), isFalse);
    expect(isQueueIndexValid(-1, 1), isFalse);
    expect(isQueueIndexValid(0, 0), isFalse);
  });
}
