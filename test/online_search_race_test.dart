import 'dart:async';

import 'package:clove/models/online_music_track.dart';
import 'package:clove/screens/search_screen.dart';
import 'package:clove/services/online_music_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:clove/widgets/queue_swipe.dart';

class _FakeOnlineMusicProvider
    implements OnlineMusicProvider, CancellableOnlineMusicProvider {
  final searches = <String, Completer<OnlineMusicPage>>{};
  final resolutions = <String, Completer<DirectAudioSource>>{};
  int cancellationCount = 0;

  @override
  String get id => 'youtube';

  @override
  Future<OnlineMusicPage> search(String query, {String? pageToken}) =>
      (searches[query] ??= Completer<OnlineMusicPage>()).future;

  @override
  Future<DirectAudioSource> resolvePlaybackSource(OnlineMusicTrack track) =>
      (resolutions[track.id] ??= Completer<DirectAudioSource>()).future;

  @override
  Future<DirectAudioSource> refreshPlaybackSource(OnlineMusicTrack track) =>
      throw UnimplementedError();

  @override
  Future<void> cancelPendingPlayback() async {
    cancellationCount++;
  }

  @override
  void dispose() {}
}

OnlineMusicTrack _track(String id, String title) => OnlineMusicTrack(
  providerId: 'youtube',
  id: id,
  title: title,
  sourcePageUri: Uri.https('www.youtube.com', '/watch', {'v': id}),
);

void main() {
  testWidgets('a stale online search response cannot replace newer results', (
    tester,
  ) async {
    final provider = _FakeOnlineMusicProvider();
    await tester.pumpWidget(
      MaterialApp(home: SearchScreen(provider: provider)),
    );
    final field = find.byType(TextField);

    await tester.enterText(field, 'first query');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pump();
    await tester.enterText(field, 'second query');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pump();

    provider.searches['second query']!.complete(
      OnlineMusicPage(tracks: [_track('new', 'New result')]),
    );
    await tester.pump();
    provider.searches['first query']!.complete(
      OnlineMusicPage(tracks: [_track('old', 'Old result')]),
    );
    await tester.pump();

    expect(find.text('New result'), findsOneWidget);
    expect(find.text('Old result'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('query changes and closing search do not cancel pending play', (
    tester,
  ) async {
    final provider = _FakeOnlineMusicProvider();
    await tester.pumpWidget(
      MaterialApp(home: SearchScreen(provider: provider)),
    );
    final field = find.byType(TextField);

    await tester.enterText(field, 'pending query');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pump();
    provider.searches['pending query']!.complete(
      OnlineMusicPage(tracks: [_track('pending', 'Pending song')]),
    );
    await tester.pump();

    await tester.tap(find.text('Pending song'));
    await tester.pump();
    final resolution = provider.resolutions['pending']!;

    await tester.enterText(field, 'another query');
    await tester.pump();
    expect(provider.cancellationCount, 0);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(
      MaterialApp(home: SearchScreen(provider: provider)),
    );
    final reopenedField = find.byType(TextField);
    await tester.enterText(reopenedField, 'pending query');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pump();
    await tester.pump();

    final pendingRow = find.ancestor(
      of: find.text('Pending song'),
      matching: find.byType(QueueSwipe),
    );
    expect(
      find.descendant(
        of: pendingRow,
        matching: find.byType(CircularProgressIndicator),
      ),
      findsOneWidget,
    );

    resolution.completeError(
      const OnlineMusicProviderFailure(message: 'finish pending test'),
    );
    await tester.pump();
    await tester.pump();

    expect(provider.cancellationCount, 0);
    expect(
      find.descendant(
        of: pendingRow,
        matching: find.byType(CircularProgressIndicator),
      ),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
  });
}
