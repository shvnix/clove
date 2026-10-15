import 'package:flutter/material.dart';

const Color _obsidian = Color(0xFF0B0B0B);
const Color _inputSurface = Color(0xFF202020);
const Color _cardSurface = Color(0xFF1C1C20);
const Color _cloveMint = Color(0xFF1DE9B6);
const Color _primaryText = Color(0xFFFFFFFF);
const Color _secondaryText = Color(0xFFB7B5BE);

class LunaScreen extends StatefulWidget {
  final String username;

  const LunaScreen({super.key, required this.username});

  @override
  State<LunaScreen> createState() => _LunaScreenState();
}

class _LunaScreenState extends State<LunaScreen> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _obsidian,
      appBar: AppBar(
        backgroundColor: _obsidian,
        elevation: 0,
        scrolledUnderElevation: 0,
        automaticallyImplyLeading: false,
        titleSpacing: 10,

        title: Row(
          children: [
            Padding(padding: EdgeInsets.all(4)),
            Container(
              width: 34,
              height: 34,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: _cloveMint,
                shape: BoxShape.circle,
              ),
              child: Text(
                widget.username.trim().isNotEmpty
                    ? widget.username.trim()[0].toUpperCase()
                    : '?',
                style: const TextStyle(
                  color: _obsidian,
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            const SizedBox(width: 14),

            Text(
              'Luna AI',
              style: const TextStyle(
                color: _primaryText,
                fontSize: 22,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
