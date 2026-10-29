import 'dart:async';

import 'package:clove/services/serial_task_queue.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('continues with later tasks after a timed-out task', () async {
    final queue = SerialTaskQueue();
    final timedOut = queue.run(
      () => Completer<int>().future.timeout(const Duration(milliseconds: 1)),
    );

    await expectLater(timedOut, throwsA(isA<TimeoutException>()));
    expect(await queue.run(() async => 7), 7);
  });

  test('keeps tasks in order', () async {
    final queue = SerialTaskQueue();
    final order = <int>[];

    await Future.wait([
      queue.run(() async {
        order.add(1);
        await Future<void>.delayed(const Duration(milliseconds: 1));
        order.add(2);
      }),
      queue.run(() async => order.add(3)),
    ]);

    expect(order, [1, 2, 3]);
  });
}
