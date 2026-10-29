import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:on_audio_query_pluse/on_audio_query.dart';
import 'package:permission_handler/permission_handler.dart';

import '../models/clove_track.dart';

/// Permission-handler's Android mapping follows the OS media permission split.
Permission androidAudioPermissionForSdk(int sdkInt) =>
    sdkInt >= 33 ? Permission.audio : Permission.storage;

class LocalAudioScanResult {
  const LocalAudioScanResult({
    required this.tracks,
    required this.permissionStatus,
    this.error,
  });

  final List<CloveTrack> tracks;
  final PermissionStatus? permissionStatus;
  final Object? error;

  bool get hasPermission => permissionStatus?.isGranted ?? false;
}

/// Shared permission and MediaStore scan path for the Library and Local Music
/// screens. permission_handler is the single runtime permission authority.
class LocalAudioLibrary {
  LocalAudioLibrary({OnAudioQuery? audioQuery, DeviceInfoPlugin? deviceInfo})
    : _audioQuery = audioQuery ?? OnAudioQuery(),
      _deviceInfo = deviceInfo ?? DeviceInfoPlugin();

  final OnAudioQuery _audioQuery;
  final DeviceInfoPlugin _deviceInfo;

  Future<LocalAudioScanResult> scan({bool requestPermission = true}) async {
    try {
      final permission = Platform.isAndroid
          ? androidAudioPermissionForSdk(
              (await _deviceInfo.androidInfo).version.sdkInt,
            )
          : Permission.audio;
      var status = await permission.status;
      if (!status.isGranted && requestPermission) {
        status = await permission.request();
      }
      debugPrint('CLOVE: Local audio permission status: $status');
      if (!status.isGranted) {
        return LocalAudioScanResult(tracks: const [], permissionStatus: status);
      }
      final songs = await _audioQuery.querySongs();
      final tracks = mapSongModelsToTracks(songs);
      debugPrint('CLOVE: Local audio query returned ${tracks.length} tracks.');
      return LocalAudioScanResult(tracks: tracks, permissionStatus: status);
    } catch (error, stackTrace) {
      debugPrint('CLOVE: Local audio scan failed: $error');
      debugPrintStack(stackTrace: stackTrace);
      return LocalAudioScanResult(
        tracks: const [],
        permissionStatus: null,
        error: error,
      );
    }
  }
}

List<CloveTrack> mapSongModelsToTracks(Iterable<SongModel> songs) {
  final tracks = <CloveTrack>[];

  for (final song in songs) {
    final path = (song.uri ?? '').trim().isNotEmpty
        ? song.uri!.trim()
        : song.data.trim();
    if (path.isEmpty) continue;

    final title = song.title.trim();
    final artist = (song.artist ?? '').trim();
    final album = (song.album ?? '').trim();
    tracks.add(
      CloveTrack(
        path: path,
        title: title.isEmpty ? 'Unknown title' : title,
        artist: artist.isEmpty ? 'Unknown artist' : artist,
        album: album,
        duration: Duration(milliseconds: song.duration ?? 0),
        albumId: song.albumId,
        dateAdded: song.dateAdded == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch(song.dateAdded! * 1000),
      ),
    );
  }

  tracks.sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
  return tracks;
}
