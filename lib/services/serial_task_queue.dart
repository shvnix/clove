/// Runs asynchronous tasks one at a time and keeps the queue usable after a
/// task fails or times out.
class SerialTaskQueue {
  Future<void> _tail = Future<void>.value();

  Future<T> run<T>(Future<T> Function() operation) {
    final result = _tail.then((_) => operation());
    _tail = result.then<void>((_) {}).catchError((Object _) {});
    return result;
  }
}
