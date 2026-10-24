import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../services/clove_notifications.dart';

import 'package:permission_handler/permission_handler.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../data/database.dart';
import '../models/clove_track.dart';
import '../services/audio/playback_service.dart';
import '../services/local_audio_library.dart';
import '../services/playlist_repository.dart';
import '../widgets/local_artwork.dart';
import '../widgets/playlist_artwork.dart';
import '../widgets/juggle_icon_button.dart';
import '../widgets/queue_swipe.dart';
import 'profile_screen.dart';
import 'about_screen.dart';
import 'user_manual_screen.dart';
import 'local_music_screen.dart';
import 'playlist_detail_screen.dart';
import 'playlist_editor_sheet.dart';

const Color _obsidian = Color(0xFF0B0B0B);
const Color _cardSurface = Color(0xFF1C1C20);
const Color _cloveMint = Color(0xFF1DE9B6);
const Color _secondaryText = Color(0xFFB7B5BE);
const Color _lavender = Color(0xFF7C4DCC);

enum _LibraryFilter { playlists, albums, artists }

enum _LibrarySort { recentlyAdded, title, trackCount }

class LibraryScreen extends StatefulWidget {
  const LibraryScreen({
    super.key,
    required this.username,
    required this.onSaveUsername,
    required this.onDeleteAccount,
    this.onProfileTransitionChanged,
  });

  final String username;
  final Future<void> Function(String name) onSaveUsername;
  final Future<void> Function() onDeleteAccount;
  final ValueChanged<Animation<double>?>? onProfileTransitionChanged;

  @override
  LibraryScreenState createState() => LibraryScreenState();
}

