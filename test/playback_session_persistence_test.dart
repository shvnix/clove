import 'dart:convert';
import 'dart:io';

import 'package:clove/data/database.dart';
import 'package:clove/models/clove_track.dart';
import 'package:clove/services/audio/playback_session_codec.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase database;

  setUp(() {
    database = AppDatabase(NativeDatabase.memory());
  });

  tearDown(() async {
    await database.close();
  });

  test('stores a playback session without modifying saved user data', () async {
    await database.saveProfile('Clove user');
    final payload =
        '{"queue":[{"track":{"path":"/music/song.mp3"}}],"index":0,"positionMs":12000}';

    await database.savePlaybackSession(payload);

    expect(await database.loadPlaybackSession(), payload);
    expect((await database.getProfile())?.name, 'Clove user');

    await database.clearPlaybackSession();

    expect(await database.loadPlaybackSession(), isNull);
    expect((await database.getProfile())?.name, 'Clove user');
  });

  test(
    'restores online tracks from their persistent cached audio URI',
    () async {
      final directory = await Directory.systemTemp.createTemp('clove-session-');
      try {
        final audioFile = File('${directory.path}/online-song.m4a');
        await audioFile.writeAsBytes([1, 2, 3]);
        final artworkFile = File('${directory.path}/online-song.jpg');
        await artworkFile.writeAsBytes([4, 5, 6]);
        final track = CloveTrack(
          path: 'https://www.youtube.com/watch?v=online123',
          sourceUri: audioFile.uri,
          title: 'Online song',
          artist: 'Artist',
          album: '',
          duration: const Duration(minutes: 3),
          artworkUri: artworkFile.uri,
          audioHeaders: const {'User-Agent': 'Clove'},
        );

        final encoded = jsonEncode(trackToPlaybackSessionJson(track));
        final restored = trackFromPlaybackSessionJson(
          jsonDecode(encoded) as Map<String, dynamic>,
        );

        expect(restored.path, track.path);
        expect(restored.sourceUri, audioFile.uri);
        expect(restored.audioUri, audioFile.uri);
        expect(restored.artworkUri, artworkFile.uri);
        expect(restored.audioHeaders, track.audioHeaders);
        expect(canRestorePlaybackTrack(restored), isTrue);

        await audioFile.delete();
        expect(canRestorePlaybackTrack(restored), isFalse);
      } finally {
        await directory.delete(recursive: true);
      }
    },
  );

  test(
    'does not persist expiring provider stream URLs as playback sources',
    () {
      final streamUri = Uri.https('rr.googlevideo.com', '/videoplayback', {
        'expire': '9999999999',
      });
      final track = CloveTrack(
        path: 'https://www.youtube.com/watch?v=online123',
        sourceUri: streamUri,
        title: 'Online song',
        artist: 'Artist',
        album: '',
        duration: const Duration(minutes: 3),
      );

      final restored = trackFromPlaybackSessionJson(
        trackToPlaybackSessionJson(track),
      );

      expect(restored.sourceUri, isNull);
      expect(canRestorePlaybackTrack(restored), isFalse);
      expect(canRestorePlaybackTrack(track), isFalse);
    },
  );
}
