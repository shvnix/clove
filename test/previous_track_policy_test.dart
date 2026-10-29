import 'package:clove/services/audio/previous_track_policy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('previous after more than three seconds restarts current track', () {
    expect(
      decidePreviousTrackAction(
        hasCurrentTrack: true,
        hasPreviousTrack: true,
        position: const Duration(seconds: 45),
        currentTrackWasRestartedByPrevious: false,
      ),
      PreviousTrackAction.restartCurrent,
    );
  });

  test('previous near the beginning selects the prior queue item', () {
    expect(
      decidePreviousTrackAction(
        hasCurrentTrack: true,
        hasPreviousTrack: true,
        position: const Duration(seconds: 2),
        currentTrackWasRestartedByPrevious: false,
      ),
      PreviousTrackAction.previousTrack,
    );
  });

  test('previous after a previous-command restart selects prior item', () {
    expect(
      decidePreviousTrackAction(
        hasCurrentTrack: true,
        hasPreviousTrack: true,
        position: const Duration(seconds: 10),
        currentTrackWasRestartedByPrevious: true,
      ),
      PreviousTrackAction.previousTrack,
    );
  });

  test('previous at the first queue item safely restarts current track', () {
    expect(
      decidePreviousTrackAction(
        hasCurrentTrack: true,
        hasPreviousTrack: false,
        position: const Duration(seconds: 1),
        currentTrackWasRestartedByPrevious: false,
      ),
      PreviousTrackAction.restartCurrent,
    );
  });

  test('previous with no current track is a no-op', () {
    expect(
      decidePreviousTrackAction(
        hasCurrentTrack: false,
        hasPreviousTrack: false,
        position: Duration.zero,
        currentTrackWasRestartedByPrevious: false,
      ),
      PreviousTrackAction.none,
    );
  });
}
