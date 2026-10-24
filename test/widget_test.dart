import 'package:clove/main.dart';
import 'package:clove/screens/splash_screen.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('a cold Clove launch starts on the SHVNIX splash screen', (
    tester,
  ) async {
    await tester.pumpWidget(const CloveApp());

    expect(find.byType(CloveSplashScreen), findsOneWidget);
    expect(find.text('SHVNIX'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
