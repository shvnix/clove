import 'dart:io';

import 'package:clove/data/database.dart';
import 'package:clove/models/clove_track.dart';
import 'package:clove/services/playlist_repository.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase database;
  late PlaylistRepository repository;

  setUp(() {
    database = AppDatabase(NativeDatabase.memory());
    repository = PlaylistRepository(database);
  });

  tearDown(() async => database.close());

  test('playlist memberships are unique and restore tracks in order', () async {
    final id = await repository.createPlaylist('Night drive');
    const first = CloveTrack(
      path: 'content://media/audio/101',
      title: 'First song',
      artist: 'Artist',
      album: 'Album',
      duration: Duration(minutes: 3),
      albumId: 9,
    );
    const second = CloveTrack(
      path: 'content://media/audio/102',
      title: 'Second song',
      artist: 'Artist',
      album: 'Album',
      duration: Duration(minutes: 4),
    );

    await repository.addToPlaylist(id, first);
    await repository.addToPlaylist(id, first);
    await repository.addToPlaylist(id, second);

    final tracks = await repository.watchPlaylistTracks(id).first;
    expect(tracks.map((track) => track.path), [first.path, second.path]);
    expect(tracks.first.duration, first.duration);
    expect(tracks.first.albumId, first.albumId);
    expect(await repository.watchPlaylists().first, hasLength(1));
    expect(
      (await repository.watchCollections(first.path).first).contains(id),
      isTrue,
    );
  });

  test('online saves match the currently playing track identity', () async {
    const onlineId = 'https://www.youtube.com/watch?v=online-song';
    const downloaded = CloveTrack(
      path: '/cache/online-song.m4a',
      mediaId: onlineId,
      title: 'Online song',
      artist: 'Artist',
      album: '',
      duration: Duration(minutes: 3),
    );
    const currentlyPlaying = CloveTrack(
      path: onlineId,
      mediaId: onlineId,
      title: 'Online song',
      artist: 'Artist',
      album: '',
      duration: Duration(minutes: 3),
    );
    final playlistId = await repository.createPlaylist('Online');

    // Simulate rows created by the old mini-player flow, which stored the
    // online page URL as the playback path. Saving again with Search's
    // downloaded copy must repair the stored path without duplicating rows.
    await repository.setLiked(currentlyPlaying, true);
    await repository.addToPlaylist(playlistId, currentlyPlaying);
    await repository.setLiked(downloaded, true);
    await repository.addToPlaylist(playlistId, downloaded);

    final saved = await repository
        .watchCollections(
          currentlyPlaying.path,
          canonicalId: currentlyPlaying.mediaId,
        )
        .first;
    expect(saved.isLiked, isTrue);
    expect(saved.contains(playlistId), isTrue);
    final repairedPlaylistTrack =
        (await repository.watchPlaylistTracks(playlistId).first).single;
    expect(repairedPlaylistTrack.path, downloaded.path);
    expect(repairedPlaylistTrack.mediaId, onlineId);

    await repository.togglePlaylistMembership(playlistId, currentlyPlaying);
    expect(
      (await repository
              .watchCollections(
                currentlyPlaying.path,
                canonicalId: currentlyPlaying.mediaId,
              )
              .first)
          .contains(playlistId),
      isFalse,
    );
    await repository.togglePlaylistMembership(playlistId, downloaded);
    final restoredPlaylistTrack =
        (await repository.watchPlaylistTracks(playlistId).first).single;
    expect(restoredPlaylistTrack.path, downloaded.path);
    expect(restoredPlaylistTrack.mediaId, onlineId);

    final likedTrack = (await repository.watchLikedTracks().first).single;
    expect(likedTrack.path, downloaded.path);
    expect(likedTrack.mediaId, onlineId);
  });

  test(
    'Liked Songs persists membership and keeps deterministic order',
    () async {
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

      await repository.setLiked(first, true);
      await repository.setLiked(first, true);
      await repository.setLiked(second, true);

      final liked = await repository.watchLikedTracks().first;
      expect(liked.map((track) => track.path), [first.path, second.path]);
      expect(await repository.watchLikedCount().first, 2);
      expect(
        (await repository.watchCollections(first.path).first).isLiked,
        isTrue,
      );

      await repository.setLiked(first, false);
      expect(
        (await repository.watchLikedTracks().first).map((track) => track.path),
        [second.path],
      );
    },
  );

  test('deleting a playlist deletes its persisted memberships', () async {
    final id = await repository.createPlaylist('Temporary');
    const track = CloveTrack(
      path: 'file:///music/song.mp3',
      title: 'Song',
      artist: 'Artist',
      album: 'Album',
      duration: Duration(seconds: 10),
    );
    await repository.addToPlaylist(id, track);
    await repository.deletePlaylist(id);

    expect(await repository.watchPlaylists().first, isEmpty);
    expect(await repository.watchPlaylistTracks(id).first, isEmpty);
  });

  test('targeted playlist lookup reflects edits and deletion', () async {
    final id = await repository.createPlaylist('Before');

    final initial = await repository.watchPlaylist(id).first;
    expect(initial?.name, 'Before');

    await repository.updatePlaylist(id, name: 'After', artworkPath: null);
    final updated = await repository.watchPlaylist(id).first;
    expect(updated?.name, 'After');

    await repository.deletePlaylist(id);
    expect(await repository.watchPlaylist(id).first, isNull);
  });

  test(
    'account reset clears profile, playlists, likes, and owned cover files',
    () async {
      final covers = await Directory.systemTemp.createTemp('clove-covers-');
      final cover = File('${covers.path}/cover.jpg')
        ..writeAsBytesSync([1, 2, 3]);
      final unrelated = File('${covers.path}-unrelated.txt')
        ..writeAsStringSync('keep');
      try {
        await database.saveProfile('Clove User');
        final id = await repository.createPlaylist(
          'Saved playlist',
          artworkPath: cover.path,
        );
        await repository.addToPlaylist(
          id,
          const CloveTrack(
            path: '/music/song.mp3',
            title: 'Song',
            artist: 'Artist',
            album: '',
            duration: Duration.zero,
          ),
        );
        await repository.setLiked(
          const CloveTrack(
            path: '/music/liked.mp3',
            title: 'Liked',
            artist: 'Artist',
            album: '',
            duration: Duration.zero,
          ),
          true,
        );

        await database.deleteLocalAccount(playlistCoversDirectory: covers);

        expect(await database.getProfile(), isNull);
        expect(await repository.watchPlaylists().first, isEmpty);
        expect(await repository.watchLikedTracks().first, isEmpty);
        expect(await covers.exists(), isFalse);
        expect(await unrelated.exists(), isTrue);
      } finally {
        if (await covers.exists()) await covers.delete(recursive: true);
        if (await unrelated.exists()) await unrelated.delete();
      }
    },
  );

  test('updated username persists when the database is reopened', () async {
    final file = File(
      '${Directory.systemTemp.path}/clove-profile-${DateTime.now().microsecondsSinceEpoch}.sqlite',
    );
    var diskDatabase = AppDatabase(NativeDatabase(file));
    try {
      await diskDatabase.saveProfile('Before');
      await diskDatabase.saveProfile('  New Name  ');
      await diskDatabase.close();

      diskDatabase = AppDatabase(NativeDatabase(file));
      expect((await diskDatabase.getProfile())?.name, 'New Name');
    } finally {
      await diskDatabase.close();
      if (await file.exists()) await file.delete();
    }
  });

  test(
    'pinned playlists sort first and pin changes update the stream',
    () async {
      final first = await repository.createPlaylist('First');
      final second = await repository.createPlaylist('Second');

      await repository.updatePlaylist(
        second,
        name: 'Second',
        artworkPath: null,
        isPinned: true,
      );
      var summaries = await repository.watchPlaylists().first;
      expect(summaries.first.playlist.id, second);
      expect(summaries.first.playlist.isPinned, isTrue);
      expect(summaries.last.playlist.id, first);
      expect(summaries.last.playlist.isPinned, isFalse);

      await repository.updatePlaylist(
        second,
        name: 'Second',
        artworkPath: null,
        isPinned: false,
      );
      summaries = await repository.watchPlaylists().first;
      expect(summaries.every((summary) => !summary.playlist.isPinned), isTrue);
    },
  );

  test(
    'pin toggles preserve playlist edit ordering within each group',
    () async {
      final olderId = await repository.createPlaylist('Older');
      final olderBefore = await (database.select(
        database.userPlaylists,
      )..where((playlist) => playlist.id.equals(olderId))).getSingle();
      await Future<void>.delayed(const Duration(milliseconds: 2));
      final newerId = await repository.createPlaylist('Newer');

      await repository.setPlaylistPinned(olderId, true);
      var summaries = await repository.watchPlaylists().first;
      expect(summaries.map((summary) => summary.playlist.id), [
        olderId,
        newerId,
      ]);

      await repository.setPlaylistPinned(olderId, false);
      summaries = await repository.watchPlaylists().first;
      expect(summaries.map((summary) => summary.playlist.id), [
        newerId,
        olderId,
      ]);

      final olderAfter = await (database.select(
        database.userPlaylists,
      )..where((playlist) => playlist.id.equals(olderId))).getSingle();
      expect(olderAfter.updatedAt, olderBefore.updatedAt);
      expect(olderAfter.isPinned, isFalse);
    },
  );

  test('pinned state survives reopening the SQLite database', () async {
    final file = File(
      '${Directory.systemTemp.path}/clove-pin-${DateTime.now().microsecondsSinceEpoch}.sqlite',
    );
    var diskDatabase = AppDatabase(NativeDatabase(file));
    try {
      final diskRepository = PlaylistRepository(diskDatabase);
      final id = await diskRepository.createPlaylist('Pinned');
      await diskRepository.updatePlaylist(
        id,
        name: 'Pinned',
        artworkPath: null,
        isPinned: true,
      );
      await diskDatabase.close();

      diskDatabase = AppDatabase(NativeDatabase(file));
      final summaries = await PlaylistRepository(diskDatabase)
          .watchPlaylists()
          .first;
      expect(summaries.single.playlist.id, id);
      expect(summaries.single.playlist.isPinned, isTrue);
    } finally {
      await diskDatabase.close();
      if (await file.exists()) await file.delete();
    }
  });

  test(
    'version 1 profile database upgrades without losing the profile table',
    () async {
      await database.close();
      database = AppDatabase(
        NativeDatabase.memory(
          setup: (sqlite) {
            sqlite.execute('''
            CREATE TABLE user_profiles (
              id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
              name TEXT NOT NULL CHECK(length(name) BETWEEN 1 AND 30),
              created_at INTEGER NOT NULL DEFAULT CURRENT_TIMESTAMP
            )
          ''');
            sqlite.execute('PRAGMA user_version = 1');
          },
        ),
      );
      repository = PlaylistRepository(database);

      await database.select(database.userProfiles).get();
      final id = await repository.createPlaylist('After upgrade');

      expect(await repository.watchPlaylists().first, hasLength(1));
      expect(id, greaterThan(0));
    },
  );

  test(
    'v2 playlist migration retains data and defaults pin state to false',
    () async {
      await database.close();
      database = AppDatabase(
        NativeDatabase.memory(
          setup: (sqlite) {
            sqlite.execute('''
            CREATE TABLE user_playlists (
              id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
              name TEXT NOT NULL CHECK(length(name) BETWEEN 1 AND 80),
              artwork_path TEXT,
              created_at INTEGER NOT NULL DEFAULT 0,
              updated_at INTEGER NOT NULL DEFAULT 0
            )
          ''');
            sqlite.execute('''
            CREATE TABLE playlist_tracks (
              playlist_id INTEGER NOT NULL,
              track_id TEXT NOT NULL,
              title TEXT NOT NULL,
              artist TEXT NOT NULL,
              album TEXT NOT NULL,
              duration_ms INTEGER NOT NULL,
              album_id INTEGER,
              position INTEGER NOT NULL,
              added_at INTEGER NOT NULL DEFAULT 0,
              PRIMARY KEY (playlist_id, track_id)
            )
          ''');
            sqlite.execute(
              "INSERT INTO user_playlists (name, created_at, updated_at) VALUES ('Existing', 0, 0)",
            );
            sqlite.execute('PRAGMA user_version = 2');
          },
        ),
      );
      repository = PlaylistRepository(database);

      final summaries = await repository.watchPlaylists().first;
      expect(summaries, hasLength(1));
      expect(summaries.single.playlist.name, 'Existing');
      expect(summaries.single.playlist.isPinned, isFalse);
    },
  );

  test('v4 migration tolerates artwork columns already present', () async {
    await database.close();
    database = AppDatabase(
      NativeDatabase.memory(
        setup: (sqlite) {
          sqlite.execute('''
            CREATE TABLE user_playlists (
              id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
              name TEXT NOT NULL,
              artwork_path TEXT,
              created_at INTEGER NOT NULL DEFAULT 0,
              updated_at INTEGER NOT NULL DEFAULT 0,
              is_pinned INTEGER NOT NULL DEFAULT 0
            )
          ''');
          sqlite.execute('''
            CREATE TABLE playlist_tracks (
              playlist_id INTEGER NOT NULL,
              track_id TEXT NOT NULL,
              title TEXT NOT NULL,
              artist TEXT NOT NULL,
              album TEXT NOT NULL,
              duration_ms INTEGER NOT NULL,
              album_id INTEGER,
              artwork_uri TEXT,
              position INTEGER NOT NULL,
              added_at INTEGER NOT NULL DEFAULT 0,
              PRIMARY KEY (playlist_id, track_id)
            )
          ''');
          sqlite.execute('''
            CREATE TABLE liked_tracks (
              track_id TEXT NOT NULL PRIMARY KEY,
              title TEXT NOT NULL,
              artist TEXT NOT NULL,
              album TEXT NOT NULL,
              duration_ms INTEGER NOT NULL,
              album_id INTEGER,
              artwork_uri TEXT,
              position INTEGER NOT NULL,
              liked_at INTEGER NOT NULL DEFAULT 0
            )
          ''');
          sqlite.execute('PRAGMA user_version = 4');
        },
      ),
    );
    repository = PlaylistRepository(database);

    expect(await repository.watchPlaylists().first, isEmpty);
  });
}
