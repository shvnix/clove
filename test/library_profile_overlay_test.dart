import 'package:clove/screens/library_screen.dart';
import 'package:clove/screens/about_screen.dart';
import 'package:clove/screens/profile_screen.dart';
import 'package:clove/screens/user_manual_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<GlobalKey<LibraryScreenState>> pumpLibrary(WidgetTester tester) async {
    final key = GlobalKey<LibraryScreenState>();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LibraryScreen(
            key: key,
            username: 'Ava',
            onSaveUsername: (_) async {},
            onDeleteAccount: () async {},
          ),
        ),
      ),
    );
    return key;
  }

  testWidgets('profile overlay refreshes username after the parent rebuilds', (
    tester,
  ) async {
    Future<void> pumpLibrary(String username) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: LibraryScreen(
              username: username,
              onSaveUsername: (_) async {},
              onDeleteAccount: () async {},
            ),
          ),
        ),
      );
    }

    await pumpLibrary('Ava');
    await tester.tap(find.text('A').first);
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Ava'), findsOneWidget);

    await pumpLibrary('Mira');
    await tester.pump();
    expect(find.text('Mira'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'manual starts opening from Profile and Back returns to Library',
    (tester) async {
      final libraryKey = await pumpLibrary(tester);
      await tester.tap(find.text('A').first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(libraryKey.currentState!.profileTransitionAnimation.value, 1);

      await tester.tap(find.text('User Manual'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 16));
      expect(find.byType(UserManualScreen), findsOneWidget);
      expect(find.byType(ProfileScreen), findsOneWidget);

      await tester.pump(const Duration(milliseconds: 350));
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byType(ProfileScreen), findsNothing);
      expect(find.byType(UserManualScreen), findsOneWidget);

      await tester.tap(find.byTooltip('Go back').first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('Your Library'), findsOneWidget);
      expect(
        Navigator.of(tester.element(find.byType(LibraryScreen))).canPop(),
        isFalse,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('About opens once for rapid repeated Profile taps', (
    tester,
  ) async {
    final libraryKey = await pumpLibrary(tester);
    await tester.tap(find.text('A').first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(libraryKey.currentState!.profileTransitionAnimation.value, 1);

    final profile = tester.widget<ProfileScreen>(find.byType(ProfileScreen));
    final firstNavigation = profile.onOpenAbout!();
    final duplicateNavigation = profile.onOpenAbout!();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));
    expect(find.byType(AboutScreen), findsOneWidget);
    expect(find.byType(ProfileScreen), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.byType(AboutScreen), findsOneWidget);
    expect(find.byType(ProfileScreen), findsNothing);

    await tester.tap(find.byTooltip('Go back').first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pump(const Duration(milliseconds: 100));
    await firstNavigation;
    await duplicateNavigation;
    expect(tester.takeException(), isNull);
  });
}
