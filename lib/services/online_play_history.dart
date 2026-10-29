import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../models/online_music_track.dart';

/// Keeps stable provider IDs for every online track played on this device.
/// Recommendation discovery uses this set to avoid re-adding played tracks.
class OnlinePlayHistory {
  static const _fileName = 'online_played_track_ids.json';
  static Future<void> _writeTail = Future<void>.value();

  Future<Set<String>> loadPlayedIds() async {
    await _writeTail;
    return _readPlayedIds();
  }

  Future<Set<String>> _readPlayedIds() async {
    try {
      final file = await _file();
      if (!await file.exists()) return <String>{};
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! List) return <String>{};
      return decoded.whereType<String>().map((id) => id.toLowerCase()).toSet();
    } on FormatException {
      return <String>{};
    } on FileSystemException {
      return <String>{};
    }
  }

  Future<void> record(OnlineMusicTrack track) {
    final write = _writeTail.then((_) async {
      final playedIds = await _readPlayedIds();
      playedIds.add('${track.providerId}:${track.id}'.toLowerCase());
      final file = await _file();
      await file.writeAsString(jsonEncode(playedIds.toList()), flush: true);
    });
    _writeTail = write.then<void>((_) {}).catchError((Object _) {});
    return write;
  }

  Future<File> _file() async {
    final directory = await getApplicationSupportDirectory();
    return File('${directory.path}/$_fileName');
  }
}
