import 'package:drift/drift.dart';

import '../data/database.dart';
import '../models/clove_track.dart';
import 'offline_track_artwork.dart';

const int likedSongsPlaylistId = -1;

class PlaylistSummary {
  const PlaylistSummary({required this.playlist, required this.trackCount});

  final UserPlaylist playlist;
  final int trackCount;
}

class TrackCollections {
  const TrackCollections({required this.isLiked, required this.playlistIds});

  final bool isLiked;
  final Set<int> playlistIds;

  bool contains(int playlistId) => playlistIds.contains(playlistId);
}

/// Drift-backed playlist and liked-song operations. Track identity is the
/// source path/URI also used by [CloveTrack.path] and `MediaItem.id`.
class PlaylistRepository {
  PlaylistRepository(this.database);

  final AppDatabase database;

  Stream<List<PlaylistSummary>> watchPlaylists() {
    final count = database.playlistTracks.trackId.count();
    final query = database.select(database.userPlaylists).join([
      leftOuterJoin(
        database.playlistTracks,
        database.playlistTracks.playlistId.equalsExp(database.userPlaylists.id),
      ),
    ])..addColumns([count]);
    query
      ..groupBy([database.userPlaylists.id])
      ..orderBy([
        OrderingTerm.desc(database.userPlaylists.isPinned),
        OrderingTerm.desc(database.userPlaylists.updatedAt),
        OrderingTerm.asc(database.userPlaylists.name),
      ]);

    return query.watch().map(
      (rows) => rows
          .map(
            (row) => PlaylistSummary(
              playlist: row.readTable(database.userPlaylists),
              trackCount: row.read(count) ?? 0,
            ),
          )
          .toList(growable: false),
    );
  }

  Stream<UserPlaylist?> watchPlaylist(int playlistId) {
    final query = database.select(database.userPlaylists)
      ..where((playlist) => playlist.id.equals(playlistId));
    return query.watch().map((rows) => rows.firstOrNull);
  }

  Stream<List<CloveTrack>> watchPlaylistTracks(int playlistId) {
    final query = database.select(database.playlistTracks)
      ..where((entry) => entry.playlistId.equals(playlistId))
      ..orderBy([(entry) => OrderingTerm.asc(entry.position)]);
    return query.watch().map(
      (entries) => entries.map(_fromPlaylistEntry).toList(growable: false),
    );
  }

  Stream<List<CloveTrack>> watchLikedTracks() {
    final query = database.select(database.likedTracks)
      ..orderBy([(entry) => OrderingTerm.asc(entry.position)]);
    return query.watch().map(
      (entries) => entries.map(_fromLikedEntry).toList(growable: false),
    );
  }

  /// Watches every track saved in liked songs or at least one playlist.
  /// This also includes downloaded online tracks, whose file path is stored
  /// as the track identity in the same collection tables.
  Stream<List<CloveTrack>> watchSavedTracks() {
    const query = '''
      SELECT track_id, title, artist, album, duration_ms, album_id, artwork_uri
      FROM liked_tracks
      UNION
      SELECT track_id, title, artist, album, duration_ms, album_id, artwork_uri
      FROM playlist_tracks
    ''';
    return database
        .customSelect(
          query,
          readsFrom: {database.likedTracks, database.playlistTracks},
        )
        .watch()
        .map(
          (rows) => rows
              .map(
                (row) => CloveTrack(
                  path: row.read<String>('track_id'),
                  title: row.read<String>('title'),
                  artist: row.read<String>('artist'),
                  album: row.read<String>('album'),
                  duration: Duration(
                    milliseconds: row.read<int>('duration_ms'),
                  ),
                  albumId: row.readNullable<int>('album_id'),
                  artworkUri: Uri.tryParse(
                    row.readNullable<String>('artwork_uri') ?? '',
                  ),
                ),
              )
              .toList(growable: false),
        );
  }

  Stream<int> watchLikedCount() => database
      .select(database.likedTracks)
      .watch()
      .map((entries) => entries.length);

