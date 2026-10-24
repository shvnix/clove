import 'package:flutter/material.dart';

const Color _obsidian = Color(0xFF0B0B0B);
const Color _inputSurface = Color(0xFF202020);
const Color _cardSurface = Color(0xFF1C1C20);
const Color _cloveMint = Color(0xFF1DE9B6);
const Color _primaryText = Color(0xFFFFFFFF);
const Color _secondaryText = Color(0xFFB7B5BE);

class HomeScreen extends StatefulWidget {
  final String username;
  final VoidCallback onOpenProfile;

  const HomeScreen({
    super.key,
    required this.username,
    required this.onOpenProfile,
  });

@override
HomeScreenState createState() => HomeScreenState();
}

class HomeScreenState extends State<HomeScreen> {
  void openProfile() {
    widget.onOpenProfile();
  }

  @override
  Widget build(BuildContext context) {
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
    );
  }
}
