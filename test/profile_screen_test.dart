import 'package:clove/screens/about_screen.dart';
import 'package:clove/screens/profile_screen.dart';
import 'package:clove/screens/user_manual_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';

void main() {
  setUp(() {
    PackageInfo.setMockInitialValues(
      appName: 'Clove',
      packageName: 'com.shvnix.clove',
      version: '1.0.0',
      buildNumber: '1',
      buildSignature: '',
    );
  });

  testWidgets('name area opens edit dialog and validates before saving', (
    tester,
  ) async {
    String? savedName;
    await tester.pumpWidget(
      MaterialApp(
        home: ProfileScreen(
          username: 'Clove User',
          onSaveName: (name) async => savedName = name,
          onDeleteAccount: () async {},
        ),
      ),
    );

    await tester.tap(find.text('Edit name'));
    await tester.pumpAndSettle();
    expect(find.text('Clove User'), findsNWidgets(2));
    expect(find.byType(TextFormField), findsOneWidget);

    await tester.enterText(find.byType(TextFormField), '   ');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.text('Enter a name.'), findsOneWidget);
    expect(savedName, isNull);

    await tester.enterText(find.byType(TextFormField), '  New Name  ');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(savedName, 'New Name');
    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets('delete requires confirmation and cancel preserves account', (
    tester,
  ) async {
    var deletions = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: ProfileScreen(
          username: 'Clove User',
          onSaveName: (_) async {},
          onDeleteAccount: () async => deletions++,
        ),
      ),
    );

    await tester.tap(find.text('Delete account'));
    await tester.pumpAndSettle();
    expect(find.textContaining('permanently removes'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(deletions, 0);

    await tester.tap(find.text('Delete account'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete account').last);
    await tester.pumpAndSettle();
    expect(deletions, 1);
  });

  testWidgets('delete errors are reported without leaving Profile', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ProfileScreen(
            username: 'Clove User',
            onSaveName: (_) async {},
            onDeleteAccount: () async =>
                throw StateError('storage unavailable'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Delete account'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete account').last);
    await tester.pumpAndSettle();
    expect(find.byType(ProfileScreen), findsOneWidget);
    expect(find.textContaining('Could not delete account'), findsOneWidget);
  });

  testWidgets('manual and about open as separate pages', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ProfileScreen(
          username: 'Clove User',
          onSaveName: (_) async {},
          onDeleteAccount: () async {},
        ),
      ),
    );

    await tester.tap(find.text('User Manual'));
    await tester.pumpAndSettle();
    expect(find.byType(UserManualScreen), findsOneWidget);
    await tester.tap(find.byTooltip('Go back').first);
    await tester.pumpAndSettle();

    await tester.tap(find.text('About US'));
    await tester.pumpAndSettle();
    expect(find.byType(AboutScreen), findsOneWidget);
  });
}
