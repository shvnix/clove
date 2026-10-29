import 'package:audio_service/audio_service.dart';
import 'package:clove/services/audio/audio_handler.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'audio_service previous media button dispatches only Previous',
    () async {
      final handler = _DispatchProbe();

      await handler.click(MediaButton.previous);

      expect(handler.previousCommands, 1);
      expect(handler.nextCommands, 0);
    },
  );

  test('audio_service next media button dispatches only Next', () async {
    final handler = _DispatchProbe();

    await handler.click(MediaButton.next);

    expect(handler.previousCommands, 0);
    expect(handler.nextCommands, 1);
  });
}

class _DispatchProbe extends CloveAudioHandler {
  int previousCommands = 0;
  int nextCommands = 0;

  @override
  Future<void> skipToPrevious() async {
    previousCommands++;
  }

  @override
  Future<void> skipToNext() async {
    nextCommands++;
  }
}
