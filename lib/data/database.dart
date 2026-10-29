import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'package:path_provider/path_provider.dart';

part 'database.g.dart';

class UserProfiles extends Table {
  IntColumn get id => integer().autoIncrement()();

  TextColumn get name => text().withLength(min: 1, max: 30)();

  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}

class UserPlaylists extends Table {
  IntColumn get id => integer().autoIncrement()();

  TextColumn get name => text().withLength(min: 1, max: 80)();

  TextColumn get artworkPath => text().nullable()();

  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  BoolColumn get isPinned => boolean().withDefault(const Constant(false))();
}

class PlaylistTracks extends Table {
  IntColumn get playlistId =>
      integer().references(UserPlaylists, #id, onDelete: KeyAction.cascade)();

  /// The same path/URI used by CloveTrack.path and MediaItem.id.
  TextColumn get trackId => text()();

  TextColumn get title => text()();

  TextColumn get artist => text()();

  TextColumn get album => text()();

  IntColumn get durationMs => integer()();

  IntColumn get albumId => integer().nullable()();

  TextColumn get artworkUri => text().nullable()();

  /// Stable provider identity for tracks also stored as downloaded files.
  TextColumn get canonicalId => text().nullable()();

  IntColumn get position => integer()();

  DateTimeColumn get addedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {playlistId, trackId};
}

class LikedTracks extends Table {
  TextColumn get trackId => text()();

  TextColumn get title => text()();

  TextColumn get artist => text()();

  TextColumn get album => text()();

  IntColumn get durationMs => integer()();

  IntColumn get albumId => integer().nullable()();

  TextColumn get artworkUri => text().nullable()();

  /// Stable provider identity for tracks also stored as downloaded files.
  TextColumn get canonicalId => text().nullable()();

  IntColumn get position => integer()();

  DateTimeColumn get likedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {trackId};
}

/// The active playback session is stored separately from user collections.
class PlaybackSessions extends Table {
  IntColumn get id => integer()();

  TextColumn get payload => text()();

  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}

@DriftDatabase(
  tables: [
    UserProfiles,
    UserPlaylists,
    PlaylistTracks,
    LikedTracks,
    PlaybackSessions,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase([QueryExecutor? executor])
    : super(executor ?? driftDatabase(name: 'clove_db'));

  static final AppDatabase instance = AppDatabase();

  @override
  int get schemaVersion => 6;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) => m.createAll(),
    onUpgrade: (m, from, to) async {
      if (from < 2) {
        await m.createTable(userPlaylists);
        await m.createTable(playlistTracks);
        await m.createTable(likedTracks);
      }
      // The v1 upgrade creates the current table definition. Only v2 needs
      // this column migration; existing playlist rows retain their IDs/data.
      if (from >= 2 && from < 3) {
        await m.addColumn(userPlaylists, userPlaylists.isPinned);
      }
      if (from < 4) await m.createTable(playbackSessions);
      if (from >= 2 && from < 5) {
        final existingTables = await customSelect(
          "SELECT name FROM sqlite_master WHERE type = 'table'",
        ).map((row) => row.read<String>('name')).get();

        Future<bool> hasColumn(String table, String column) async {
          if (!existingTables.contains(table)) return false;
          final columns = await customSelect('PRAGMA table_info("$table")')
              .map((row) => row.read<String>('name'))
              .get();
          return columns.contains(column);
        }

        if (!existingTables.contains('playlist_tracks')) {
          await m.createTable(playlistTracks);
        } else if (!await hasColumn('playlist_tracks', 'artwork_uri')) {
          await m.addColumn(playlistTracks, playlistTracks.artworkUri);
        }
        if (!existingTables.contains('liked_tracks')) {
          await m.createTable(likedTracks);
        } else if (!await hasColumn('liked_tracks', 'artwork_uri')) {
          await m.addColumn(likedTracks, likedTracks.artworkUri);
        }
      }
      if (from >= 2 && from < 6) {
        final playlistColumns = await customSelect(
          'PRAGMA table_info("playlist_tracks")',
        ).map((row) => row.read<String>('name')).get();
        final likedColumns = await customSelect(
          'PRAGMA table_info("liked_tracks")',
        ).map((row) => row.read<String>('name')).get();
        if (!playlistColumns.contains('canonical_id')) {
          await m.addColumn(playlistTracks, playlistTracks.canonicalId);
        }
        if (!likedColumns.contains('canonical_id')) {
          await m.addColumn(likedTracks, likedTracks.canonicalId);
        }
      }
    },
  );

  /// Returns the saved profile, or null on the first launch.
  Future<UserProfile?> getProfile() async {
    return (select(userProfiles)
          ..orderBy([(profile) => OrderingTerm.asc(profile.id)])
          ..limit(1))
        .getSingleOrNull();
  }

  Future<String?> loadPlaybackSession() async => (await (select(
    playbackSessions,
  )..where((row) => row.id.equals(1))).getSingleOrNull())?.payload;

  Future<void> savePlaybackSession(String payload) async {
    await into(playbackSessions).insertOnConflictUpdate(
      PlaybackSessionsCompanion.insert(id: const Value(1), payload: payload),
    );
  }

  Future<void> clearPlaybackSession() async {
    await (delete(playbackSessions)..where((row) => row.id.equals(1))).go();
  }

  /// Saves the user's name, updating the existing profile if present.
  Future<void> saveProfile(String name) async {
    final normalizedName = name.trim();

    if (normalizedName.isEmpty || normalizedName.length > 30) {
      throw ArgumentError('Name must be between 1 and 30 characters.');
    }

    await transaction(() async {
      final existing = await getProfile();

      if (existing == null) {
        await into(userProfiles)
            .insert(UserProfilesCompanion.insert(name: normalizedName));
      } else {
        await (update(userProfiles)
              ..where((profile) => profile.id.equals(existing.id)))
            .write(UserProfilesCompanion(name: Value(normalizedName)));
      }
    });
  }

  /// Removes the locally stored account and all data owned by that account.
  /// Playlist cover files are confined to the directory used by the editor.
  Future<void> deleteLocalAccount({Directory? playlistCoversDirectory}) async {
    await transaction(() async {
      await delete(playlistTracks).go();
      await delete(likedTracks).go();
      await delete(userPlaylists).go();
      await delete(userProfiles).go();
    });

    final covers =
        playlistCoversDirectory ??
        Directory(
          '${(await getApplicationDocumentsDirectory()).path}/playlist_covers',
        );
    if (await covers.exists()) {
      await covers.delete(recursive: true);
    }
  }
}
