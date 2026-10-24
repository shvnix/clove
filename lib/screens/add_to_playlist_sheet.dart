import 'package:flutter/material.dart';

import '../services/clove_notifications.dart';

import '../widgets/juggle_icon_button.dart';
import '../models/clove_track.dart';
import '../services/playlist_repository.dart';
import '../services/online_library_track_resolver.dart';
import '../services/online_music_provider_scope.dart';
import '../widgets/playlist_artwork.dart';
import 'playlist_editor_sheet.dart';

Future<void> showAddToPlaylistSheet(
  BuildContext context, {
  required PlaylistRepository repository,
  required CloveTrack track,
  AnimationStyle? animationStyle,
}) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  backgroundColor: const Color(0xFF1C1C20),
  shape: const RoundedRectangleBorder(
    borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
  ),
  sheetAnimationStyle: animationStyle,
  builder: (_) => _AddToPlaylistSheet(repository: repository, track: track),
);

class _AddToPlaylistSheet extends StatefulWidget {
  const _AddToPlaylistSheet({required this.repository, required this.track});

  final PlaylistRepository repository;
  final CloveTrack track;

  @override
  State<_AddToPlaylistSheet> createState() => _AddToPlaylistSheetState();
}

class _AddToPlaylistSheetState extends State<_AddToPlaylistSheet> {
  final Set<int> _busyRows = {};
  bool _busyLiked = false;

  Future<CloveTrack> _trackForSaving() => resolvePlayableLibraryTrack(
    widget.track,
    OnlineMusicProviderScope.of(context),
  );

  Future<void> _toggleMembership(
    int playlistId, {
    required bool isSelected,
  }) async {
    if (_busyRows.contains(playlistId)) return;

    setState(() => _busyRows.add(playlistId));

    try {
      if (isSelected) {
        await widget.repository.removeFromPlaylist(
          playlistId,
          widget.track.path,
          canonicalId: widget.track.mediaId,
        );
      } else {
        final track = await _trackForSaving();
        await widget.repository.addToPlaylist(playlistId, track);
      }
    } catch (error) {
      _showError(error);
    } finally {
      if (mounted) {
        setState(() => _busyRows.remove(playlistId));
      }
    }
  }

  Future<void> _toggleLiked(TrackCollections collections) async {
    if (_busyLiked) return;

    setState(() => _busyLiked = true);

    try {
      final track = collections.isLiked
          ? widget.track
          : await _trackForSaving();
      await widget.repository.setLiked(track, !collections.isLiked);
    } catch (error) {
      _showError(error);
    } finally {
      if (mounted) {
        setState(() => _busyLiked = false);
      }
    }
  }

  Future<void> _createPlaylist() async {
    final id = await showPlaylistEditor(context, repository: widget.repository);

    if (!mounted || id == null) return;

    try {
      final track = await _trackForSaving();
      await widget.repository.addToPlaylist(id, track);

      if (mounted) {
        CloveNotifications.show(
          context,
          const SnackBar(content: Text('Added to your new playlist.')),
        );
      }
    } catch (error) {
      _showError(error);
    }
  }

  void _showError(Object error) {
    if (!mounted) return;

    CloveNotifications.show(
      context,
      SnackBar(content: Text('Could not update playlist: $error')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final maxHeight = MediaQuery.sizeOf(context).height * 0.84;

    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxHeight),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header content: 18 px horizontal padding.
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 12, 18, 0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 38,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.white24,
                      borderRadius: BorderRadius.circular(5),
                    ),
                  ),

