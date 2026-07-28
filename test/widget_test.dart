import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bank_working_desktop/main.dart';

void main() {
  testWidgets('unauthenticated app starts on the login screen', (WidgetTester tester) async {
    await tester.pumpWidget(const ProviderScope(child: BankWorkingDesktopApp()));

    // The splash screen holds until the user clicks "Enter" -- it never
    // auto-advances (splash_screen.dart's own doc comment says so) -- and
    // its glare sweep (an AnimationController.repeat()) and particle
    // field (a raw Ticker) animate forever by design. pumpAndSettle()
    // waits for every animation to finish, so it can never return while
    // the splash screen is showing; this was a pre-existing bug in this
    // test, unrelated to whatever else you're touching when you find it.
    // Pump by fixed durations instead of waiting for the screen to
    // "settle" -- 1800ms clears splash_screen.dart's _enterButtonDelay
    // (1700ms) so the button exists to tap.
    await tester.pump(const Duration(milliseconds: 1800));
    await tester.tap(find.text('Enter'));
    // Step through in small increments rather than one big pump(): the
    // fade-out AnimationController needs several ticks to actually reach
    // 1.0 and fire whenComplete() (which calls context.go('/login')),
    // and go_router needs a frame after that to build the new route.
    for (var i = 0; i < 15; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    expect(find.text('Sign in'), findsWidgets);
    expect(find.text('Bank Working Generator'), findsOneWidget);
  });
}