  Stream<TrackCollections> watchCollections(
    String trackId, {
    String? canonicalId,
  }) {
    final stableId = canonicalId ?? trackId;
    const query = '''
      SELECT 'liked' AS kind, 0 AS playlist_id
      FROM liked_tracks WHERE track_id = ? OR canonical_id = ?
      UNION ALL
      SELECT 'playlist' AS kind, playlist_id
      FROM playlist_tracks WHERE track_id = ? OR canonical_id = ?
    ''';
    return database
        .customSelect(
          query,
          variables: [
            Variable.withString(trackId),
            Variable.withString(stableId),
            Variable.withString(trackId),
            Variable.withString(stableId),
          ],
          readsFrom: {database.likedTracks, database.playlistTracks},
        )
        .watch()
        .map((rows) {
          var liked = false;
          final playlistIds = <int>{};
          for (final row in rows) {
            if (row.read<String>('kind') == 'liked') {
              liked = true;
            } else {
              playlistIds.add(row.read<int>('playlist_id'));
            }
          }
          return TrackCollections(isLiked: liked, playlistIds: playlistIds);
        });
  }

  Future<int> createPlaylist(String name, {String? artworkPath}) async {
    final normalizedName = name.trim();
    if (normalizedName.isEmpty) {
      throw ArgumentError('Playlist name cannot be empty.');
    }
    if (normalizedName.length > 80) {
      throw ArgumentError('Playlist name must be 80 characters or fewer.');
    }
    final now = DateTime.now();
    return database
        .into(database.userPlaylists)
        .insert(
          UserPlaylistsCompanion.insert(
            name: normalizedName,
            artworkPath: Value(artworkPath),
            createdAt: Value(now),
            updatedAt: Value(now),
          ),
        );
  }

