import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:ytdlp_flutter/ytdlp_flutter.dart';

void main() {
  runApp(const MaterialApp(home: DemoPage()));
}

class DemoPage extends StatefulWidget {
  const DemoPage({super.key});

  @override
  State<DemoPage> createState() => _DemoPageState();
}

class _DemoPageState extends State<DemoPage> {
  final _urlController = TextEditingController(
      text: 'https://www.youtube.com/watch?v=0wemf5SZkW4');
  String _status = 'idle';
  double? _fraction;
  static const _taskId = 'example-download';

  Future<void> _run(Future<void> Function() body) async {
    try {
      await body();
    } catch (e) {
      setState(() => _status = 'error: $e');
    }
  }

  Future<void> _getInfo() => _run(() async {
        setState(() => _status = 'fetching info…');
        await Ytdlp.init();
        final info = await Ytdlp.getVideoInfo(_urlController.text.trim());
        setState(() => _status =
            '${info.title}\n${info.durationSeconds ?? '?'}s by ${info.uploader ?? '?'}');
      });

  Future<void> _download() => _run(() async {
        setState(() {
          _status = 'downloading…';
          _fraction = null;
        });
        await Ytdlp.init();
        final dir = await getApplicationDocumentsDirectory();
        final path = await Ytdlp.downloadAudio(
          url: _urlController.text.trim(),
          outputDir: '${dir.path}/ytdlp_example',
          taskId: _taskId,
          onProgress: (p) => setState(() => _fraction = p.fraction),
        );
        setState(() => _status = 'done: $path');
      });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('ytdlp_flutter example')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _urlController,
              decoration: const InputDecoration(labelText: 'Video URL'),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                ElevatedButton(onPressed: _getInfo, child: const Text('Info')),
                ElevatedButton(
                    onPressed: _download, child: const Text('Download audio')),
                ElevatedButton(
                    onPressed: () => Ytdlp.cancel(_taskId),
                    child: const Text('Cancel')),
              ],
            ),
            const SizedBox(height: 16),
            if (_fraction != null) LinearProgressIndicator(value: _fraction),
            const SizedBox(height: 16),
            Text(_status),
          ],
        ),
      ),
    );
  }
}
