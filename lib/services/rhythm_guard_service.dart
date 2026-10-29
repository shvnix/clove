import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'audio/playback_service.dart';

/// Persisted daily listening usage and the user's daily listening limit.
///
/// Usage advances from actual player-position movement while the player is
/// ready and playing. Pauses, buffering, seeks, and track changes do not count
/// as listening time.
class RhythmGuardSnapshot {
  const RhythmGuardSnapshot({
    required this.dayKey,
    required this.listenedMilliseconds,
    required this.dailyLimitMinutes,
  });

  final String dayKey;
  final int listenedMilliseconds;
  final int dailyLimitMinutes;

  Duration get listened => Duration(milliseconds: listenedMilliseconds);
  Duration get limit => Duration(minutes: dailyLimitMinutes);
  Duration get remaining => Duration(
    milliseconds: (limit.inMilliseconds - listenedMilliseconds).clamp(
      0,
      limit.inMilliseconds,
    ),
  );

  double get progress =>
      (listenedMilliseconds / limit.inMilliseconds).clamp(0.0, 1.0);

  bool get limitReached => listenedMilliseconds >= limit.inMilliseconds;
  bool get warning => !limitReached && progress >= 0.9;
}

class RhythmGuardService {
  RhythmGuardService._();

  static final RhythmGuardService instance = RhythmGuardService._();
  static const int defaultDailyLimitMinutes = 95;
  static const int _minimumLimitMinutes = 1;
  static const int _maximumLimitMinutes = 24 * 60;
  static const String _fileName = 'rhythm_guard_daily_usage.json';

  final StreamController<RhythmGuardSnapshot> _snapshots =
      StreamController<RhythmGuardSnapshot>.broadcast();
  StreamSubscription<MediaItem?>? _mediaSubscription;
  StreamSubscription<PlaybackState>? _stateSubscription;
  StreamSubscription<Duration>? _positionSubscription;
  Future<void>? _startFuture;
  Future<void> _writeTail = Future<void>.value();
  RhythmGuardSnapshot _snapshot = RhythmGuardSnapshot(
    dayKey: _todayKey(),
    listenedMilliseconds: 0,
    dailyLimitMinutes: defaultDailyLimitMinutes,
  );
  DateTime? _lastPositionAt;
  Duration? _lastPosition;
  String? _trackKey;
  bool _isAudiblyPlaying = false;
  double _playbackSpeed = 1;
  int _lastPersistedMilliseconds = 0;
  int _lastPublishedMilliseconds = 0;

  Stream<RhythmGuardSnapshot> get stream => _snapshots.stream;
  RhythmGuardSnapshot get snapshot => _snapshot;

  /// Starts one process-wide watcher. MainShell calls this once per app
  /// session so usage is counted even while Home is off screen.
  Future<void> start() => _startFuture ??= _start();

  Future<void> _start() async {
    await _load();
    _snapshots.add(_snapshot);
    try {
      await PlaybackService.initialize();
      _mediaSubscription = PlaybackService.mediaItemStream.listen(
        _onMediaItem,
        onError: _onStreamError,
      );
      _stateSubscription = PlaybackService.playbackStateStream.listen(
        _onPlaybackState,
        onError: _onStreamError,
      );
      _positionSubscription = PlaybackService.positionStream.listen(
        _onPosition,
        onError: _onStreamError,
      );
    } on Exception {
      _log('Could not attach to playback tracking.');
    }
  }

  Future<void> setDailyLimit(Duration limit) async {
    await start();
    final minutes = limit.inMinutes.clamp(
      _minimumLimitMinutes,
      _maximumLimitMinutes,
    );
    _snapshot = RhythmGuardSnapshot(
      dayKey: _todayKey(),
      listenedMilliseconds: _todayUsage(),
      dailyLimitMinutes: minutes,
    );
    _snapshots.add(_snapshot);
    await _persist();
  }

  /// Stops listeners cleanly if the owning app session is being torn down.
  Future<void> stop() async {
    await _mediaSubscription?.cancel();
    await _stateSubscription?.cancel();
    await _positionSubscription?.cancel();
    _mediaSubscription = null;
    _stateSubscription = null;
    _positionSubscription = null;
    _isAudiblyPlaying = false;
    _lastPosition = null;
    _lastPositionAt = null;
    await _persist();
    _startFuture = null;
  }

  void _onMediaItem(MediaItem? item) {
    final key = item?.extras?['queueEntryId']?.toString() ?? item?.id;
    if (key != _trackKey) {
      _trackKey = key;
      _lastPosition = null;
      _lastPositionAt = null;
    }
  }

  void _onPlaybackState(PlaybackState state) {
    final isPlaying =
        state.playing && state.processingState == AudioProcessingState.ready;
    _playbackSpeed = state.speed > 0 ? state.speed : 1;
    if (isPlaying != _isAudiblyPlaying) {
      _isAudiblyPlaying = isPlaying;
      _lastPosition = null;
      _lastPositionAt = null;
      if (!isPlaying) unawaited(_persist());
    }
  }