  Future<void> updatePlaylist(
    int id, {
    required String name,
    required String? artworkPath,
    bool? isPinned,
  }) async {
    final normalizedName = name.trim();
    if (normalizedName.isEmpty || normalizedName.length > 80) {
      throw ArgumentError('Playlist name must be between 1 and 80 characters.');
    }
    final pinnedValue = isPinned == null
        ? const Value<bool>.absent()
        : Value<bool>(isPinned);
    await (database.update(
      database.userPlaylists,
    )..where((playlist) => playlist.id.equals(id))).write(
      UserPlaylistsCompanion(
        name: Value(normalizedName),
        artworkPath: Value(artworkPath),
        isPinned: pinnedValue,
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  /// Changes pin priority without changing the playlist's edit timestamp.
  Future<void> setPlaylistPinned(int id, bool isPinned) =>
      (database.update(database.userPlaylists)
            ..where((playlist) => playlist.id.equals(id)))
          .write(UserPlaylistsCompanion(isPinned: Value(isPinned)));

  Future<void> deletePlaylist(int id) => database.transaction(() async {
    await (database.delete(
      database.playlistTracks,
    )..where((entry) => entry.playlistId.equals(id))).go();
    await (database.delete(
      database.userPlaylists,
    )..where((playlist) => playlist.id.equals(id))).go();
  });

  Future<void> addToPlaylist(int playlistId, CloveTrack track) async {
    track = await withOfflineTrackArtwork(track);
    await database.transaction(() async {
      final existing =
          await (database.select(database.playlistTracks)..where(
                (entry) =>
                    entry.playlistId.equals(playlistId) &
                    (entry.trackId.equals(track.path) |
                        (track.mediaId == null
                            ? const Constant(false)
                            : entry.canonicalId.equals(track.mediaId!))),
              ))
              .getSingleOrNull();
      if (existing != null) {
        // If this item was first saved from a stream URL, replace its stored
        // playback path with the downloaded file when Search/Now Playing
        // provides the offline copy later.
        if (existing.trackId != track.path ||
            existing.canonicalId != track.mediaId ||
            existing.artworkUri != track.artworkUri?.toString()) {
          await (database.update(database.playlistTracks)..where(
                (entry) =>
                    entry.playlistId.equals(playlistId) &
                    entry.trackId.equals(existing.trackId),
              ))
              .write(
                PlaylistTracksCompanion(
                  trackId: Value(track.path),
                  title: Value(track.title),
                  artist: Value(track.artist),
                  album: Value(track.album),
                  durationMs: Value(track.duration.inMilliseconds),
                  albumId: Value(track.albumId),
                  artworkUri: Value(track.artworkUri?.toString()),
                  canonicalId: Value(track.mediaId),
                ),
              );
        }
        return;
      }
      final entries = await (database.select(
        database.playlistTracks,
      )..where((entry) => entry.playlistId.equals(playlistId))).get();
      await database
          .into(database.playlistTracks)
          .insert(
            PlaylistTracksCompanion.insert(
              playlistId: playlistId,
              trackId: track.path,
              title: track.title,
              artist: track.artist,
              album: track.album,
              durationMs: track.duration.inMilliseconds,
              albumId: Value(track.albumId),
              artworkUri: Value(track.artworkUri?.toString()),
              canonicalId: Value(track.mediaId),
              position: entries.length,
            ),
          );
      await (database.update(database.userPlaylists)
            ..where((playlist) => playlist.id.equals(playlistId)))
          .write(UserPlaylistsCompanion(updatedAt: Value(DateTime.now())));
    });
  }

  Future<void> removeFromPlaylist(
    int playlistId,
    String trackId, {
    String? canonicalId,
  }) async {
    await database.transaction(() async {
      await (database.delete(database.playlistTracks)..where(
            (entry) =>
                entry.playlistId.equals(playlistId) &
                (entry.trackId.equals(trackId) |
                    (canonicalId == null
                        ? const Constant(false)
                        : entry.canonicalId.equals(canonicalId))),
          ))
          .go();
      final remaining =
          await (database.select(database.playlistTracks)
                ..where((entry) => entry.playlistId.equals(playlistId))
                ..orderBy([(entry) => OrderingTerm.asc(entry.position)]))
              .get();
      for (var index = 0; index < remaining.length; index++) {
        if (remaining[index].position != index) {
          await (database.update(database.playlistTracks)..where(
                (entry) =>
                    entry.playlistId.equals(playlistId) &
                    entry.trackId.equals(remaining[index].trackId),
              ))
              .write(PlaylistTracksCompanion(position: Value(index)));
        }
      }
    });
  }

  Future<void> togglePlaylistMembership(
    int playlistId,
    CloveTrack track,
  ) async {
    track = await withOfflineTrackArtwork(track);
    await database.transaction(() async {
      final existing =
          await (database.select(database.playlistTracks)..where(
                (entry) =>
                    entry.playlistId.equals(playlistId) &
                    (entry.trackId.equals(track.path) |
                        (track.mediaId == null
                            ? const Constant(false)
                            : entry.canonicalId.equals(track.mediaId!))),
              ))
              .getSingleOrNull();

      if (existing == null) {
        final entries = await (database.select(
          database.playlistTracks,
        )..where((entry) => entry.playlistId.equals(playlistId))).get();
        await database
            .into(database.playlistTracks)
            .insert(
              PlaylistTracksCompanion.insert(
                playlistId: playlistId,
                trackId: track.path,
                title: track.title,
                artist: track.artist,
                album: track.album,
                durationMs: track.duration.inMilliseconds,
                albumId: Value(track.albumId),
                artworkUri: Value(track.artworkUri?.toString()),
                canonicalId: Value(track.mediaId),
                position: entries.length,
              ),
            );
        await (database.update(database.userPlaylists)
              ..where((playlist) => playlist.id.equals(playlistId)))
            .write(UserPlaylistsCompanion(updatedAt: Value(DateTime.now())));
        return;
      }

      await (database.delete(database.playlistTracks)..where(
            (entry) =>
                entry.playlistId.equals(playlistId) &
                entry.trackId.equals(existing.trackId),
          ))
          .go();
      final remaining =
          await (database.select(database.playlistTracks)
                ..where((entry) => entry.playlistId.equals(playlistId))
                ..orderBy([(entry) => OrderingTerm.asc(entry.position)]))
              .get();
      for (var index = 0; index < remaining.length; index++) {
        if (remaining[index].position != index) {
          await (database.update(database.playlistTracks)..where(
                (entry) =>
                    entry.playlistId.equals(playlistId) &
                    entry.trackId.equals(remaining[index].trackId),
              ))
              .write(PlaylistTracksCompanion(position: Value(index)));
        }
      }
    });
  }

  Future<void> setLiked(CloveTrack track, bool liked) async {
    if (liked) track = await withOfflineTrackArtwork(track);
    await database.transaction(() async {
      final existing =
          await (database.select(database.likedTracks)..where(
                (entry) =>
                    entry.trackId.equals(track.path) |
                    (track.mediaId == null
                        ? const Constant(false)
                        : entry.canonicalId.equals(track.mediaId!)),
              ))
              .getSingleOrNull();
      if (liked &&
          existing != null &&
          (existing.trackId != track.path ||
              existing.canonicalId != track.mediaId ||
              existing.artworkUri != track.artworkUri?.toString())) {
        await (database.update(
          database.likedTracks,
        )..where((entry) => entry.trackId.equals(existing.trackId))).write(
          LikedTracksCompanion(
            trackId: Value(track.path),
            title: Value(track.title),
            artist: Value(track.artist),
            album: Value(track.album),
            durationMs: Value(track.duration.inMilliseconds),
            albumId: Value(track.albumId),
            artworkUri: Value(track.artworkUri?.toString()),
            canonicalId: Value(track.mediaId),
          ),
        );
      }
      if (liked && existing == null) {
        final entries = await database.select(database.likedTracks).get();
        await database
            .into(database.likedTracks)
            .insert(
              LikedTracksCompanion.insert(
                trackId: track.path,
                title: track.title,
                artist: track.artist,
                album: track.album,
                durationMs: track.duration.inMilliseconds,
                albumId: Value(track.albumId),
                artworkUri: Value(track.artworkUri?.toString()),
                canonicalId: Value(track.mediaId),
                position: entries.length,
              ),
            );
      } else if (!liked && existing != null) {
        await (database.delete(database.likedTracks)..where(
              (entry) =>
                  entry.trackId.equals(track.path) |
                  (track.mediaId == null
                      ? const Constant(false)
                      : entry.canonicalId.equals(track.mediaId!)),
            ))
            .go();
        final remaining = await (database.select(
          database.likedTracks,
        )..orderBy([(entry) => OrderingTerm.asc(entry.position)])).get();
        for (var index = 0; index < remaining.length; index++) {
          if (remaining[index].position != index) {
            await (database.update(database.likedTracks)..where(
                  (entry) => entry.trackId.equals(remaining[index].trackId),
                ))
                .write(LikedTracksCompanion(position: Value(index)));
          }
        }
      }
    });
  }

  /// Toggles a track in liked songs and returns its state after the change.
  /// The read and write share a transaction so notification taps cannot add
  /// duplicate entries or make decisions from a stale UI cache.
  Future<bool> toggleLiked(CloveTrack track) async {
    track = await withOfflineTrackArtwork(track);
    return database.transaction(() async {
      final existing =
          await (database.select(database.likedTracks)..where(
                (entry) =>
                    entry.trackId.equals(track.path) |
                    (track.mediaId == null
                        ? const Constant(false)
                        : entry.canonicalId.equals(track.mediaId!)),
              ))
              .getSingleOrNull();

      if (existing == null) {
        final entries = await database.select(database.likedTracks).get();
        await database
            .into(database.likedTracks)
            .insert(
              LikedTracksCompanion.insert(
                trackId: track.path,
                title: track.title,
                artist: track.artist,
                album: track.album,
                durationMs: track.duration.inMilliseconds,
                albumId: Value(track.albumId),
                artworkUri: Value(track.artworkUri?.toString()),
                canonicalId: Value(track.mediaId),
                position: entries.length,
              ),
            );
        return true;
      }

      if (existing.canonicalId == null && track.mediaId != null) {
        await (database.update(database.likedTracks)
              ..where((entry) => entry.trackId.equals(existing.trackId)))
            .write(LikedTracksCompanion(canonicalId: Value(track.mediaId)));
      }

      if (existing.trackId != track.path) {
        await (database.delete(
          database.likedTracks,
        )..where((entry) => entry.trackId.equals(existing.trackId))).go();
      } else {
        await (database.delete(
          database.likedTracks,
        )..where((entry) => entry.trackId.equals(track.path))).go();
      }
      final remaining = await (database.select(
        database.likedTracks,
      )..orderBy([(entry) => OrderingTerm.asc(entry.position)])).get();
      for (var index = 0; index < remaining.length; index++) {
        if (remaining[index].position != index) {
          await (database.update(database.likedTracks)..where(
                (entry) => entry.trackId.equals(remaining[index].trackId),
              ))
              .write(LikedTracksCompanion(position: Value(index)));
        }
      }
      return false;
    });
  }

  static CloveTrack _fromPlaylistEntry(PlaylistTrack entry) => CloveTrack(
    path: entry.trackId,
    title: entry.title,
    artist: entry.artist,
    album: entry.album,
    duration: Duration(milliseconds: entry.durationMs),
    albumId: entry.albumId,
    mediaId: entry.canonicalId,
    artworkUri: entry.artworkUri == null
        ? null
        : Uri.tryParse(entry.artworkUri!),
  );

  static CloveTrack _fromLikedEntry(LikedTrack entry) => CloveTrack(
    path: entry.trackId,
    title: entry.title,
    artist: entry.artist,
    album: entry.album,
    duration: Duration(milliseconds: entry.durationMs),
    albumId: entry.albumId,
    mediaId: entry.canonicalId,
    artworkUri: entry.artworkUri == null
        ? null
        : Uri.tryParse(entry.artworkUri!),
  );
}
