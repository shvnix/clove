/// The action to take when the user requests the previous track.
enum PreviousTrackAction { none, restartCurrent, previousTrack }

/// Spotify-style Previous behavior uses a three-second restart threshold.
const previousTrackRestartThreshold = Duration(seconds: 3);

PreviousTrackAction decidePreviousTrackAction({
  required bool hasCurrentTrack,
  required bool hasPreviousTrack,
  required Duration position,
  required bool currentTrackWasRestartedByPrevious,
}) {
  if (!hasCurrentTrack) return PreviousTrackAction.none;

  if (currentTrackWasRestartedByPrevious) {
    return hasPreviousTrack
        ? PreviousTrackAction.previousTrack
        : PreviousTrackAction.restartCurrent;
  }

  if (position > previousTrackRestartThreshold) {
    return PreviousTrackAction.restartCurrent;
  }

  return hasPreviousTrack
      ? PreviousTrackAction.previousTrack
      : PreviousTrackAction.restartCurrent;
}
