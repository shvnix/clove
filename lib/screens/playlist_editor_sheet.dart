import 'dart:io';

import 'package:flutter/material.dart';

import '../services/clove_notifications.dart';

import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';

import '../data/database.dart';
import '../services/playlist_repository.dart';
import '../widgets/playlist_artwork.dart';

Future<int?> showPlaylistEditor(
  BuildContext context, {
  required PlaylistRepository repository,
  UserPlaylist? playlist,
}) => showModalBottomSheet<int>(
  context: context,
  isScrollControlled: true,
  backgroundColor: const Color(0xFF1C1C20),
  shape: const RoundedRectangleBorder(
    borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
  ),
  builder: (_) =>
      _PlaylistEditorSheet(repository: repository, playlist: playlist),
);

class _PlaylistEditorSheet extends StatefulWidget {
  const _PlaylistEditorSheet({required this.repository, this.playlist});

  final PlaylistRepository repository;
  final UserPlaylist? playlist;

  @override
  State<_PlaylistEditorSheet> createState() => _PlaylistEditorSheetState();
}

class _PlaylistEditorSheetState extends State<_PlaylistEditorSheet> {
  late final TextEditingController _nameController;
  XFile? _pickedCover;
  bool _clearCover = false;
  late bool _isPinned;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.playlist?.name ?? '');
    _isPinned = widget.playlist?.isPinned ?? false;
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _chooseCover() async {
    try {
      final image = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        imageQuality: 90,
      );
      if (!mounted || image == null) return;
      setState(() {
        _pickedCover = image;
        _clearCover = false;
      });
    } catch (error) {
      if (!mounted) return;
      CloveNotifications.show(
        context,
        SnackBar(content: Text('Could not choose that image: $error')),
      );
    }
  }

  Future<String> _persistCover(XFile source) async {
    final documents = await getApplicationDocumentsDirectory();
    final directory = Directory('${documents.path}/playlist_covers');
    await directory.create(recursive: true);
    final extension = source.path.split('.').last.toLowerCase();
    final safeExtension = RegExp(r'^[a-z0-9]{1,5}$').hasMatch(extension)
        ? extension
        : 'jpg';
    final destination = File(
      '${directory.path}/cover_${DateTime.now().microsecondsSinceEpoch}.$safeExtension',
    );
    return (await File(source.path).copy(destination.path)).path;
  }

  Future<void> _save() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      CloveNotifications.show(
        context,
        const SnackBar(content: Text('Enter a playlist name first.')),
      );
      return;
    }
    if (name.length > 80) {
      CloveNotifications.show(
        context,
        const SnackBar(content: Text('Use 80 characters or fewer.')),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      final coverPath = _pickedCover != null
          ? await _persistCover(_pickedCover!)
          : _clearCover
          ? null
          : widget.playlist?.artworkPath;
      final playlist = widget.playlist;
      final id = playlist == null
          ? await widget.repository.createPlaylist(name, artworkPath: coverPath)
          : await _update(playlist.id, name, coverPath, _isPinned);
      if (!mounted) return;
      Navigator.of(context).pop(id);
    } catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      CloveNotifications.show(
        context,
        SnackBar(content: Text('Could not save playlist: $error')),
      );
    }
  }

  Future<int> _update(
    int id,
    String name,
    String? artworkPath,
    bool isPinned,
  ) async {
    await widget.repository.updatePlaylist(
      id,
      name: name,
      artworkPath: artworkPath,
      isPinned: isPinned,
    );
    return id;
  }

  @override
  Widget build(BuildContext context) {
    final currentPath = _clearCover
        ? null
        : _pickedCover?.path ?? widget.playlist?.artworkPath;
    final keyboardInset = MediaQuery.viewInsetsOf(context).bottom;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(22, 12, 22, 20 + keyboardInset),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 38,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(5),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              Text(
                widget.playlist == null ? 'Create playlist' : 'Edit playlist',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 24),
              Center(
                child: Stack(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(18),
                      child: _pickedCover == null
                          ? PlaylistArtwork(size: 148, artworkPath: currentPath)
                          : Image.file(
                              File(_pickedCover!.path),
                              width: 148,
                              height: 148,
                              fit: BoxFit.cover,
                              errorBuilder: (_, _, _) =>
                                  const PlaylistArtwork(size: 148),
                            ),
                    ),
                    Positioned(
                      right: 5,
                      bottom: 5,
                      child: Material(
                        color: const Color(0xFF1DE9B6),
                        shape: const CircleBorder(),
                        child: IconButton(
                          tooltip: 'Choose cover image',
                          onPressed: _chooseCover,
                          icon: const Icon(
                            Icons.edit_rounded,
                            color: Color(0xFF0B0B0B),
                            size: 18,
                          ),
                        ),
                      ),
                    ),
                    if (widget.playlist?.artworkPath != null ||
                        _pickedCover != null)
                      Positioned(
                        left: 5,
                        bottom: 5,
                        child: Material(
                          color: const Color(0xCC0B0B0B),
                          shape: const CircleBorder(),
                          child: IconButton(
                            tooltip: 'Remove cover image',
                            onPressed: () => setState(() {
                              _pickedCover = null;
                              _clearCover = true;
                            }),
                            icon: const Icon(
                              Icons.close_rounded,
                              color: Colors.white,
                              size: 18,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              TextField(
                controller: _nameController,
                autofocus: widget.playlist == null,
                maxLength: 80,
                textCapitalization: TextCapitalization.sentences,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  labelText: 'Playlist name',
                  counterStyle: TextStyle(color: Colors.white38),
                ),
              ),
              if (widget.playlist != null)
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    _isPinned ? 'Pinned to Library' : 'Pin to Library',
                    style: const TextStyle(color: Colors.white),
                  ),
                  value: _isPinned,
                  activeTrackColor: const Color(0xFF1DE9B6),
                  onChanged: _saving
                      ? null
                      : (value) => setState(() => _isPinned = value),
                ),
              const SizedBox(height: 10),
              Row(
                children: [
                  TextButton(
                    onPressed: _saving ? null : () => Navigator.pop(context),
                    child: const Text(
                      'Cancel',
                      style: TextStyle(color: Colors.white70),
                    ),
                  ),
                  const Spacer(),
                  FilledButton(
                    onPressed: _saving ? null : _save,
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF1DE9B6),
                      foregroundColor: const Color(0xFF0B0B0B),
                    ),
                    child: _saving
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text(widget.playlist == null ? 'Create' : 'Save'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
