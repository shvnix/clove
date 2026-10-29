import 'package:audio_service/audio_service.dart';

String formatPlaybackTime(Duration duration) {
  final seconds = duration.inSeconds.clamp(0, 1 << 30);
  final minutes = seconds ~/ 60;
  final remainder = seconds % 60;
  return '$minutes:${remainder.toString().padLeft(2, '0')}';
}

Duration resolvePlaybackDuration(Duration? playerDuration, Duration? metadata) {
  if (playerDuration != null && playerDuration > Duration.zero) {
    return playerDuration;
  }
  if (metadata != null && metadata > Duration.zero) return metadata;
  return Duration.zero;
}

AudioServiceRepeatMode nextRepeatMode(AudioServiceRepeatMode mode) =>
    switch (mode) {
      AudioServiceRepeatMode.none => AudioServiceRepeatMode.all,
      AudioServiceRepeatMode.all => AudioServiceRepeatMode.one,
      _ => AudioServiceRepeatMode.none,
    };

bool isQueueIndexValid(int index, int queueLength) =>
    index >= 0 && index < queueLength;
