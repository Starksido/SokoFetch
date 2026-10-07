import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soko_fetch/core/theme.dart';
import 'package:soko_fetch/core/ui/ui.dart';
import 'package:soko_fetch/features/auth/otp_screen.dart';
import 'package:soko_fetch/features/auth/role_picker_screen.dart';
import 'package:soko_fetch/features/auth/splash_screen.dart';
import 'package:soko_fetch/features/auth/welcome_screen.dart';

import 'ui_helpers.dart';

void main() {
  setUpAll(loadAppFont);

  group('formatKes', () {
    test('groups thousands and drops .00', () {
      expect(formatKes(0), 'KES 0');
      expect(formatKes(950), 'KES 950');
      expect(formatKes(1250), 'KES 1,250');
      expect(formatKes(1234567), 'KES 1,234,567');
    });

    test('keeps real cents', () {
      expect(formatKes(377.25), 'KES 377.25');
      expect(formatKes(61.6), 'KES 61.60');
      expect(formatKes(-40.5), '-KES 40.50');
    });
  });

  test('photo paths from the API load from the API server', () {
    const base = 'http://127.0.0.1:8000';
    expect(resolveMediaUrl('/media/demo/tomatoes.jpg', base: base),
        'http://127.0.0.1:8000/media/demo/tomatoes.jpg');
    expect(resolveMediaUrl('/media/x.jpg', base: '$base/'),
        'http://127.0.0.1:8000/media/x.jpg');
    expect(resolveMediaUrl('https://cdn.example.com/a.jpg', base: base),
        'https://cdn.example.com/a.jpg');
    expect(resolveMediaUrl(null), isNull);
    expect(resolveMediaUrl(''), isNull);
  });

  group('order status pill', () {
    test('every status has a friendly label', () {
      expect(orderStatusStyle('in_transit'), ('On the way', PillTone.accent));
      expect(orderStatusStyle('delivered'), ('Delivered', PillTone.success));
      expect(orderStatusStyle('cancelled').$2, PillTone.danger);
      expect(orderStatusStyle('pending').$2, PillTone.warning);
      // Unknown statuses still read sensibly
      expect(orderStatusStyle('on_hold').$1, 'on hold');
    });
  });

  testWidgets('splash logo and tagline are centred', (tester) async {
    FlutterSecureStorage.setMockInitialValues({});
    const size = Size(360, 800);
    await pumpAt(tester, const SplashScreen(delay: Duration(seconds: 1)), size);
    for (final f in [
      find.byType(SokoMark),
      find.text('Your local shops, delivered'),
    ]) {
      expect(tester.getCenter(f).dx, closeTo(size.width / 2, 1));
    }
    await tester.pumpAndSettle(const Duration(seconds: 2)); // Let it move on
  });

  testWidgets('a stat tile shrinks a long amount instead of cutting it off',
      (tester) async {
    await pumpAt(
        tester,
        const Scaffold(
          body: Center(
            child: SizedBox(
                width: 100, // a third of a small phone, as on rider Profile
                child: StatTile(label: 'Earned', value: 'KES 87.94')),
          ),
        ),
        const Size(360, 800));
    final value = tester.renderObject<RenderParagraph>(find.text('KES 87.94'));
    expect(value.didExceedMaxLines, isFalse);
  });

  testWidgets('bottom bar shows count, label and price, and can be disabled',
      (tester) async {
    var taps = 0;
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light,
      home: Scaffold(
        bottomNavigationBar: BottomCtaBar(
            label: 'View cart', count: 3, amount: 1250, onPressed: () => taps++),
      ),
    ));
    expect(find.text('3'), findsOneWidget);
    expect(find.text('View cart'), findsOneWidget);
    expect(find.text('KES 1,250'), findsOneWidget);
    await tester.tap(find.text('View cart'));
    expect(taps, 1);

    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light,
      home: const Scaffold(
          bottomNavigationBar: BottomCtaBar(label: 'Continue', onPressed: null)),
    ));
    final button = tester.widget<ElevatedButton>(find.byType(ElevatedButton));
    expect(button.onPressed, isNull);
  });

  group('sign-in screens lay out at every size', () {
    final screens = <String, (Widget, Object?)>{
      'welcome': (const WelcomeScreen(), null),
      'otp': (const OtpScreen(), '+254712345678'),
      'role picker': (const RolePickerScreen(), 'signup-token'),
    };
    for (final MapEntry(key: name, value: (screen, args)) in screens.entries) {
      for (final size in kScreenSizes) {
        testWidgets('$name at ${size.width.toInt()}x${size.height.toInt()}',
            (tester) async {
          expect(await pumpAt(tester, screen, size, arguments: args), isEmpty);
        });
      }
      testWidgets('$name with large text', (tester) async {
        expect(
            await pumpAt(tester, screen, const Size(360, 800),
                textScale: 1.3, arguments: args),
            isEmpty);
      });
    }
  });
}
