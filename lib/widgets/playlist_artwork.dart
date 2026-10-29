import 'dart:io';

import 'package:flutter/material.dart';

import '../models/clove_track.dart';
import 'local_artwork.dart';

class PlaylistArtwork extends StatelessWidget {
  const PlaylistArtwork({
    super.key,
    required this.size,
    this.artworkPath,
    this.track,
    this.likedSongs = false,
    this.borderRadius = 12,
  });

  final double size;
  final String? artworkPath;
  final CloveTrack? track;
  final bool likedSongs;
  final double borderRadius;

  @override
  Widget build(BuildContext context) {
    if (track != null) {
      return LocalArtwork(
        track: track!,
        size: size,
        borderRadius: borderRadius,
        iconSize: size * 0.4,
      );
    }
    final path = artworkPath;
    final fallback = _fallback();
    if (path == null || path.isEmpty) return fallback;
    return _frame(
      Image.file(
        File(path),
        width: size,
        height: size,
        fit: BoxFit.cover,
        cacheWidth: (size * MediaQuery.devicePixelRatioOf(context)).round(),
        cacheHeight: (size * MediaQuery.devicePixelRatioOf(context)).round(),
        errorBuilder: (_, _, _) => fallback,
      ),
    );
  }

  Widget _fallback() => _frame(
    DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: likedSongs
              ? const [Color(0xFF7C4DCC), Color(0xFFDCCBFF)]
              : const [Color(0xFF1C1C20), Color(0xFF38383F)],
        ),
      ),
      child: Center(
        child: Icon(
          likedSongs ? Icons.favorite_rounded : Icons.queue_music_rounded,
          size: size * 0.42,
          color: Colors.white,
        ),
      ),
    ),
  );

  Widget _frame(Widget child) => ClipRRect(
    borderRadius: BorderRadius.circular(borderRadius),
    child: SizedBox(width: size, height: size, child: child),
  );
}
