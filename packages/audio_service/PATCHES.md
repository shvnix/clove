# Clove patch

This local fork is based on `audio_service` 0.18.19.

- A pause releases the audio wake lock immediately but keeps the Android media
  playback foreground service for a 30 second handoff window. Resuming during
  an audio-focus interruption cancels the pending foreground teardown. This
  prevents Android 17 from treating the resumed playback as background audio
  without a foreground service.

The normal foreground teardown still happens after the grace window, and a
resume after teardown starts the service again through the existing playback
path. Keep this fork until upstream supports a transient-pause grace period.
