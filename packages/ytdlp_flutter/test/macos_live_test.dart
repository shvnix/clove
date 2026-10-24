import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ytdlp_flutter/ytdlp_flutter.dart';

/// Live smoke test for the macOS backend. Needs network: downloads the
/// official yt-dlp binary (~35 MB, cached across runs) and then a real
/// 32 MB video's audio. Skipped unless opted in:
///
///   LIVE=1 flutter test test/macos_live_test.dart
///
/// The video is 0wemf5SZkW4 (32 MB) deliberately: it is the regression case
/// that defeated youtube_explode (n-throttle serving 0 bytes, 403 past
/// 1 MB). Anything that only proves itself on a sub-1MB video proves
/// nothing.
void main() {
  test('macOS: info + full audio download of the 32MB regression video',
      () async {
    // Cache the binary outside the temp workdir so repeat runs are fast.
    final cache = Directory(
        '${Directory.systemTemp.path}/ytdlp_flutter_test_cache');
    final backend = YtdlpMacos(cacheDirOverride: cache.path);
    YtdlpPlatform.instance = backend;

    await Ytdlp.init();

    const url = 'https://www.youtube.com/watch?v=0wemf5SZkW4';
    final info = await Ytdlp.getVideoInfo(url);
    // ignore: avoid_print
    print('info: $info');
    expect(info.id, '0wemf5SZkW4');
    expect(info.title, isNotEmpty);

    final outDir =
        Directory.systemTemp.createTempSync('ytdlp_flutter_dl').path;
    var progressReports = 0;
    int? lastDownloaded;
    final path = await Ytdlp.downloadAudio(
      url: url,
      outputDir: outDir,
      taskId: 'live-test',
      onProgress: (p) {
        progressReports++;
        lastDownloaded = p.downloadedBytes ?? lastDownloaded;
      },
    );
    final size = File(path).lengthSync();
    // ignore: avoid_print
    print('downloaded $path ($size bytes, $progressReports progress reports)');

    // Must be well past the 1 MB cap that broke youtube_explode.
    expect(size, greaterThan(2 * 1024 * 1024));
    expect(progressReports, greaterThan(0));

    Directory(outDir).deleteSync(recursive: true);
  },
      timeout: const Timeout(Duration(minutes: 10)),
      skip: Platform.environment['LIVE'] != '1'
          ? 'live test — run with LIVE=1'
          : false);
}