class LibraryScreenState extends State<LibraryScreen>
    with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  final PlaylistRepository _playlists = PlaylistRepository(
    AppDatabase.instance,
  );
  late final Stream<List<PlaylistSummary>> _playlistSummaries = _playlists
      .watchPlaylists();
  late final Stream<int> _likedSongsCount = _playlists.watchLikedCount();
  final LocalAudioLibrary _localLibrary = LocalAudioLibrary();
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  late final AnimationController _profileController;
  late final Animation<double> _profileAnimation;
  OverlayEntry? _profileOverlayEntry;
  Future<void>? _profileCloseFuture;
  bool _profileDestinationOpening = false;
  late Widget _libraryHomeEntry;

  bool _profileOpen = false;
  bool _overlayRefreshScheduled = false;
  final Set<int> _pinningPlaylistIds = <int>{};

  static const Duration _profileDuration = Duration(milliseconds: 320);
  static const double _profileWidthFactor = 0.88;

  LocalAudioScanResult _scanResult = const LocalAudioScanResult(
    tracks: [],
    permissionStatus: null,
  );
  _LibraryFilter _filter = _LibraryFilter.playlists;
  _LibrarySort _sort = _LibrarySort.recentlyAdded;
  String _search = '';
  bool _searchOpen = false;
  bool _grid = false;
  bool _scanning = false;

  final List<Widget> _destinations = [];

  bool get canPopDestination => _destinations.isNotEmpty;
  bool get canPopProfile => _profileOpen;
  Animation<double> get profileTransitionAnimation => _profileAnimation;
  double get profileTransitionWidthFactor => _profileWidthFactor;

  void popDestination() {
    if (!canPopDestination || !mounted) return;
    setState(() => _destinations.removeLast());
  }

  void popProfile() {
    if (!canPopProfile) return;
    unawaited(_closeProfileScreen());
  }

  void openProfile() {
    _openProfileScreen();
  }

  Future<void> closeProfileForAccountDeletion() => _closeProfileScreen();

  Future<void> _openProfilePage(Widget page) async {
    if (!mounted || _profileDestinationOpening) return;
    _profileDestinationOpening = true;

    try {
      final route = Navigator.of(
        context,
        rootNavigator: true,
      ).push<void>(MaterialPageRoute<void>(builder: (_) => page));
      unawaited(_closeProfileScreen());
      await route;
    } finally {
      _profileDestinationOpening = false;
    }
  }

  void showLibraryHome() {
    if (_destinations.isEmpty || !mounted) return;
    setState(_destinations.clear);
  }

  void _pushDestination(Widget destination) {
    setState(() => _destinations.add(destination));
  }

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addObserver(this);

    _profileController = AnimationController(
      vsync: this,
      duration: _profileDuration,
      reverseDuration: _profileDuration,
    );

    _profileAnimation = CurvedAnimation(
      parent: _profileController,
      curve: Curves.easeInOutCubic,
      reverseCurve: Curves.easeInOutCubic,
    );

    _libraryHomeEntry = _buildLibraryHomeEntry();

    _scanLocalMusic();
  }

  @override
  void didUpdateWidget(covariant LibraryScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.username != widget.username) {
      _libraryHomeEntry = _buildLibraryHomeEntry();
    }
    if (oldWidget.username == widget.username ||
        _profileOverlayEntry == null ||
        _overlayRefreshScheduled) {
      return;
    }

    _overlayRefreshScheduled = true;
    final entry = _profileOverlayEntry;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _overlayRefreshScheduled = false;
      if (!mounted ||
          !_profileOpen ||
          !identical(_profileOverlayEntry, entry)) {
        return;
      }
      entry!.markNeedsBuild();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    final entry = _profileOverlayEntry;
    _profileOverlayEntry = null;
    if (entry != null && entry.mounted) entry.remove();
    _searchController.dispose();
    _searchFocusNode.dispose();
    _profileController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final denied = !_scanResult.hasPermission;
    if (state == AppLifecycleState.resumed && denied && !_scanning) {
      _scanLocalMusic(requestPermission: false);
    }
  }

  void _openProfileScreen() {
    if (_profileOpen || _profileOverlayEntry != null) return;
    _profileOpen = true;
    _profileOverlayEntry = OverlayEntry(builder: _buildProfileOverlay);
    Overlay.of(context, rootOverlay: true).insert(_profileOverlayEntry!);
    widget.onProfileTransitionChanged?.call(_profileAnimation);
    _profileController.forward();
  }

  Future<void> _closeProfileScreen() {
    if (!_profileOpen) return Future<void>.value();
    return _profileCloseFuture ??= _reverseAndRemoveProfile();
  }

  Future<void> _reverseAndRemoveProfile() async {
    final entry = _profileOverlayEntry;
    try {
      await _profileController.reverse();

      if (!mounted || !identical(_profileOverlayEntry, entry)) return;
      if (entry != null && entry.mounted) entry.remove();
      _profileOverlayEntry = null;
      _profileOpen = false;
      widget.onProfileTransitionChanged?.call(null);
    } finally {
      _profileCloseFuture = null;
    }
  }

  Widget _buildProfileOverlay(BuildContext context) {
    final screenWidth = MediaQuery.sizeOf(context).width;
    final panelWidth = screenWidth * _profileWidthFactor;

    return Positioned.fill(
      child: SlideTransition(
        position: Tween<Offset>(
          begin: Offset(-panelWidth / screenWidth, 0),
          end: Offset.zero,
        ).animate(_profileAnimation),
        child: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onHorizontalDragStart: (_) {
            _profileController.stop();
          },
          onHorizontalDragUpdate: (details) {
            _handleProfileDragUpdate(details, panelWidth);
          },
          onHorizontalDragEnd: _handleProfileDragEnd,
          child: ProfileScreen(
            username: widget.username,
            onSaveName: widget.onSaveUsername,
            onDeleteAccount: widget.onDeleteAccount,
            onOpenManual: () => _openProfilePage(const UserManualScreen()),
            onOpenAbout: () => _openProfilePage(const AboutScreen()),
            onClose: _closeProfileScreen,
          ),
        ),
      ),
    );
  }

  void _handleProfileDragUpdate(DragUpdateDetails details, double panelWidth) {
    _profileController.value =
        (_profileController.value + details.delta.dx / panelWidth).clamp(
          0.0,
          1.0,
        );
  }

  void _handleProfileDragEnd(DragEndDetails details) {
    final velocity = details.primaryVelocity ?? 0;

    // Swipe left to close, or close if the drawer is mostly dismissed.
    final shouldClose = velocity < -500 || _profileController.value < 0.75;

    if (shouldClose) {
      _closeProfileScreen();
    } else {
      // Restore the drawer if the swipe wasn't sufficient.
      _profileController.forward();
    }
  }

  Future<LocalAudioScanResult> _scanLocalMusic({
    bool requestPermission = true,
  }) async {
    if (_scanning) return _scanResult;
    _setLibraryState(() => _scanning = true);
    final result = await _localLibrary.scan(
      requestPermission: requestPermission,
    );
    if (!mounted) return result;
    _setLibraryState(() {
      _scanResult = result;
      _scanning = false;
    });
    return result;
  }

  void _openLocalMusic({
    LocalAudioScanResult? result,
    Iterable<CloveTrack> Function(Iterable<CloveTrack>)? trackFilter,
  }) {
    if (_scanning) {
      CloveNotifications.show(
        context,
        const SnackBar(content: Text('Clove is still scanning your music.')),
      );
      return;
    }
    _pushDestination(
      LocalMusicScreen(
        library: _localLibrary,
        initialResult: result ?? _scanResult,
        trackFilter: trackFilter,
        onClose: popDestination,
      ),
    );
  }

  Future<void> _openPermissionSettings() async {
    final opened = await openAppSettings();
    if (!opened && mounted) {
      CloveNotifications.show(
        context,
        const SnackBar(content: Text('Could not open app settings.')),
      );
    }
  }

  Future<void> _createPlaylist() async {
    await showPlaylistEditor(context, repository: _playlists);
  }

  Future<void> _openPlaylist(PlaylistSummary summary) async {
    _pushDestination(
      PlaylistDetailScreen(
        repository: _playlists,
        playlistId: summary.playlist.id,
        onClose: popDestination,
      ),
    );
  }

  Future<void> _openLikedSongs() async {
    _pushDestination(
      PlaylistDetailScreen(
        repository: _playlists,
        likedSongs: true,
        onClose: popDestination,
      ),
    );
  }

  Future<void> _showPlaylistActions(PlaylistSummary summary) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: _cardSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 10),
            Container(
              width: 38,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(5),
              ),
            ),
            ListTile(
              leading: Transform.rotate(
                angle: 0.60,
                child: Icon(
                  summary.playlist.isPinned
                      ? Icons.push_pin_rounded
                      : Icons.push_pin_outlined,
                  color: summary.playlist.isPinned ? _cloveMint : Colors.white,
                ),
              ),
              title: Text(
                summary.playlist.isPinned ? 'Unpin Playlist' : 'Pin Playlist',
              ),
              onTap: _pinningPlaylistIds.contains(summary.playlist.id)
                  ? null
                  : () => _startPlaylistPinToggle(context, summary),
            ),
            ListTile(
              leading: const Icon(Icons.edit_outlined, color: Colors.white),
              title: const Text('Edit playlist'),
              onTap: () => Navigator.pop(context, 'edit'),
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline, color: Colors.white),
              title: const Text('Delete playlist'),
              onTap: () => Navigator.pop(context, 'delete'),
            ),
          ],
        ),
      ),
    );
    if (!mounted || action == null) return;
    if (action == 'togglePin') {
      await _togglePlaylistPinned(summary);
    } else if (action == 'edit') {
      await showPlaylistEditor(
        context,
        repository: _playlists,
        playlist: summary.playlist,
      );
    } else if (action == 'delete') {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          backgroundColor: _cardSurface,
          title: const Text('Delete playlist?'),
          content: Text(
            '“${summary.playlist.name}” and its saved track list will be deleted.',
            style: const TextStyle(color: _secondaryText),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text(
                'Delete',
                style: TextStyle(color: Colors.redAccent),
              ),
            ),
          ],
        ),
      );
      if (confirmed == true) {
        try {
          await _playlists.deletePlaylist(summary.playlist.id);
          PlaybackService.clearActiveSourceIfMatches(
            PlaybackService.playlistSourceId(summary.playlist.id),
          );
          final cover = summary.playlist.artworkPath;
          if (cover != null) {
            final file = File(cover);
            if (await file.exists()) await file.delete();
          }
        } catch (error) {
          if (mounted) {
            CloveNotifications.show(
              context,
              SnackBar(content: Text('Could not delete playlist: $error')),
            );
          }
        }
      }
    }
  }

  void _startPlaylistPinToggle(
    BuildContext sheetContext,
    PlaylistSummary summary,
  ) {
    final playlistId = summary.playlist.id;
    if (!_pinningPlaylistIds.add(playlistId)) return;
    Navigator.pop(sheetContext, 'togglePin');
  }

  Future<void> _togglePlaylistPinned(PlaylistSummary summary) async {
    final playlistId = summary.playlist.id;

    try {
      await _playlists.setPlaylistPinned(
        playlistId,
        !summary.playlist.isPinned,
      );
    } catch (error) {
      if (mounted) {
        CloveNotifications.show(
          context,
          SnackBar(content: Text('Could not update playlist pin: $error')),
        );
      }
    } finally {
      _pinningPlaylistIds.remove(playlistId);
    }
  }

  List<PlaylistSummary> _visiblePlaylists(List<PlaylistSummary> playlists) {
    final query = _search.trim().toLowerCase();
    final result = playlists
        .where(
          (entry) =>
              query.isEmpty ||
              entry.playlist.name.toLowerCase().contains(query),
        )
        .toList();
    final priorOrder = {
      for (var index = 0; index < result.length; index++)
        result[index].playlist.id: index,
    };
    result.sort((a, b) {
      if (a.playlist.isPinned != b.playlist.isPinned) {
        return a.playlist.isPinned ? -1 : 1;
      }
      final comparison = switch (_sort) {
        _LibrarySort.recentlyAdded => 0,
        _LibrarySort.title => a.playlist.name.toLowerCase().compareTo(
          b.playlist.name.toLowerCase(),
        ),
        _LibrarySort.trackCount => b.trackCount.compareTo(a.trackCount),
      };
      return comparison != 0
          ? comparison
          : priorOrder[a.playlist.id]!.compareTo(priorOrder[b.playlist.id]!);
    });
    return result;
  }

  Future<bool> _queuePlaylist(PlaylistSummary summary) async {
    final tracks = await _playlists
        .watchPlaylistTracks(summary.playlist.id)
        .first;
    if (tracks.isEmpty) return false;
    return PlaybackService.queueTracksOrStart(
      tracks,
      sourceId: PlaybackService.playlistSourceId(summary.playlist.id),
      sourcePositions: List<int>.generate(tracks.length, (index) => index),
    );
  }

  List<_TrackGroup> _groups(List<CloveTrack> tracks) {
    final query = _search.trim().toLowerCase();
    final byName = <String, List<CloveTrack>>{};
    for (final track in tracks) {
      final name = _filter == _LibraryFilter.albums
          ? track.album
          : track.artist;
      final normalized = name.trim().isEmpty
          ? (_filter == _LibraryFilter.albums
                ? 'Unknown album'
                : 'Unknown artist')
          : name.trim();
      byName.putIfAbsent(normalized, () => []).add(track);
    }
    final groups = byName.entries
        .map((entry) => _TrackGroup(entry.key, entry.value))
        .where((group) {
          if (query.isEmpty) return true;
          return group.name.toLowerCase().contains(query) ||
              group.tracks.any(
                (track) =>
                    track.title.toLowerCase().contains(query) ||
                    track.artist.toLowerCase().contains(query) ||
                    track.album.toLowerCase().contains(query),
              );
        })
        .toList();
    if (_sort == _LibrarySort.title) {
      groups.sort(
        (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
      );
    } else if (_sort == _LibrarySort.trackCount) {
      groups.sort((a, b) => b.tracks.length.compareTo(a.tracks.length));
    } else {
      groups.sort(
        (a, b) => (b.latestAdded?.millisecondsSinceEpoch ?? 0).compareTo(
          a.latestAdded?.millisecondsSinceEpoch ?? 0,
        ),
      );
    }
    return groups;
  }

  void _toggleSearch() {
    _setLibraryState(() {
      _searchOpen = !_searchOpen;
      if (!_searchOpen) {
        _search = '';
        _searchController.clear();
      }
    });
  }

  void _setLibraryState(VoidCallback update) {
    if (!mounted) return;
    setState(() {
      update();
      _libraryHomeEntry = _buildLibraryHomeEntry();
    });
  }

  Widget _buildLibraryHomeEntry() => StreamBuilder<String?>(
    stream: PlaybackService.playbackSourceStream,
    initialData: PlaybackService.activeSourceId,
    builder: (context, sourceSnapshot) => StreamBuilder<bool>(
      stream: PlaybackService.isPlayingStream,
      initialData: PlaybackService.isPlaying,
      builder: (context, playingSnapshot) => _buildLibraryHome(
        activeSourceId: sourceSnapshot.data,
        isPlaying: playingSnapshot.data ?? false,
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final screenWidth = constraints.maxWidth;
        final panelWidth = screenWidth * _profileWidthFactor;

        return Scaffold(
          backgroundColor: _obsidian,
          body: Stack(
            clipBehavior: Clip.hardEdge,
            children: [
              // Library moves exactly as far as the profile panel is wide.
              AnimatedBuilder(
                animation: _profileAnimation,
                child: IndexedStack(
                  index: _destinations.length,
                  children: [_libraryHomeEntry, ..._destinations],
                ),
                builder: (context, child) {
                  final progress = _profileAnimation.value;

                  return Transform.translate(
                    offset: Offset(panelWidth * progress, 0),
                    child: Stack(
                      fit: StackFit.passthrough,
                      children: [
                        child!,

                        // Fade the library to black as the profile opens.
                      ],
                    ),
                  );
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildLibraryHome({
    required String? activeSourceId,
    required bool isPlaying,
  }) => Scaffold(
    backgroundColor: _obsidian,

    appBar: AppBar(
      backgroundColor: _obsidian,
      foregroundColor: Colors.white,
      elevation: 0,
      scrolledUnderElevation: 0,
      automaticallyImplyLeading: false,
      titleSpacing: 2,
      title: Row(
        children: [
          GestureDetector(
            onTap: _openProfileScreen,
            behavior: HitTestBehavior.opaque,
            child: SizedBox(
              width: 56,
              height: 56,
              child: Center(
                child: Container(
                  width: 34,
                  height: 34,
                  alignment: Alignment.center,
                  decoration: const BoxDecoration(
                    color: _cloveMint,
                    shape: BoxShape.circle,
                  ),
                  child: Text(
                    widget.username.trim().isEmpty
                        ? '?'
                        : widget.username.trim()[0].toUpperCase(),
                    style: const TextStyle(
                      color: _obsidian,
                      fontSize: 24,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 4),
          const Expanded(
            child: Text(
              'Your Library',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
            ),
          ),
        ],
      ),
      actions: [
        JuggleIconButton(
          tooltip: _searchOpen ? 'Close search' : 'Search library',
          onPressed: _toggleSearch,
          size: 48,
          icon: _searchOpen
              ? const Icon(Icons.close_rounded, color: Colors.white, size: 36)
              : SvgPicture.asset(
                  'assets/icon/search.svg',
                  width: 24,
                  height: 24,
                  colorFilter: const ColorFilter.mode(
                    Colors.white,
                    BlendMode.srcIn,
                  ),
                ),
        ),
        JuggleIconButton(
          tooltip: 'Create playlist',
          onPressed: _createPlaylist,
          size: 48,
          icon: const Icon(Icons.add_rounded, size: 42, color: Colors.white),
        ),
        const SizedBox(width: 6),
      ],
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(52),
        child: SizedBox(
          height: 52,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            scrollDirection: Axis.horizontal,
            children: [
              _filterChip(_LibraryFilter.playlists, 'Playlists'),
              const SizedBox(width: 8),
              _filterChip(_LibraryFilter.albums, 'Albums'),
              const SizedBox(width: 8),
              _filterChip(_LibraryFilter.artists, 'Artists'),
            ],
          ),
        ),
      ),
    ),

    body: Stack(
      children: [
        // Scrollable library page
        SafeArea(
          top: false,
          bottom: false,
          child: CustomScrollView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            slivers: [
              // Search field
              if (_searchOpen)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(18, 6, 18, 12),
                    child: TextField(
                      controller: _searchController,
                      focusNode: _searchFocusNode,
                      autofocus: true,
                      onTapOutside: (_) => FocusScope.of(context).unfocus(),
                      onChanged: (value) =>
                          _setLibraryState(() => _search = value),
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        hintText: _filter == _LibraryFilter.playlists
                            ? 'Search playlists'
                            : _filter == _LibraryFilter.albums
                            ? 'Search albums or tracks'
                            : 'Search artists or tracks',
                        prefixIcon: Padding(
                          padding: const EdgeInsets.all(14),
                          child: SvgPicture.asset(
                            'assets/icon/search.svg',
                            width: 18,
                            height: 18,
                            colorFilter: const ColorFilter.mode(
                              _secondaryText,
                              BlendMode.srcIn,
                            ),
                          ),
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: const BorderSide(
                            color: _cloveMint,
                            width: 1.5,
                          ),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: const BorderSide(
                            color: _cloveMint,
                            width: 1.5,
                          ),
                        ),
                        suffixIcon: _search.isEmpty
                            ? null
                            : JuggleIconButton(
                                tooltip: 'Clear search',
                                onPressed: () {
                                  _searchController.clear();
                                  _setLibraryState(() => _search = '');
                                  _searchFocusNode.requestFocus();
                                },
                                size: 40,
                                icon: const Icon(
                                  Icons.clear,
                                  color: _secondaryText,
                                ),
                              ),
                      ),
                    ),
                  ),
                ),

              // Recently added / grid controls
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                  child: Row(
                    children: [
                      PopupMenuButton<_LibrarySort>(
                        initialValue: _sort,
                        color: _cardSurface,
                        onSelected: (sort) =>
                            _setLibraryState(() => _sort = sort),
                        itemBuilder: (_) => const [
                          PopupMenuItem(
                            value: _LibrarySort.recentlyAdded,
                            child: Text('Recently added'),
                          ),
                          PopupMenuItem(
                            value: _LibrarySort.title,
                            child: Text('Title'),
                          ),
                          PopupMenuItem(
                            value: _LibrarySort.trackCount,
                            child: Text('Track count'),
                          ),
                        ],
                        child: Row(
                          children: [
                            const Icon(
                              Icons.swap_vert_rounded,
                              color: Colors.white70,
                              size: 19,
                            ),
                            const SizedBox(width: 5),
                            Text(
                              switch (_sort) {
                                _LibrarySort.recentlyAdded => 'Recently added',
                                _LibrarySort.title => 'Title',
                                _LibrarySort.trackCount => 'Track count',
                              },
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const Icon(
                              Icons.arrow_drop_down,
                              color: Colors.white70,
                            ),
                          ],
                        ),
                      ),
                      const Spacer(),
                      JuggleIconButton(
                        tooltip: _grid ? 'Show list' : 'Show grid',
                        onPressed: () => _setLibraryState(() => _grid = !_grid),
                        size: 40,
                        icon: Icon(
                          _grid
                              ? Icons.view_list_rounded
                              : Icons.grid_view_rounded,
                          color: Colors.white70,
                          size: 22,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // Library content in the same scroll view
              SliverToBoxAdapter(
                child: StreamBuilder<List<PlaylistSummary>>(
                  stream: _playlistSummaries,
                  builder: (context, playlistsSnapshot) => StreamBuilder<int>(
                    stream: _likedSongsCount,
                    builder: (context, likedSnapshot) =>
                        StreamBuilder<List<CloveTrack>>(
                          stream: _playlists.watchSavedTracks(),
                          builder: (context, savedSnapshot) =>
                              _buildLibraryContent(
                                playlistsSnapshot.data ?? const [],
                                likedSnapshot.data ?? 0,
                                playlistsSnapshot.hasError ||
                                    likedSnapshot.hasError ||
                                    savedSnapshot.hasError,
                                savedTracks: savedSnapshot.data ?? const [],
                                activeSourceId: activeSourceId,
                                isPlaying: isPlaying,
                              ),
                        ),
                  ),
                ),
              ),

              // Extra bottom space for the mini-player / navigation bar
              const SliverToBoxAdapter(child: SizedBox(height: 180)),
            ],
          ),
        ),

        // Fixed, dark shadow immediately below the AppBar.
        // The controls scroll underneath this shadow.
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: IgnorePointer(
            child: Container(
              height: 4,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.black, Colors.black, Colors.transparent],
                  stops: const [0.0, 0.4, 1.0],
                ),
              ),
            ),
          ),
        ),
      ],
    ),
  );

  Widget _filterChip(_LibraryFilter filter, String label) {
    final selected = _filter == filter;

    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => _setLibraryState(() => _filter = filter),
      showCheckmark: false,
      selectedColor: _cloveMint,
      backgroundColor: _cardSurface,
      labelStyle: TextStyle(
        color: selected ? _obsidian : Colors.white,
        fontSize: 13,
        fontWeight: FontWeight.w700,
      ),
      side: BorderSide.none,
      shape: const StadiumBorder(),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    );
  }

  Widget _buildLibraryContent(
    List<PlaylistSummary> playlists,
    int likedCount,
    bool databaseError, {
    required List<CloveTrack> savedTracks,
    required String? activeSourceId,
    required bool isPlaying,
  }) {
    if (databaseError) {
      return _emptyMessage(
        Icons.storage_rounded,
        'Library unavailable',
        'Clove could not read saved playlists. Restart the app and try again.',
      );
    }
    final visiblePlaylists = _visiblePlaylists(playlists);
    final localPaths = _scanResult.tracks.map((track) => track.path).toSet();
    final groupedTracks = [
      ..._scanResult.tracks,
      ...savedTracks.where((track) => !localPaths.contains(track.path)),
    ];
    final groups = _groups(groupedTracks);
    final hasQuery = _search.trim().isNotEmpty;
    final noMatches = _filter == _LibraryFilter.playlists
        ? visiblePlaylists.isEmpty && hasQuery
        : groups.isEmpty && hasQuery;

    return ListView(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      children: [
        if (_filter == _LibraryFilter.playlists) ...[
          if (_scanning && !_scanResult.hasPermission)
            const LinearProgressIndicator(
              minHeight: 2,
              color: _cloveMint,
              backgroundColor: Colors.white10,
            ),
          _builtInEntry(
            title: 'Liked Songs',
            subtitle: '$likedCount songs',
            artwork: Container(
              width: 58,
              height: 58,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [_lavender, Color(0xFFDCCBFF)],
                ),
                borderRadius: BorderRadius.circular(13),
              ),
              child: const Icon(
                Icons.favorite_rounded,
                color: Colors.white,
                size: 28,
              ),
            ),
            onTap: _openLikedSongs,
            isActive: activeSourceId == PlaybackService.likedSongsSourceId,
          ),
          _builtInEntry(
            title: 'Local Music',
            subtitle: _scanning
                ? 'Scanning your device…'
                : _scanResult.hasPermission
                ? '${_scanResult.tracks.length} songs on this device'
                : 'Music saved on this device',
            artwork: Container(
              width: 58,
              height: 58,
              decoration: BoxDecoration(
                color: const Color(0xFF202622),
                borderRadius: BorderRadius.circular(13),
              ),
              child: const Icon(
                Icons.phone_android_rounded,
                color: _cloveMint,
                size: 28,
              ),
            ),
            trailing: SizedBox(
              width: 30,
              child: JuggleIconButton(
                tooltip: 'Refresh local music',
                onPressed: _scanning ? null : () => _scanLocalMusic(),
                size: 40,
                icon: Icon(
                  Icons.refresh_rounded,
                  color: Colors.white60,
                  size: 24,
                ),
              ),
            ),
            onTap: () => _openLocalMusic(),
            isActive: activeSourceId == PlaybackService.localMusicSourceId,
          ),
          const SizedBox(height: 14),
          if (visiblePlaylists.isEmpty && !hasQuery)
            _emptyMessage(
              Icons.queue_music_rounded,
              'Create your first playlist',
              'Keep the music you love together in one place.',
              action: 'Create playlist',
              onAction: _createPlaylist,
            )
          else if (visiblePlaylists.isNotEmpty)
            _playlistEntries(
              visiblePlaylists,
              activeSourceId: activeSourceId,
              isPlaying: isPlaying,
            ),
        ] else ...[
          if (!_scanResult.hasPermission && !_scanning)
            _permissionPrompt()
          else if (_scanResult.error != null && !_scanning)
            _emptyMessage(
              Icons.error_outline_rounded,
              'Could not scan local music',
              'Try refreshing your on-device music library.',
              action: 'Retry scan',
              onAction: () => _scanLocalMusic(),
            ),
          if (_scanning && _scanResult.tracks.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 30),
              child: Center(
                child: CircularProgressIndicator(color: _cloveMint),
              ),
            ),
          if (groups.isEmpty && !_scanning && !hasQuery)
            _emptyMessage(
              Icons.library_music_outlined,
              'No ${_filter.name} found',
              'Scan your local music to build this collection.',
              action: 'Scan music',
              onAction: () => _scanLocalMusic(),
            ),
          if (groups.isNotEmpty) _groupEntries(groups),
        ],
        if (noMatches)
          _emptyMessage(
            Icons.search_off_rounded,
            'No matches',
            'Try a different name or search term.',
          ),
      ],
    );
  }

  Widget _builtInEntry({
    required String title,
    required String subtitle,
    required Widget artwork,
    required VoidCallback onTap,
    bool isActive = false,
    Widget? trailing,
  }) => Material(
    color: Colors.transparent,
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.only(
          left: 12, // Move image boxes to the right
          right: 12,
          top: 7,
          bottom: 7,
        ),
        child: Row(
          children: [
            artwork,
            const SizedBox(width: 13),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: isActive ? _cloveMint : Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: const TextStyle(color: _secondaryText, fontSize: 12),
                  ),
                ],
              ),
            ),
            ?trailing,
          ],
        ),
      ),
    ),
  );

  Widget _playlistEntries(
    List<PlaylistSummary> playlists, {
    required String? activeSourceId,
    required bool isPlaying,
  }) {
    if (_grid) {
      return GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: playlists.length,
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          crossAxisSpacing: 14,
          mainAxisSpacing: 10,
          childAspectRatio: 0.8,
        ),
        itemBuilder: (context, index) => _playlistGridTile(
          playlists[index],
          isActive:
              activeSourceId ==
              PlaybackService.playlistSourceId(playlists[index].playlist.id),
        ),
      );
    }
    return Column(
      children: [
        for (final playlist in playlists)
          _playlistListTile(
            playlist,
            isActive:
                activeSourceId ==
                PlaybackService.playlistSourceId(playlist.playlist.id),
          ),
      ],
    );
  }

  Widget _playlistGridTile(PlaylistSummary summary, {required bool isActive}) =>
      QueueSwipe(
        successMessage: 'Playlist added to queue',
        onQueue: () => _queuePlaylist(summary),
        child: GestureDetector(
          onLongPress: () => _showPlaylistActions(summary),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => _openPlaylist(summary),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: LayoutBuilder(
                      builder: (context, constraints) => PlaylistArtwork(
                        size: constraints.maxWidth,
                        artworkPath: summary.playlist.artworkPath,
                        borderRadius: 14,
                      ),
                    ),
                  ),
                  const SizedBox(height: 9),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          summary.playlist.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: isActive ? _cloveMint : Colors.white,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      if (summary.playlist.isPinned) ...[
                        Transform.rotate(
                          angle: 0.60,
                          child: const Icon(
                            Icons.push_pin_rounded,
                            color: _cloveMint,
                            size: 12,
                          ),
                        ),
                        const SizedBox(width: 4),
                      ],
                      Expanded(
                        child: Text(
                          'Playlist · ${summary.trackCount} songs',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: _secondaryText,
                            fontSize: 11,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      );

  Widget _playlistListTile(PlaylistSummary summary, {required bool isActive}) =>
      QueueSwipe(
        successMessage: 'Playlist added to queue',
        onQueue: () => _queuePlaylist(summary),
        child: GestureDetector(
          onLongPress: () => _showPlaylistActions(summary),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => _openPlaylist(summary),
            child: Padding(
              padding: const EdgeInsets.only(
                left: 12, // Move image 10 pixels to the right
                right: 12,
                top: 7,
                bottom: 7,
              ),
              child: Row(
                children: [
                  PlaylistArtwork(
                    size: 58,
                    artworkPath: summary.playlist.artworkPath,
                  ),
                  const SizedBox(width: 13),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                summary.playlist.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: isActive ? _cloveMint : Colors.white,
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            if (summary.playlist.isPinned) ...[
                              Transform.rotate(
                                angle: 0.60,
                                child: const Icon(
                                  Icons.push_pin_rounded,
                                  color: _cloveMint,
                                  size: 13,
                                ),
                              ),
                              const SizedBox(width: 5),
                            ],
                            Expanded(
                              child: Text(
                                'Playlist · ${summary.trackCount} songs',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: _secondaryText,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  SizedBox(
                    width: 30,
                    child: JuggleIconButton(
                      tooltip: 'Playlist options',
                      onPressed: () => _showPlaylistActions(summary),
                      size: 40,
                      icon: const Icon(
                        Icons.more_vert_rounded,
                        color: Colors.white54,
                        size: 24,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );

  Widget _groupEntries(List<_TrackGroup> groups) {
    if (_grid) {
      return GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: groups.length,
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          crossAxisSpacing: 14,
          mainAxisSpacing: 12,
          childAspectRatio: 0.86,
        ),
        itemBuilder: (_, index) => _groupGridTile(groups[index]),
      );
    }
    return Column(
      children: [for (final group in groups) _groupListTile(group)],
    );
  }

  Widget _groupGridTile(_TrackGroup group) => InkWell(
    borderRadius: BorderRadius.circular(16),
    onTap: () => _openGroup(group),
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) => LocalArtwork(
                track: group.tracks.first,
                size: constraints.maxWidth,
                borderRadius: 14,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            group.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            '${group.tracks.length} ${_filter == _LibraryFilter.albums ? 'songs' : 'tracks'}',
            style: const TextStyle(color: _secondaryText, fontSize: 11),
          ),
        ],
      ),
    ),
  );

  Widget _groupListTile(_TrackGroup group) => GestureDetector(
    behavior: HitTestBehavior.opaque,
    onTap: () => _openGroup(group),
    child: Padding(
      padding: const EdgeInsets.only(
        left: 12, // Move image boxes to the right
        right: 12,
        top: 7,
        bottom: 7,
      ),
      child: Row(
        children: [
          LocalArtwork(track: group.tracks.first, size: 58, borderRadius: 13),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  group.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${group.tracks.length} ${_filter == _LibraryFilter.albums ? 'songs' : 'tracks'}',
                  style: const TextStyle(color: _secondaryText, fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );

  void _openGroup(_TrackGroup group) {
    final selected = group.tracks.map((track) => track.path).toSet();
    _openLocalMusic(
      result: LocalAudioScanResult(
        tracks: group.tracks,
        permissionStatus: _scanResult.permissionStatus,
      ),
      trackFilter: (tracks) =>
          tracks.where((track) => selected.contains(track.path)),
    );
  }

  Widget _permissionPrompt() {
    final status = _scanResult.permissionStatus;
    final settings = status?.isPermanentlyDenied ?? false;
    final restricted = status?.isRestricted ?? false;
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Material(
        color: _cardSurface,
        borderRadius: BorderRadius.circular(16),
        child: ListTile(
          leading: const Icon(Icons.folder_off_outlined, color: _cloveMint),
          title: Text(
            restricted ? 'Music access is restricted' : 'Allow music access',
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
          ),
          subtitle: Text(
            settings || restricted
                ? 'Open Android settings to allow local music scanning.'
                : 'Grant access to show your albums and artists.',
            style: const TextStyle(color: _secondaryText),
          ),
          trailing: JuggleIconButton(
            tooltip: settings || restricted ? 'Open settings' : 'Refresh music',
            onPressed: () {
              if (settings || restricted) {
                _openPermissionSettings();
              } else {
                _scanLocalMusic();
              }
            },
            size: 48,
            icon: Icon(
              settings || restricted
                  ? Icons.settings_outlined
                  : Icons.refresh_rounded,
              color: Colors.white70,
            ),
          ),
        ),
      ),
    );
  }

  Widget _emptyMessage(
    IconData icon,
    String title,
    String message, {
    String? action,
    VoidCallback? onAction,
  }) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 12),
    child: Column(
      children: [
        Icon(icon, size: 42, color: _cloveMint),
        const SizedBox(height: 12),
        Text(
          title,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 7),
        Text(
          message,
          textAlign: TextAlign.center,
          style: const TextStyle(color: _secondaryText, height: 1.45),
        ),
        if (action != null && onAction != null) ...[
          const SizedBox(height: 15),
          FilledButton(
            onPressed: onAction,
            style: FilledButton.styleFrom(
              foregroundColor: _obsidian,
              backgroundColor: _cloveMint,
            ),
            child: Text(action),
          ),
        ],
      ],
    ),
  );
}

class _TrackGroup {
  const _TrackGroup(this.name, this.tracks);

  final String name;
  final List<CloveTrack> tracks;

  DateTime? get latestAdded {
    DateTime? latest;
    for (final track in tracks) {
      final added = track.dateAdded;
      if (added != null && (latest == null || added.isAfter(latest))) {
        latest = added;
      }
    }
    return latest;
  }
}
