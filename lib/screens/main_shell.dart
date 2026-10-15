import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'library_screen.dart';
import 'home_screen.dart';
import 'luna_screen.dart';
import 'search_screen.dart';

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

  late final List<Widget> _screens;

  @override
  void initState() {
    super.initState();

    _screens = [
      HomeScreen(username: widget.username),
      LibraryScreen(username: widget.username),
      LunaScreen(username: widget.username),
    ];
  }

  void _selectTab(int index) {
    if (_selectedTab == index) return;

    setState(() {
      _selectedTab = index;
    });
  }

  void _openSearch() {
  Navigator.push(
    context,
    PageRouteBuilder(
      pageBuilder: (context, animation, secondaryAnimation) =>
          const SearchScreen(),

      transitionsBuilder:
          (context, animation, secondaryAnimation, child) {
        const begin = Offset(0.0, 1.0);
        const end = Offset.zero;
        const curve = Curves.easeOutCubic;

        final tween = Tween(
          begin: begin,
          end: end,
        ).chain(
          CurveTween(curve: curve),
        );

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
    canPop: _selectedTab == 0,
    onPopInvokedWithResult: (didPop, result) {
      if (didPop) return;

      if (_selectedTab != 0) {
        setState(() {
          _selectedTab = 0;
        });
      }
    },
    child: Scaffold(
      backgroundColor: _obsidian,
      extendBody: true,
      body: Stack(
        children: [
          IndexedStack(
            index: _selectedTab,
            children: _screens,
          ),
          _buildBottomNavigation(),
        ],
      ),
    ),
  );
}


  // BOTTOM NAVIGATION

  Widget _buildBottomNavigation() {
    return Positioned(
      left: 20,
      right: 20,
      bottom: 6,
      child: SafeArea(
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
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.25),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.3),
                      blurRadius: 24,
                      offset: const Offset(0, 8),
                    ),
                  ],
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
