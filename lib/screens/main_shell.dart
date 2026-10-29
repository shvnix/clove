import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import 'library_screen.dart';
import 'home_screen.dart';
import 'luna_screen.dart';
import 'search_screen.dart';
import '../services/audio/playback_service.dart';
import '../widgets/clove_mini_player.dart';
import '../data/database.dart';
import '../services/playlist_repository.dart';
import '../services/online_music_provider_scope.dart';
import '../services/clove_notifications.dart';
import '../services/rhythm_guard_service.dart';
import 'login_screen.dart';

const Color _obsidian = Color(0xFF0B0B0B);
const Color _cloveMint = Color(0xFF1DE9B6);

class MainShell extends StatefulWidget {
  final String username;

  const MainShell({super.key, required this.username});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _selectedTab = 0;
  late String _username;
  Animation<double>? _libraryProfileAnimation;
  late final PlaylistRepository _playlistRepository;
  final GlobalKey<LibraryScreenState> _libraryKey =
      GlobalKey<LibraryScreenState>();
  final GlobalKey<HomeScreenState> _homeKey = GlobalKey<HomeScreenState>();

  late List<Widget> _screens;

  @override
  void initState() {
    super.initState();
    _username = widget.username;
    _playlistRepository = PlaylistRepository(AppDatabase.instance);
    _screens = _createScreens();
    unawaited(RhythmGuardService.instance.start());
  }

  List<Widget> _createScreens() => [
    HomeScreen(
      key: _homeKey,
      username: _username,
      onOpenProfile: _openProfile,
      onOpenSearch: _openSearch,
      onOpenSearchQuery: (query) => _openSearch(initialQuery: query),
      onOpenLibrary: () => _selectTab(1),
      onOpenPlaylist: _openHomePlaylist,
      isActive: _selectedTab == 0,
    ),
    LibraryScreen(
      key: _libraryKey,
      username: _username,
      onSaveUsername: _saveUsername,
      onDeleteAccount: _deleteAccount,
      onProfileTransitionChanged: (animation) {
        if (!mounted) return;
        setState(() => _libraryProfileAnimation = animation);
      },
    ),
    LunaScreen(username: _username, onOpenProfile: _openProfile),
  ];

  Future<void> _saveUsername(String name) async {
    final normalized = name.trim();
    await AppDatabase.instance.saveProfile(normalized);
    if (!mounted) return;
    setState(() {
      _username = normalized;
      _screens = _createScreens();
    });
  }

  Future<void> _deleteAccount() async {
    if (PlaybackService.isInitialized) await PlaybackService.stop();
    await AppDatabase.instance.deleteLocalAccount();
    if (!mounted) return;

    await _libraryKey.currentState?.closeProfileForAccountDeletion();
    if (!mounted) return;

    Navigator.of(context, rootNavigator: true).pushAndRemoveUntil<void>(
      MaterialPageRoute<void>(
        builder: (_) => CloveLoginScreen(database: AppDatabase.instance),
      ),
      (_) => false,
    );
  }

  void _selectTab(int index) {
    if (index == 1) {
      _libraryKey.currentState?.showLibraryHome();
    }
    if (_selectedTab == index) return;

    setState(() {
      _selectedTab = index;
    });
  }

  void _openHomePlaylist(int playlistId) {
    _selectTab(1);
    _libraryKey.currentState?.openPlaylist(playlistId);
  }

