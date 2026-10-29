import 'package:flutter/foundation.dart';

/// Tracks online actions outside a screen so pending indicators survive
/// navigating away from Search and returning to the same result.
class OnlineActionTracker extends ChangeNotifier {
  OnlineActionTracker._();

  static final instance = OnlineActionTracker._();

  final Map<String, int> _openingCounts = {};
  final Map<String, int> _queueingCounts = {};

  bool isOpening(String trackKey) => (_openingCounts[trackKey] ?? 0) > 0;

  bool isQueueing(String trackKey) => (_queueingCounts[trackKey] ?? 0) > 0;

  void beginOpening(String trackKey) => _increment(_openingCounts, trackKey);

  void finishOpening(String trackKey) => _decrement(_openingCounts, trackKey);

  void beginQueueing(String trackKey) => _increment(_queueingCounts, trackKey);

  void finishQueueing(String trackKey) => _decrement(_queueingCounts, trackKey);

  void _increment(Map<String, int> counts, String trackKey) {
    counts.update(trackKey, (count) => count + 1, ifAbsent: () => 1);
    notifyListeners();
  }

  void _decrement(Map<String, int> counts, String trackKey) {
    final count = counts[trackKey];
    if (count == null) return;
    if (count <= 1) {
      counts.remove(trackKey);
    } else {
      counts[trackKey] = count - 1;
    }
    notifyListeners();
  }
}
