import 'dart:async';
import 'dart:math' as math;

import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../data/database.dart';
import '../models/clove_track.dart';
import '../models/online_music_track.dart';
import '../services/audio/playback_queue.dart';
import '../services/audio/playback_service.dart';
import '../services/online_music_provider.dart';
import '../services/online_music_provider_scope.dart';
import '../services/online_playback_bridge.dart';
import '../services/playlist_repository.dart';
import '../services/recent_online_tracks.dart';
import '../services/rhythm_guard_service.dart';
import '../widgets/juggle_icon_button.dart';
import '../widgets/local_artwork.dart';
import '../widgets/playlist_artwork.dart';
import 'playlist_detail_screen.dart';

const Color _obsidian = Color(0xFF0B0B0B);
const Color _cardSurface = Color(0xFF1C1C20);
const Color _cloveMint = Color(0xFF1DE9B6);
const Color _primaryText = Color(0xFFFFFFFF);
const Color _secondaryText = Color(0xFFB7B5BE);
const List<String> _featuredArtistNames = [
  'The Weeknd',
  'Karan Aujla',
  'Dhanda Nyoliwala',
  'Arijit Singh',
  'AP Dhillon',
  'Diljit Dosanjh',
  'Shubh',
  'Sidhu Moose Wala',
  'Taylor Swift',
  'Drake',
];
const Map<String, String> _featuredArtistAssets = {
  'The Weeknd': 'assets/artists/weeknd.jpg',
  'Karan Aujla': 'assets/artists/karan.jpg',
  'Dhanda Nyoliwala': 'assets/artists/dhanda.jpg',
  'Arijit Singh': 'assets/artists/arijit.jpg',
  'AP Dhillon': 'assets/artists/dhillon.jpg',
  'Diljit Dosanjh': 'assets/artists/diljit.jpg',
  'Shubh': 'assets/artists/shubh.jpg',
  'Sidhu Moose Wala': 'assets/artists/Sidhumoosewala.jpg',
  'Taylor Swift': 'assets/artists/taylor.jpg',
  'Drake': 'assets/artists/drake.jpg',
};

class HomeScreen extends StatefulWidget {
  final String username;
  final VoidCallback onOpenProfile;
  final VoidCallback? onOpenSearch;
  final ValueChanged<String>? onOpenSearchQuery;
  final VoidCallback? onOpenLibrary;
  final ValueChanged<int>? onOpenPlaylist;
  final bool isActive;

  const HomeScreen({
    super.key,
    required this.username,
    required this.onOpenProfile,
    this.onOpenSearch,
    this.onOpenSearchQuery,
    this.onOpenLibrary,
    this.onOpenPlaylist,
    this.isActive = true,
  });

  @override
  HomeScreenState createState() => HomeScreenState();
}

class HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  final RecentOnlineTracks _recentStore = RecentOnlineTracks();
  final PlaylistRepository _repository = PlaylistRepository(
    AppDatabase.instance,
  );
  final RhythmGuardService _rhythmGuardService = RhythmGuardService.instance;
  Stream<List<CloveTrack>> get _likedStream => _repository.watchLikedTracks();
  Stream<MediaItem?> get _mediaStream => PlaybackService.mediaItemStream;
  Stream<PlaybackState> get _playbackStream =>
      PlaybackService.playbackStateStream;

  List<OnlineMusicTrack> _recentTracks = const [];
  List<OnlineMusicTrack> _homeRecommendations = const [];
  List<PlaylistSummary> _playlists = const [];
  OnlineMusicProvider? _provider;
  StreamSubscription<List<OnlineMusicTrack>>? _recentChangesSubscription;
  StreamSubscription<List<PlaylistSummary>>? _playlistsSubscription;
  StreamSubscription<MediaItem?>? _mediaItemSubscription;
  StreamSubscription<PlaybackState>? _playbackStateSubscription;
  int _recentLoadRevision = 0;
  int _homeRecommendationGeneration = 0;

  bool _loadingRecents = true;
  bool _loadingHomeRecommendations = false;
  bool _homeRecommendationsLoaded = false;
  bool _homeRecommendationsFailed = false;
  bool _loadingPlaylists = true;
  bool _playlistsFailed = false;
  MediaItem? _currentMediaItem;
  bool _isPlaybackPlaying = false;
  String? _openingRecent;
  int _playGeneration = 0;

  List<Widget Function()> get _homeItems => [
    _quickAccess,
    () => const SizedBox(height: 26),
    () => _sectionHeader('Rhythm Guard'),
    () => const SizedBox(height: 8),
    _rhythmGuard,
    () => const SizedBox(height: 8),
    () => _sectionHeader(
      _recentTracks.isEmpty ? 'Recommendations' : 'Recently played',
      action: 'Search',
      onAction: widget.onOpenSearch,
    ),
    () => const SizedBox(height: 8),
    _recentSection,
    () => const SizedBox(height: 8),
    () => _sectionHeader(
      'Artists',
      action: 'Search',
      onAction: widget.onOpenSearch,
    ),
    () => const SizedBox(height: 8),
    _artistsSection,
    () => const SizedBox(height: 27),

    _nowPlayingCard,

    () => const SizedBox(height: 27),
    () => _sectionHeader(
      'Your playlists',
      action: 'Library',
      onAction: widget.onOpenLibrary,
    ),
    () => const SizedBox(height: 12),
    _playlistsSection,
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _recentChangesSubscription = RecentOnlineTracks.changes.listen((tracks) {
      _recentLoadRevision++;
      if (tracks.isNotEmpty) _homeRecommendationGeneration++;
      if (!mounted) return;
      setState(() {
        _recentTracks = tracks;
        _loadingRecents = false;
        if (tracks.isNotEmpty) _loadingHomeRecommendations = false;
      });
      if (tracks.isEmpty) _ensureHomeRecommendations();
    });
    _playlistsSubscription = _repository.watchPlaylists().listen(
      (playlists) {
        if (!mounted) return;
        setState(() {
          _playlists = playlists;
          _loadingPlaylists = false;
          _playlistsFailed = false;
        });
      },
      onError: (Object _) {
        if (!mounted) return;
        setState(() {
          _loadingPlaylists = false;
          _playlistsFailed = true;
        });
      },
    );
    _mediaItemSubscription = PlaybackService.mediaItemStream.listen((item) {
      if (!mounted) return;
      setState(() => _currentMediaItem = item);
    });
    _playbackStateSubscription = PlaybackService.playbackStateStream.listen((
      state,
    ) {
      if (!mounted || _isPlaybackPlaying == state.playing) return;
      setState(() => _isPlaybackPlaying = state.playing);
    });
    unawaited(_loadRecents());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final provider = context
        .dependOnInheritedWidgetOfExactType<OnlineMusicProviderScope>()
        ?.provider;
    if (!identical(_provider, provider)) {
      _provider = provider;
      _ensureHomeRecommendations();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_recentChangesSubscription?.cancel());
    unawaited(_playlistsSubscription?.cancel());
    unawaited(_mediaItemSubscription?.cancel());
    unawaited(_playbackStateSubscription?.cancel());

    super.dispose();
  }

  Future<void> _loadRecents() async {
    final revision = _recentLoadRevision;
    final tracks = await _recentStore.load();
    if (!mounted || revision != _recentLoadRevision) return;
    setState(() {
      _recentTracks = tracks;
      _loadingRecents = false;
    });
    if (tracks.isEmpty) _ensureHomeRecommendations();
  }

  void _ensureHomeRecommendations() {
    final provider = _provider;
    if (_loadingRecents ||
        _recentTracks.isNotEmpty ||
        _homeRecommendationsLoaded ||
        _loadingHomeRecommendations ||
        provider == null) {
      return;
    }
    final generation = ++_homeRecommendationGeneration;
    _loadingHomeRecommendations = true;
    unawaited(_loadHomeRecommendations(provider, generation));
  }

  Future<void> _loadHomeRecommendations(
    OnlineMusicProvider provider,
    int generation,
  ) async {
    const queries = [
      'popular songs official audio',
      'new songs official audio',
      'top songs official audio',
    ];
    final pages = await Future.wait(
      queries.map((query) async {
        try {
          return await provider
              .search(query)
              .timeout(const Duration(seconds: 30));
        } on Object {
          return const OnlineMusicPage(tracks: []);
        }
      }),
    );
    if (!mounted ||
        generation != _homeRecommendationGeneration ||
        _recentTracks.isNotEmpty) {
      return;
    }

    final recommendations = <OnlineMusicTrack>[];
    final seenIds = <String>{};
    for (var index = 0; index < pages.length; index++) {
      for (final track in rankMusicResults(
        queries[index],
        pages[index].tracks,
      )) {
        final key = '${track.providerId}:${track.id}'.toLowerCase();
        if (seenIds.add(key)) recommendations.add(track);
        if (recommendations.length == 10) break;
      }
      if (recommendations.length == 10) break;
    }

    setState(() {
      _homeRecommendations = List.unmodifiable(recommendations);
      _loadingHomeRecommendations = false;
      _homeRecommendationsLoaded = true;
      _homeRecommendationsFailed = recommendations.isEmpty;
    });
  }

  void _searchArtist(String artist) {
    widget.onOpenSearchQuery?.call('$artist songs');
  }

  void _openLikedSongs() => Navigator.of(context).push<void>(
    MaterialPageRoute<void>(
      builder: (_) =>
          PlaylistDetailScreen(repository: _repository, likedSongs: true),
    ),
  );

  void _openPlaylist(PlaylistSummary summary) {
    final onOpenPlaylist = widget.onOpenPlaylist;
    if (onOpenPlaylist != null) {
      onOpenPlaylist(summary.playlist.id);
      return;
    }
    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => PlaylistDetailScreen(
          repository: _repository,
          playlistId: summary.playlist.id,
        ),
      ),
    );
  }

  Future<void> _playRecent(OnlineMusicTrack track) async {
    final provider = _provider;
    if (provider == null) return;
    final generation = ++_playGeneration;
    final key = '${track.providerId}:${track.id}';
    setState(() => _openingRecent = key);
    try {
      var source = await provider.resolvePlaybackSource(track);
      if (source.expiresAt != null &&
          !source.expiresAt!.isAfter(
            DateTime.now().add(const Duration(seconds: 15)),
          )) {
        source = await provider.refreshPlaybackSource(track);
      }
      if (!mounted || generation != _playGeneration) return;
      await PlaybackService.startTracks([
        cloveTrackFromOnlineSource(track, source),
      ], sourceId: searchRecentsSourceId);
      unawaited(_recordRecent(track));
      unawaited(_queueRemainingRecents(track, generation));
    } catch (_) {
      if (mounted && generation == _playGeneration) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not play this recent song.')),
        );
      }
    } finally {
      if (mounted && generation == _playGeneration) {
        setState(() => _openingRecent = null);
      }
    }
  }

  bool _isHomeTrackCurrent(OnlineMusicTrack track) {
    final item = _currentMediaItem;
    if (item == null) return false;
    final canonicalId = canonicalTrackIdFromMediaItem(item);
    final trackId = trackIdFromMediaItem(item);
    final sourcePage = track.sourcePage.toString();
    return canonicalId == sourcePage ||
        trackId == sourcePage ||
        canonicalId == track.id ||
        trackId == track.id;
  }

  bool _isHomeTrackPlaying(OnlineMusicTrack track) =>
      _isPlaybackPlaying && _isHomeTrackCurrent(track);

  bool _isPlaylistPlaying(PlaylistSummary playlist) {
    final item = _currentMediaItem;
    return _isPlaybackPlaying &&
        item?.extras?['sourceType'] == 'playlist' &&
        item?.extras?['sourcePlaylistId'] == playlist.playlist.id;
  }

  Future<void> _toggleHomeTrack(OnlineMusicTrack track) async {
    if (_isHomeTrackCurrent(track)) {
      if (_isPlaybackPlaying) {
        await PlaybackService.pause();
      } else {
        await PlaybackService.play();
      }
      return;
    }
    await _playRecent(track);
  }

  Future<void> _recordRecent(OnlineMusicTrack track) async {
    final tracks = await _recentStore.record(track, moveToTop: false);
    if (mounted) setState(() => _recentTracks = tracks);
  }

  Future<void> _queueRemainingRecents(
    OnlineMusicTrack selected,
    int generation,
  ) async {
    final provider = _provider;
    if (provider == null) return;
    final selectedKey = '${selected.providerId}:${selected.id}';
    final remaining = _recentTracks.where(
      (track) => '${track.providerId}:${track.id}' != selectedKey,
    );
    final additions = <CloveTrack>[];
    for (final track in remaining) {
      if (!mounted || generation != _playGeneration) return;
      try {
        var source = await provider.resolvePlaybackSource(track);
        if (source.expiresAt != null &&
            !source.expiresAt!.isAfter(
              DateTime.now().add(const Duration(seconds: 15)),
            )) {
          source = await provider.refreshPlaybackSource(track);
        }
        additions.add(cloveTrackFromOnlineSource(track, source));
      } on Exception {
        // Skip unavailable old recents while preserving the remaining order.
      }
    }
    if (additions.isNotEmpty && mounted && generation == _playGeneration) {
      await PlaybackService.addTracksToQueue(
        additions,
        sourceId: searchRecentsSourceId,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final homeItems = _homeItems;
    final initial = widget.username.trim().isEmpty
        ? '?'
        : widget.username.trim()[0].toUpperCase();
    return Scaffold(
      backgroundColor: _obsidian,
      appBar: AppBar(
        backgroundColor: _obsidian,
        foregroundColor: _primaryText,
        elevation: 0,
        scrolledUnderElevation: 0,
        automaticallyImplyLeading: false,
        titleSpacing: 2,
        title: Row(
          children: [
            GestureDetector(
              onTap: widget.onOpenProfile,
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
                      initial,
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
            Expanded(
              child: Text(
                widget.username,
                style: const TextStyle(
                  color: _primaryText,
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
      ),
      body: ListView.builder(
        padding: const EdgeInsets.fromLTRB(14, 8, 14, 200),
        itemCount: homeItems.length,
        itemBuilder: (context, index) => homeItems[index](),
      ),
    );
  }

  Widget _quickAccess() => StreamBuilder<List<CloveTrack>>(
    stream: _likedStream,
    builder: (context, snapshot) {
      final count = snapshot.data?.length ?? 0;
      final recent = _recentTracks.isEmpty ? null : _recentTracks.first;
      return Column(
        children: [
          Row(
            children: [
              Expanded(
                child: _quickTile(
                  'Liked Songs',
                  '$count songs',
                  const PlaylistArtwork(size: 52, likedSongs: true),
                  _openLikedSongs,
                ),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: _quickTile(
                  'Search Recents',
                  recent?.artist ?? 'Your recent plays',
                  recent == null
                      ? _smallIcon(Icons.history_rounded)
                      : _onlineArtwork(recent, 52),
                  widget.onOpenSearch,
                ),
              ),
            ],
          ),
          const SizedBox(height: 9),
          Row(
            children: [
              Expanded(
                child: _quickTile(
                  'Explore music',
                  'Search online',
                  _smallIcon(Icons.travel_explore_rounded),
                  widget.onOpenSearch,
                ),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: _quickTile(
                  'Your library',
                  'Playlists and music',
                  _smallIcon(Icons.library_music_rounded),
                  widget.onOpenLibrary,
                ),
              ),
            ],
          ),
        ],
      );
    },
  );

  Widget _quickTile(
    String title,
    String subtitle,
    Widget artwork,
    VoidCallback? onTap,
  ) => Material(
    color: const Color(0xFF202024),
    borderRadius: BorderRadius.circular(9),
    clipBehavior: Clip.antiAlias,
    child: InkWell(
      onTap: onTap,
      child: SizedBox(
        height: 68,
        child: Row(
          children: [
            SizedBox(width: 52, height: 68, child: ClipRect(child: artwork)),
            const SizedBox(width: 9),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(right: 7),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: _primaryText,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: _secondaryText,
                        fontSize: 10,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );

  Widget _smallIcon(IconData icon) => Container(
    width: 52,
    height: 68,
    decoration: const BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFF174B42), Color(0xFF26332F)],
      ),
    ),
    alignment: Alignment.center,
    child: Icon(icon, color: _cloveMint, size: 24),
  );

  Widget _nowPlayingCard() => StreamBuilder<MediaItem?>(
    stream: _mediaStream,
    builder: (context, snapshot) {
      final item = snapshot.data;
      if (item == null) {
        return Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF193D35), Color(0xFF18221F), Color(0xFF211C29)],
            ),
          ),
          child: Row(
            children: [
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'YOUR MUSIC, YOUR MOMENT',
                      style: TextStyle(
                        color: _cloveMint,
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1,
                      ),
                    ),
                    SizedBox(height: 9),
                    Text(
                      'Find the sound\nthat feels like you.',
                      style: TextStyle(
                        color: _primaryText,
                        fontSize: 22,
                        height: 1.12,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton.filled(
                onPressed: widget.onOpenSearch,
                style: IconButton.styleFrom(
                  backgroundColor: _cloveMint,
                  foregroundColor: _obsidian,
                ),
                icon: SvgPicture.asset(
                  'assets/icon/search.svg',
                  width: 18,
                  height: 18,
                ),
              ),
            ],
          ),
        );
      }
      return Container(
        padding: const EdgeInsets.all(13),
        decoration: BoxDecoration(
          color: _cardSurface,
          borderRadius: BorderRadius.circular(17),
          // border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
        ),
        child: Row(
          children: [
            _mediaArtwork(item, 66),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'PICK UP WHERE YOU LEFT OFF',
                    style: TextStyle(
                      color: _cloveMint,
                      fontSize: 9,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.7,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    item.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: _primaryText,
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    item.artist ?? 'Unknown artist',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: _secondaryText, fontSize: 11),
                  ),
                ],
              ),
            ),
            StreamBuilder<PlaybackState>(
              stream: _playbackStream,
              builder: (context, state) {
                final playing = state.data?.playing ?? false;

                return JuggleIconButton(
                  tooltip: playing ? 'Pause' : 'Play',
                  size: 44, // Original button size
                  onPressed: () => unawaited(
                    playing ? PlaybackService.pause() : PlaybackService.play(),
                  ),
                  icon: Container(
                    width: 39,
                    height: 39,
                    decoration: const BoxDecoration(
                      color: _cloveMint,
                      shape: BoxShape.circle,
                    ),
                    alignment: Alignment.center,
                    child: Icon(
                      playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                      size: 25,
                      color: const Color(0xFF0B0B0B),
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      );
    },
  );

  Widget _recentSection() {
    if (_loadingRecents) {
      return const SizedBox(
        height: 190,
        child: Center(
          child: CircularProgressIndicator(color: _cloveMint, strokeWidth: 2),
        ),
      );
    }

    final showingRecommendations = _recentTracks.isEmpty;
    if (showingRecommendations &&
        (_loadingHomeRecommendations || !_homeRecommendationsLoaded)) {
      return const SizedBox(
        height: 190,
        child: Center(
          child: CircularProgressIndicator(color: _cloveMint, strokeWidth: 2),
        ),
      );
    }
    if (showingRecommendations && _homeRecommendationsFailed) {
      return _emptyCard(
        'Recommendations unavailable',
        'Online songs could not be loaded right now.',
        Icons.cloud_off_rounded,
      );
    }

    final tracks = showingRecommendations
        ? _homeRecommendations.take(10).toList()
        : _recentTracks.take(12).toList();

    return SizedBox(
      height: 190,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 4),
        itemCount: tracks.length,
        separatorBuilder: (_, _) => const SizedBox(width: 13),
        itemBuilder: (context, index) {
          final track = tracks[index];
          final key = '${track.providerId}:${track.id}';
          final isPlaying = _isHomeTrackPlaying(track);

          return SizedBox(
            width: 160,
            child: Material(
              color: _cardSurface,
              borderRadius: BorderRadius.circular(27),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: () => unawaited(_toggleHomeTrack(track)),
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Center(
                          child: AspectRatio(
                            aspectRatio: 1,
                            child: Stack(
                              fit: StackFit.expand,
                              children: [
                                ClipPath(
                                  clipper: _BottomArchClipper(),
                                  child: _onlineArtwork(track, 142),
                                ),

                                if (_openingRecent == key)
                                  ClipPath(
                                    clipper: _BottomArchClipper(),
                                    child: Container(
                                      color: Colors.black54,
                                      child: const Center(
                                        child: CircularProgressIndicator(
                                          color: _cloveMint,
                                          strokeWidth: 2,
                                        ),
                                      ),
                                    ),
                                  ),

                                Positioned(
                                  right: 8,
                                  bottom: 0,
                                  child: Material(
                                    color: _cloveMint,
                                    shape: const CircleBorder(),
                                    elevation: 3,
                                    child: InkWell(
                                      customBorder: const CircleBorder(),
                                      onTap: () =>
                                          unawaited(_toggleHomeTrack(track)),
                                      child: SizedBox(
                                        width: 42,
                                        height: 42,
                                        child: Center(
                                          child: isPlaying
                                              ? const PlayingEqualizer()
                                              : const Icon(
                                                  Icons.play_arrow_rounded,
                                                  color: _obsidian,
                                                  size: 28,
                                                ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),

                      const SizedBox(height: 9),

                      Text(
                        track.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: isPlaying ? _cloveMint : _primaryText,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),

                      Text(
                        track.artist ?? track.creatorName ?? 'Unknown artist',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: _secondaryText,
                          fontSize: 10,
                        ),
                      ),
                      const SizedBox(height: 3),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _artistsSection() {
    return SizedBox(
      height: 158,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.only(left: 0, right: 8, top: 0),
        itemCount: _featuredArtistNames.length,
        separatorBuilder: (_, _) => const SizedBox(width: 9),
        itemBuilder: (context, index) {
          final artist = _featuredArtistNames[index];

          return SizedBox(
            width: 120,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => _searchArtist(artist),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _artistArtwork(artist),
                  const SizedBox(height: 5),
                  SizedBox(
                    width: 132,
                    child: Text(
                      artist,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: _primaryText,
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        height: 1.2,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _artistArtwork(String artist) {
    final assetPath = _featuredArtistAssets[artist]!;
    Widget image(double size) => Image.asset(
      assetPath,
      width: size,
      height: size,
      fit: BoxFit.cover,
      errorBuilder: (_, _, _) => Container(
        width: size,
        height: size,
        color: _cardSurface,
        alignment: Alignment.center,
        child: Icon(Icons.person_rounded, color: _cloveMint, size: size * 0.42),
      ),
    );

    Widget steppedLayer({
      required double left,
      required double top,
      required double size,
      required double opacity,
    }) {
      return Positioned(
        left: left,
        top: top,
        child: Opacity(
          opacity: opacity,
          child: ClipPath(clipper: _ArtistStepClipper(), child: image(size)),
        ),
      );
    }

    return SizedBox(
      width: 132,
      height: 128,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          steppedLayer(left: 4, top: 16, size: 88, opacity: 0.45),
          steppedLayer(left: 12, top: 8, size: 88, opacity: 0.65),
          steppedLayer(left: 20, top: 2, size: 88, opacity: 0.85),

          // Main artwork.
          Positioned(
            left: 22,
            top: 14,
            child: ClipPath(
              clipper: _ArtistStepClipper(),
              child: SizedBox(width: 96, height: 100, child: image(100)),
            ),
          ),

          // Floating play button.
          Positioned(
            right: 3,
            bottom: 1,
            child: Material(
              color: _cloveMint,
              shape: const CircleBorder(),
              elevation: 2,
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: () => _searchArtist(artist),
                child: const SizedBox(
                  width: 35,
                  height: 35,
                  child: Icon(
                    Icons.play_arrow_rounded,
                    color: _obsidian,
                    size: 23,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _rhythmGuard() => StreamBuilder<RhythmGuardSnapshot>(
    stream: _rhythmGuardService.stream,
    initialData: _rhythmGuardService.snapshot,
    builder: (context, snapshot) {
      final usage = snapshot.data ?? _rhythmGuardService.snapshot;
      final progressColor = usage.limitReached || usage.progress >= 0.9
          ? const Color(0xFFFF5252)
          : usage.progress >= 0.7
          ? const Color(0xFFFFD54F)
          : _cloveMint;
      final percentage = (usage.progress * 100).round();
      final status = usage.limitReached
          ? 'Daily listening limit reached'
          : usage.warning
          ? 'Warning: your daily limit is close'
          : 'Tap to adjust your daily listening limit';

      return Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: () => _editRhythmGuardLimit(usage),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              gradient: const LinearGradient(
                colors: [Color(0xFF152E29), Color(0xFF202026)],
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                SizedBox(
                  width: 82,
                  height: 82,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      SizedBox.expand(
                        child: CircularProgressIndicator(
                          value: usage.progress,
                          strokeWidth: 5,
                          strokeCap: StrokeCap.round,
                          backgroundColor: Colors.white12,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            progressColor,
                          ),
                        ),
                      ),
                      Text(
                        '$percentage%',
                        style: const TextStyle(
                          color: _primaryText,
                          fontSize: 21,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Expanded(
                            child: Text(
                              'Rhythm Guard',
                              style: TextStyle(
                                color: _primaryText,
                                fontSize: 14,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 9,
                              vertical: 5,
                            ),
                            decoration: BoxDecoration(
                              color: _cloveMint.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: const Text(
                              'Adaptive Guard',
                              style: TextStyle(
                                color: _cloveMint,
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Text(
                        'Today: ${_formatListeningTime(usage.listened)} / '
                        '${_formatListeningTime(usage.limit)}',
                        style: const TextStyle(
                          color: _primaryText,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 7),
                      Text(
                        status,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: usage.warning || usage.limitReached
                              ? progressColor
                              : _secondaryText,
                          fontSize: 10,
                          fontWeight: usage.warning || usage.limitReached
                              ? FontWeight.w700
                              : FontWeight.w400,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );

  Future<void> _editRhythmGuardLimit(RhythmGuardSnapshot current) async {
    var hours = current.dailyLimitMinutes ~/ 60;
    var minutes = current.dailyLimitMinutes % 60;
    final selectedLimit = await showDialog<Duration>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          final minuteOptions = hours == 24
              ? const <int>[0]
              : List<int>.generate(60, (index) => index);
          final isValid = hours > 0 || minutes > 0;
          return AlertDialog(
            backgroundColor: _cardSurface,
            title: const Text(
              'Daily listening limit',
              style: TextStyle(color: _primaryText),
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Rhythm Guard counts time while music is actively playing.',
                  style: TextStyle(color: _secondaryText, fontSize: 13),
                ),
                const SizedBox(height: 18),
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<int>(
                        initialValue: hours,
                        decoration: const InputDecoration(labelText: 'Hours'),
                        items: List<DropdownMenuItem<int>>.generate(
                          25,
                          (value) => DropdownMenuItem(
                            value: value,
                            child: Text('$value h'),
                          ),
                        ),
                        onChanged: (value) {
                          if (value == null) return;
                          setDialogState(() {
                            hours = value;
                            if (hours == 24) minutes = 0;
                          });
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: DropdownButtonFormField<int>(
                        initialValue: minutes,
                        decoration: const InputDecoration(labelText: 'Minutes'),
                        items: minuteOptions
                            .map(
                              (value) => DropdownMenuItem(
                                value: value,
                                child: Text('$value min'),
                              ),
                            )
                            .toList(growable: false),
                        onChanged: hours == 24
                            ? null
                            : (value) {
                                if (value != null) {
                                  setDialogState(() => minutes = value);
                                }
                              },
                      ),
                    ),
                  ],
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: isValid
                    ? () => Navigator.pop(
                        dialogContext,
                        Duration(hours: hours, minutes: minutes),
                      )
                    : null,
                child: const Text('Save limit'),
              ),
            ],
          );
        },
      ),
    );
    if (!mounted || selectedLimit == null) return;
    await _rhythmGuardService.setDailyLimit(selectedLimit);
  }

  String _formatListeningTime(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    if (hours == 0) return '$minutes min';
    return minutes == 0 ? '${hours}h' : '${hours}h ${minutes}m';
  }

  Widget _playlistsSection() {
    if (_loadingPlaylists) {
      return const SizedBox(
        height: 100,
        child: Center(
          child: CircularProgressIndicator(color: _cloveMint, strokeWidth: 2),
        ),
      );
    }
    if (_playlistsFailed) {
      return _emptyCard(
        'Could not load playlists',
        'Open your library to try again.',
        Icons.error_outline_rounded,
      );
    }
    final playlists = _playlists;
    if (playlists.isEmpty) {
      return _emptyCard(
        'Make this space yours',
        'Create a playlist in your library to see it here.',
        Icons.queue_music_rounded,
      );
    }

    return SizedBox(
      height: 224,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 2),
        itemCount: playlists.length > 10 ? 10 : playlists.length,
        separatorBuilder: (_, _) => const SizedBox(width: 13),
        itemBuilder: (context, index) {
          final item = playlists[index];
          final isPlaying = _isPlaylistPlaying(item);

          return SizedBox(
            width: 158,
            child: Material(
              color: const Color(0xFF19191D),
              borderRadius: BorderRadius.circular(22),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: () => _openPlaylist(item),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Layered artwork area.
                    Expanded(
                      child: Stack(
                        children: [
                          Positioned.fill(
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                  colors: [
                                    const Color(0xFF1DE9B6)
                                        .withValues(alpha: 0.18),
                                    const Color(0xFF28232F),
                                    const Color(0xFF19191D),
                                  ],
                                ),
                              ),
                            ),
                          ),

                          // Background artwork layers.
                          Positioned(
                            left: 23,
                            top: 15,
                            child: Transform.rotate(
                              angle: 0.12,
                              child: Opacity(
                                opacity: 0.42,
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(15),
                                  child: PlaylistArtwork(
                                    size: 120,
                                    artworkPath: item.playlist.artworkPath,
                                    borderRadius: 15,
                                  ),
                                ),
                              ),
                            ),
                          ),

                          Positioned(
                            left: 15,
                            top: 12,
                            child: Transform.rotate(
                              angle: -0.09,
                              child: Opacity(
                                opacity: 0.70,
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(15),
                                  child: PlaylistArtwork(
                                    size: 100,
                                    artworkPath: item.playlist.artworkPath,
                                    borderRadius: 15,
                                  ),
                                ),
                              ),
                            ),
                          ),

                          // Main artwork.
                          Positioned(
                            left: 20,
                            top: 17,
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(17),
                              child: PlaylistArtwork(
                                size: 114,
                                artworkPath: item.playlist.artworkPath,
                                borderRadius: 17,
                              ),
                            ),
                          ),

                          // Playlist count badge.
                          Positioned(
                            top: 10,
                            right: 10,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 5,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.62),
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(
                                  color: Colors.white.withValues(alpha: 0.10),
                                ),
                              ),
                              child: Text(
                                '${item.trackCount} tracks',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 9,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ),

                          // Floating play button.
                          Positioned(
                            right: 11,
                            bottom: 20,
                            child: Material(
                              color: const Color(0xFF1DE9B6),
                              shape: const CircleBorder(),
                              elevation: 5,
                              child: InkWell(
                                customBorder: const CircleBorder(),
                                onTap: () => _openPlaylist(item),
                                child: SizedBox(
                                        width: 39,
                                        height: 39,
                                        child: Center(
                                          child: isPlaying
                                              ? const PlayingEqualizer()
                                              : const Icon(
                                                  Icons.play_arrow_rounded,
                                                  color: _obsidian,
                                                  size: 28,
                                                ),
                                        ),
                                      ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    // Playlist details.
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 9, 12, 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            item.playlist.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: isPlaying ? _cloveMint : Colors.white,
                              fontSize: 13,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 4),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _sectionHeader(
    String title, {
    String? subtitle,
    String? action,
    VoidCallback? onAction,
  }) => Row(
    crossAxisAlignment: CrossAxisAlignment.end,
    children: [
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(
                color: _primaryText,
                fontSize: 19,
                fontWeight: FontWeight.w900,
              ),
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 3),
              Text(
                subtitle,
                style: const TextStyle(color: _secondaryText, fontSize: 10),
              ),
            ],
          ],
        ),
      ),
      if (action != null)
        TextButton(
          onPressed: onAction,
          style: TextButton.styleFrom(foregroundColor: _secondaryText),
          child: Text(action, style: const TextStyle(fontSize: 10)),
        ),
    ],
  );

  Widget _emptyCard(String title, String message, IconData icon) => Container(
    padding: const EdgeInsets.all(15),
    decoration: BoxDecoration(
      color: _cardSurface,
      borderRadius: BorderRadius.circular(14),
    ),
    child: Row(
      children: [
        Icon(icon, color: _cloveMint, size: 23),
        const SizedBox(width: 11),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: _primaryText,
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                message,
                style: const TextStyle(color: _secondaryText, fontSize: 10),
              ),
            ],
          ),
        ),
      ],
    ),
  );

  Widget _onlineArtwork(OnlineMusicTrack track, double size) => LocalArtwork(
    track: CloveTrack(
      path: track.sourcePage.toString(),
      mediaId: track.sourcePage.toString(),
      title: track.title,
      artist: track.artist ?? track.creatorName ?? 'Unknown artist',
      album: track.album ?? '',
      duration: track.duration ?? Duration.zero,
      artworkUri: track.artworkUri,
    ),
    size: size,
    borderRadius: 10,
  );

  Widget _mediaArtwork(MediaItem item, double size) => LocalArtwork(
    track: CloveTrack(
      path: item.id,
      mediaId: item.id,
      title: item.title,
      artist: item.artist ?? 'Unknown artist',
      album: item.album ?? '',
      duration: item.duration ?? Duration.zero,
      albumId: item.extras?['albumId'] as int?,
      artworkUri: item.artUri,
    ),
    size: size,
    borderRadius: 12,
  );
}

class _ArtistStepClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    final w = size.width;
    final h = size.height;

    // Equal steps on all four corners.
    final sx = w * 0.12;
    final sy = h * 0.12;

    return Path()
      // Top-left corner.
      ..moveTo(sx, 0)
      ..lineTo(w - sx, 0)
      // Top-right corner.
      ..lineTo(w - sx, sy)
      ..lineTo(w, sy)
      ..lineTo(w, h - sy)
      // Bottom-right corner.
      ..lineTo(w - sx, h - sy)
      ..lineTo(w - sx, h)
      // Bottom-left corner.
      ..lineTo(sx, h)
      ..lineTo(sx, h - sy)
      ..lineTo(0, h - sy)
      // Close the top-left corner.
      ..lineTo(0, sy)
      ..lineTo(sx, sy)
      ..close();
  }

  @override
  bool shouldReclip(covariant _ArtistStepClipper oldClipper) {
    return false;
  }
}

class _BottomArchClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    final w = size.width;
    final h = size.height;

    // Increase this value to make the arch shallower.
    const archDepth = 0.90;

    return Path()
      ..moveTo(w * 0.5, 0)
      // Smooth top-left and left side.
      ..cubicTo(w * 0.22, 0, 0, h * 0.18, 0, h * 0.46)
      ..lineTo(0, h * 0.68)
      // Smooth lower-left corner.
      ..cubicTo(0, h * 0.88, w * 0.12, h, w * 0.25, h)
      // Wider, shallow arch.
      ..cubicTo(w * 0.36, h, w * 0.36, h * archDepth, w * 0.50, h * archDepth)
      ..cubicTo(w * 0.64, h * archDepth, w * 0.64, h, w * 0.75, h)
      // Smooth lower-right corner.
      ..cubicTo(w * 0.88, h, w, h * 0.88, w, h * 0.68)
      ..lineTo(w, h * 0.46)
      // Smooth right side and top-right corner.
      ..cubicTo(w, h * 0.18, w * 0.78, 0, w * 0.5, 0)
      ..close();
  }

  @override
  bool shouldReclip(covariant _BottomArchClipper oldClipper) => false;
}

class PlayingEqualizer extends StatefulWidget {
  const PlayingEqualizer({super.key});

  @override
  State<PlayingEqualizer> createState() => _PlayingEqualizerState();
}

class _PlayingEqualizerState extends State<PlayingEqualizer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  // Change this to 1 or 2 to try another style.
  static const int style = 3;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 650),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<bool>(
      stream: PlaybackService.isPlayingStream,
      initialData: PlaybackService.isPlaying,
      builder: (context, snapshot) {
        final isPlaying = snapshot.data ?? false;

        if (isPlaying && !_controller.isAnimating) {
          _controller.repeat();
        } else if (!isPlaying && _controller.isAnimating) {
          _controller.stop();
        }

        final heights = switch (style) {
          1 => [18.0, 12.0, 18.0],
          2 => [10.0, 16.0, 22.0, 16.0, 10.0],
          _ => [12.0, 22.0, 16.0, 28.0, 19.0],
        };

        return SizedBox(
          width: style == 1 ? 12 : 16,
          height: 16,
          child: AnimatedBuilder(
            animation: _controller,
            builder: (context, child) {
              return Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: List.generate(heights.length, (index) {
                  final phase = (_controller.value + index * 0.19) % 1.0;
                  final wave = (0.5 + 0.5 * math.sin(phase * 2 * math.pi))
                      .clamp(0.0, 1.0);
                  final height = 5.0 + wave * (heights[index] - 5.0);

                  return Container(
                    width: 2,
                    height: height.clamp(3.0, 16.0),
                    decoration: BoxDecoration(
                      color: _obsidian,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  );
                }),
              );
            },
          ),
        );
      },
    );
  }
}
