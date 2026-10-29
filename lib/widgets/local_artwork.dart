import 'dart:collection';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:on_audio_query_pluse/on_audio_query.dart';

import '../models/clove_track.dart';

/// Loads each album's artwork once and keeps a bounded set of encoded images.
class LocalArtworkCache {
  LocalArtworkCache._();

  static final LocalArtworkCache instance = LocalArtworkCache._();
  final OnAudioQuery _query = OnAudioQuery();
  final LinkedHashMap<int, Future<Uint8List?>> _images =
      LinkedHashMap<int, Future<Uint8List?>>();

  Future<Uint8List?> load(int albumId) {
    final cached = _images.remove(albumId);
    if (cached != null) {
      _images[albumId] = cached;
      return cached;
    }

    final future = _query
        .queryArtwork(albumId, ArtworkType.ALBUM, size: 512, quality: 85)
        .then((bytes) {
          debugPrint(
            'CLOVE: Artwork ${bytes == null ? 'missing' : 'loaded'} for album $albumId.',
          );
          return bytes;
        })
        .catchError((Object error) {
          debugPrint('CLOVE: Artwork lookup failed for album $albumId: $error');
          return null;
        });
    _images[albumId] = future;
    if (_images.length > 64) _images.remove(_images.keys.first);
    return future;
  }
}

class LocalArtwork extends StatelessWidget {
  const LocalArtwork({
    super.key,
    required this.track,
    required this.size,
    this.borderRadius = 14,
    this.iconSize,
    this.elevation = false,
  });

  final CloveTrack track;
  final double size;
  final double borderRadius;
  final double? iconSize;
  final bool elevation;

  @override
  Widget build(BuildContext context) {
    final albumId = track.albumId;
    final fallback = _fallback();
    if (albumId == null || albumId < 0) {
      final artworkUri = track.artworkUri;
      if (artworkUri == null ||
          (artworkUri.scheme != 'file' &&
              (!{'http', 'https'}.contains(artworkUri.scheme) ||
                  artworkUri.host.isEmpty))) {
        return fallback;
      }

      if (artworkUri.scheme == 'file') {
        return _frame(
          Transform.scale(
            scale: 1.4,
            child: Image.file(
              File.fromUri(artworkUri),
              width: size,
              height: size,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => fallback,
            ),
          ),
        );
      }

      return _frame(
        Transform.scale(
          scale: 1.4,
          child: Image.network(
            artworkUri.toString(),
            width: size,
            height: size,
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) => fallback,
          ),
        ),
      );
    }

    return FutureBuilder<Uint8List?>(
      future: LocalArtworkCache.instance.load(albumId),
      builder: (context, snapshot) {
        final bytes = snapshot.data;
        if (bytes == null || bytes.isEmpty) return fallback;
        return _frame(
          Image.memory(
            bytes,
            width: size,
            height: size,
            fit: BoxFit.cover,
            cacheWidth: (size * MediaQuery.devicePixelRatioOf(context)).round(),
            cacheHeight: (size * MediaQuery.devicePixelRatioOf(context))
                .round(),
            errorBuilder: (_, _, _) => fallback,
          ),
        );
      },
    );
  }

  Widget _fallback() => _frame(
    DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF252B2A), Color(0xFF121615)],
        ),
      ),
      child: Center(
        child: Icon(
          Icons.graphic_eq_rounded,
          size: iconSize ?? size * 0.42,
          color: const Color(0xFF1DE9B6),
        ),
      ),
    ),
  );

  Widget _frame(Widget child) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(borderRadius),
      boxShadow: elevation
          ? [
              BoxShadow(
                color: const Color(0xFF000000).withValues(alpha: 0.45),
                blurRadius: 12,
                spreadRadius: 1,
                offset: const Offset(0, 8),
              ),
            ]
          : null,
    ),
    child: ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: child,
    ),
  );
}