  Future<void> _openSearch({String? initialQuery}) async {
    await Navigator.push<void>(
      context,
      PageRouteBuilder<void>(
        pageBuilder: (context, animation, secondaryAnimation) => SearchScreen(
          provider: OnlineMusicProviderScope.of(context),
          initialQuery: initialQuery,
        ),

        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          const begin = Offset(0.0, 1.0);
          const end = Offset.zero;
          const curve = Curves.easeOutCubic;

          final tween = Tween(
            begin: begin,
            end: end,
          ).chain(CurveTween(curve: curve));

          return SlideTransition(
            position: animation.drive(tween),
            child: child,
          );
        },

        transitionDuration: const Duration(milliseconds: 200),
        reverseTransitionDuration: const Duration(milliseconds: 150),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop:
          _selectedTab == 0 &&
          !(_libraryKey.currentState?.canPopProfile ?? false),
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;

        final library = _libraryKey.currentState;
        if (_selectedTab == 1 && (library?.canPopDestination ?? false)) {
          library?.popDestination();
          return;
        }
        if (library?.canPopProfile ?? false) {
          library?.popProfile();
          return;
        }
        if (_selectedTab != 0) {
          setState(() {
            _selectedTab = 0;
          });
        }
      },
      child: Scaffold(
        backgroundColor: _obsidian,
        extendBody: true,
        body: Stack(children: [_buildTabScreens(), _buildShellControls()]),
      ),
    );
  }

  Widget _buildTabScreens() {
    final animation =
        _libraryProfileAnimation ?? const AlwaysStoppedAnimation<double>(0);

    return AnimatedBuilder(
      animation: animation,
      child: IndexedStack(index: _selectedTab, children: _screens),
      builder: (context, child) {
        final width = MediaQuery.sizeOf(context).width;
        final progress = _libraryProfileAnimation?.value ?? 0.0;
        final pageMovesInsideLibrary = _selectedTab == 1;

        return Transform.translate(
          offset: Offset(
            pageMovesInsideLibrary ? 0 : width * 0.88 * progress,
            0,
          ),
          child: child,
        );
      },
    );
  }

  Widget _buildShellControls() {
    final animation = _libraryProfileAnimation;

    return AnimatedBuilder(
      animation: animation ?? const AlwaysStoppedAnimation<double>(0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: CloveMiniPlayer(
              playlistRepository: _playlistRepository,
              notificationAnchor: true,
            ),
          ),
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.only(left: 18, right: 18, bottom: 6),
            child: _buildBottomNavigation(),
          ),
        ],
      ),
      builder: (context, child) {
        final progress = animation?.value ?? 0.0;

        final screenWidth = MediaQuery.sizeOf(context).width;

        final widthFactor =
            _libraryKey.currentState?.profileTransitionWidthFactor ?? 0.88;

        return Positioned.fill(
          child: Transform.translate(
            offset: Offset(screenWidth * widthFactor * progress, 0),
            child: Stack(
              fit: StackFit.expand,
              children: [
                child!,

                // Preserve the existing fade while the profile is opening.
                Positioned.fill(
                  child: IgnorePointer(
                    child: ColoredBox(
                      color: Colors.black.withValues(alpha: progress * 0.75),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _openProfile() {
    final library = _libraryKey.currentState;
    if (library == null) return;

    if (library.canPopProfile) return;

    library.openProfile();
  }

  // BOTTOM NAVIGATION

  Widget _buildBottomNavigation() {
    return SafeArea(
      key: CloveNotifications.navigationAnchorKey,
      top: false,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Main navigation pill
          Expanded(
            child: Container(
              height: 68,
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: _obsidian,
                borderRadius: BorderRadius.circular(50),
                border: Border.all(color: Colors.white.withValues(alpha: 0.25)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: _navItem(
                      index: 0,
                      svgPath: 'assets/icon/home.svg',
                      label: 'Home',
                    ),
                  ),
                  Expanded(
                    child: _navItem(
                      index: 1,
                      icon: Icons.library_music_rounded,
                      label: 'Library',
                    ),
                  ),
                  Expanded(
                    child: _navItem(
                      index: 2,
                      svgPath: 'assets/icon/moon.svg',
                      label: 'Luna',
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(width: 8),

          Material(
            color: _obsidian,
            shape: const CircleBorder(),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: _openSearch,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOut,
                width: 68,
                height: 68,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.25),
                  ),
                ),
                child: Center(
                  child: SvgPicture.asset(
                    'assets/icon/search.svg',
                    width: 22,
                    height: 22,
                    colorFilter: const ColorFilter.mode(
                      Color(0xFF8E8D95),
                      BlendMode.srcIn,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _navItem({
    required int index,
    IconData? icon,
    String? svgPath,
    required String label,
  }) {
    final bool selected = _selectedTab == index;

    final Color iconColor = selected ? _obsidian : const Color(0xFF8E8D95);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeInOutCubic,
      height: double.infinity,
      padding: EdgeInsets.symmetric(
        horizontal: selected ? 0 : 4,
        vertical: selected ? 0 : 4,
      ),
      decoration: BoxDecoration(
        color: selected ? _cloveMint : Colors.transparent,
        borderRadius: BorderRadius.circular(50),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          splashColor: Colors.transparent,
          highlightColor: Colors.transparent,
          hoverColor: Colors.transparent,
          focusColor: Colors.transparent,
          borderRadius: BorderRadius.circular(50),
          onTap: () => _selectTab(index),
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: selected ? 8 : 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (svgPath != null)
                  SvgPicture.asset(
                    svgPath,
                    width: 25,
                    height: 25,
                    colorFilter: ColorFilter.mode(iconColor, BlendMode.srcIn),
                  )
                else if (icon != null)
                  Icon(icon, color: iconColor, size: 25),

                if (selected) ...[
                  const SizedBox(width: 2),
                  Flexible(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: _obsidian,
                        fontSize: 11,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