                  const SizedBox(height: 18),

                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Saved in',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 21,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              widget.track.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Color(0xFFB7B5BE),
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: 'Close',
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(
                          Icons.close_rounded,
                          color: Colors.white70,
                        ),
                      ),
                    ],
                  ),

                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton.icon(
                      onPressed: _createPlaylist,
                      icon: const Icon(Icons.add_rounded),
                      label: const Text('New playlist'),
                      style: TextButton.styleFrom(
                        foregroundColor: const Color(0xFF1DE9B6),
                        textStyle: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Playlist list: no horizontal padding.
            // The divider can now extend to both edges.
            Flexible(
              child: StreamBuilder<TrackCollections>(
                stream: widget.repository.watchCollections(
                  widget.track.path,
                  canonicalId: widget.track.mediaId,
                ),
                builder: (context, membershipSnapshot) {
                  if (membershipSnapshot.hasError) {
                    return _message('Could not load saved playlists.');
                  }

                  final collections = membershipSnapshot.data;

                  if (collections == null) {
                    return const Center(
                      child: CircularProgressIndicator(
                        color: Color(0xFF1DE9B6),
                      ),
                    );
                  }

                  return StreamBuilder<List<PlaylistSummary>>(
                    stream: widget.repository.watchPlaylists(),
                    builder: (context, playlistsSnapshot) {
                      if (playlistsSnapshot.hasError) {
                        return _message('Could not load your playlists.');
                      }

                      final playlists = playlistsSnapshot.data;

                      if (playlists == null) {
                        return const Center(
                          child: CircularProgressIndicator(
                            color: Color(0xFF1DE9B6),
                          ),
                        );
                      }

                      final addedPlaylists = playlists
                          .where((p) => collections.contains(p.playlist.id))
                          .toList();

                      final otherPlaylists = playlists
                          .where((p) => !collections.contains(p.playlist.id))
                          .toList();

                      return ListView(
                        shrinkWrap: true,
                        padding: EdgeInsets.zero,
                        children: [
                          // Liked Songs
                          StreamBuilder<int>(
                            stream: widget.repository.watchLikedCount(),
                            builder: (context, countSnapshot) {
                              return _SavedRow(
                                artwork: const PlaylistArtwork(
                                  size: 48,
                                  likedSongs: true,
                                ),
                                title: 'Liked Songs',
                                subtitle: '${countSnapshot.data ?? 0} songs',
                                selected: collections.isLiked,
                                busy: _busyLiked,
                                onTap: () => _toggleLiked(collections),
                              );
                            },
                          ),

                          // Playlists already containing this track.
                          for (final summary in addedPlaylists)
                            _SavedRow(
                              artwork: PlaylistArtwork(
                                size: 48,
                                artworkPath: summary.playlist.artworkPath,
                              ),
                              title: summary.playlist.name,
                              subtitle: '${summary.trackCount} songs',
                              selected: true,
                              busy: _busyRows.contains(summary.playlist.id),
                              onTap: () => _toggleMembership(
                                summary.playlist.id,
                                isSelected: true,
                              ),
                            ),

                          // Full-width divider.
                          if (otherPlaylists.isNotEmpty) ...[
                            const SizedBox(height: 12),

                            const Divider(
                              color: Colors.white12,
                              height: 1,
                              thickness: 1,
                            ),

                            const SizedBox(height: 12),

                            // Other playlists.
                            for (final summary in otherPlaylists)
                              _SavedRow(
                                artwork: PlaylistArtwork(
                                  size: 48,
                                  artworkPath: summary.playlist.artworkPath,
                                ),
                                title: summary.playlist.name,
                                subtitle: '${summary.trackCount} songs',
                                selected: false,
                                busy: _busyRows.contains(summary.playlist.id),
                                onTap: () => _toggleMembership(
                                  summary.playlist.id,
                                  isSelected: false,
                                ),
                              ),
                          ],
                        ],
                      );
                    },
                  );
                },
              ),
            ),

            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Widget _message(String text) => Center(
    child: Text(text, style: const TextStyle(color: Color(0xFFB7B5BE))),
  );
}

class _SavedRow extends StatelessWidget {
  const _SavedRow({
    required this.artwork,
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.busy,
    required this.onTap,
  });

  final Widget artwork;
  final String title;
  final String subtitle;
  final bool selected;
  final bool busy;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => ListTile(
    contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 2),
    leading: artwork,
    title: Text(
      title,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
    ),
    subtitle: Text(subtitle, style: const TextStyle(color: Color(0xFFB7B5BE))),
    trailing: SizedBox.square(
      dimension: 40,
      child: busy
          ? const Padding(
              padding: EdgeInsets.all(9),
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Color(0xFF1DE9B6),
              ),
            )
          : JuggleIconButton(
              tooltip: selected ? 'Remove from playlist' : 'Add to playlist',
              size: 40,
              onPressed: onTap,
              icon: Icon(
                selected
                    ? Icons.check_circle_rounded
                    : Icons.add_circle_outline_rounded,
                color: selected ? const Color(0xFF1DE9B6) : Colors.white70,
                size: 27,
              ),
            ),
    ),
    onTap: onTap,
  );
}
