import 'package:clove/screens/main_shell.dart';
import 'package:clove/screens/profile_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Home and Luna avatars open the shared Profile overlay', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(splashFactory: NoSplash.splashFactory),
        home: const MainShell(username: 'Ava'),
      ),
    );

    await tester.tap(find.text('A').first);
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(ProfileScreen), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.binding.handlePopRoute();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(ProfileScreen), findsNothing);

    await tester.tapAt(const Offset(590, 540));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('A').first);
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(ProfileScreen), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.binding.handlePopRoute();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(ProfileScreen), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