  void _onPosition(Duration position) {
    final now = DateTime.now();
    if (!_isAudiblyPlaying) {
      _lastPosition = position;
      _lastPositionAt = now;
      return;
    }

    final previousPosition = _lastPosition;
    final previousAt = _lastPositionAt;
    _lastPosition = position;
    _lastPositionAt = now;
    if (previousPosition == null || previousAt == null) return;

    final elapsed = now.difference(previousAt);
    final moved = position - previousPosition;
    if (elapsed <= Duration.zero || moved <= Duration.zero) return;

    // A position jump larger than real elapsed playback is a seek. Clamp by
    // playback speed to count wall-clock listening time rather than song time.
    final expectedAudioMs = elapsed.inMilliseconds * _playbackSpeed;
    if (moved.inMilliseconds > expectedAudioMs + 1500) return;
    final playedMilliseconds = (moved.inMilliseconds / _playbackSpeed).round();
    final counted = playedMilliseconds.clamp(0, elapsed.inMilliseconds);
    if (counted <= 0) return;

    _addUsage(previousAt, now, counted);
  }

  void _addUsage(DateTime start, DateTime end, int milliseconds) {
    final today = _todayKey();
    final startDay = _dateKey(start);
    final endDay = _dateKey(end);
    var countForToday = milliseconds;
    if (startDay != endDay) {
      // Position events are frequent; if one straddles midnight, only the
      // portion after local midnight belongs to today's total.
      final midnight = DateTime(end.year, end.month, end.day);
      countForToday = endDay == today
          ? milliseconds.clamp(0, end.difference(midnight).inMilliseconds)
          : 0;
    } else if (endDay != today) {
      countForToday = 0;
    }

    if (countForToday <= 0) {
      _rolloverIfNeeded(today);
      return;
    }

    final base = _todayUsage();
    _snapshot = RhythmGuardSnapshot(
      dayKey: today,
      listenedMilliseconds: base + countForToday,
      dailyLimitMinutes: _snapshot.dailyLimitMinutes,
    );
    if ((_snapshot.listenedMilliseconds - _lastPublishedMilliseconds) >= 1000) {
      _lastPublishedMilliseconds = _snapshot.listenedMilliseconds;
      _snapshots.add(_snapshot);
    }
    if (_snapshot.listenedMilliseconds - _lastPersistedMilliseconds >= 10000) {
      _lastPersistedMilliseconds = _snapshot.listenedMilliseconds;
      unawaited(_persist());
    }
  }

  void _rolloverIfNeeded(String today) {
    if (_snapshot.dayKey == today) return;
    _snapshot = RhythmGuardSnapshot(
      dayKey: today,
      listenedMilliseconds: 0,
      dailyLimitMinutes: _snapshot.dailyLimitMinutes,
    );
    _lastPersistedMilliseconds = 0;
    _lastPublishedMilliseconds = 0;
    _snapshots.add(_snapshot);
    unawaited(_persist());
  }

  int _todayUsage() =>
      _snapshot.dayKey == _todayKey() ? _snapshot.listenedMilliseconds : 0;

  Future<void> _load() async {
    try {
      final file = await _file();
      if (!await file.exists()) return;
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map<String, dynamic>) return;
      final limit =
          (decoded['dailyLimitMinutes'] as num?)?.toInt() ??
          defaultDailyLimitMinutes;
      final day = decoded['dayKey'];
      final usage = (decoded['listenedMilliseconds'] as num?)?.toInt() ?? 0;
      final today = _todayKey();
      _snapshot = RhythmGuardSnapshot(
        dayKey: today,
        listenedMilliseconds: day == today ? usage.clamp(0, 86400000) : 0,
        dailyLimitMinutes: limit.clamp(
          _minimumLimitMinutes,
          _maximumLimitMinutes,
        ),
      );
      _lastPersistedMilliseconds = _snapshot.listenedMilliseconds;
      _lastPublishedMilliseconds = _snapshot.listenedMilliseconds;
      if (day != today) await _persist();
    } on Object {
      _log('Could not load saved daily listening data.');
    }
  }

  Future<void> _persist() async {
    final snapshot = _snapshot;
    final write = _writeTail.then((_) async {
      final file = await _file();
      await file.writeAsString(
        jsonEncode({
          'dayKey': snapshot.dayKey,
          'listenedMilliseconds': snapshot.listenedMilliseconds,
          'dailyLimitMinutes': snapshot.dailyLimitMinutes,
        }),
        flush: true,
      );
    });
    _writeTail = write.then<void>((_) {}).catchError((Object error) {
      _log('Could not save daily listening data.');
    });
    await _writeTail;
  }

  Future<File> _file() async {
    final directory = await getApplicationSupportDirectory();
    return File('${directory.path}/$_fileName');
  }

  void _onStreamError(Object error) => _log('Playback tracking stream failed.');

  void _log(String message) {
    if (kDebugMode) debugPrint('CLOVE Rhythm Guard: $message');
  }

  static String _todayKey() => _dateKey(DateTime.now());

  static String _dateKey(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-'
      '${value.month.toString().padLeft(2, '0')}-'
      '${value.day.toString().padLeft(2, '0')}';
}
