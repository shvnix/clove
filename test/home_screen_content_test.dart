import 'package:clove/screens/home_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Home retains its profile header and renders music sections', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: HomeScreen(username: 'Ava', onOpenProfile: () {}),
      ),
    );

    expect(find.text('Ava'), findsOneWidget);
    expect(find.text('Liked Songs'), findsOneWidget);
    expect(find.text('Recently played'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Artists'), 220);
    expect(find.text('Artists'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Rhythm Guard'), 220);
    expect(find.text('Rhythm Guard'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('New Releases'), 220);
    expect(find.text('New Releases'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Your playlists'), 220);
    expect(find.text('Your playlists'), findsOneWidget);
    await tester.drag(find.byType(ListView).first, const Offset(0, 2200));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.scrollUntilVisible(find.text('Your playlists'), 220);
    expect(find.text('Your playlists'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
  });
}
