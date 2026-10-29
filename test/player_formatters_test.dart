import 'package:clove/services/audio/player_formatters.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('uses the live player duration when track metadata is missing', () {
    expect(
      resolvePlaybackDuration(const Duration(minutes: 3), Duration.zero),
      const Duration(minutes: 3),
    );
  });

  test('uses metadata duration until the player reports one', () {
    expect(
      resolvePlaybackDuration(null, const Duration(minutes: 4)),
      const Duration(minutes: 4),
    );
  });

  test('reports unknown duration only when both values are unavailable', () {
    expect(resolvePlaybackDuration(null, Duration.zero), Duration.zero);
  });
}
