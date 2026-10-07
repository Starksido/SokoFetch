import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soko_fetch/core/theme.dart';

/// Screen sizes every redesigned screen must lay out at without overflow:
/// small phone, common phone, large phone, tablet landscape.
const kScreenSizes = [
  Size(320, 640),
  Size(360, 800),
  Size(412, 915),
  Size(1280, 800),
];

/// Pumps [screen] at [size] and [textScale]; returns layout errors.
Future<List<String>> pumpAt(WidgetTester tester, Widget screen, Size size,
    {double textScale = 1.0,
    Object? arguments,
    List<Override> overrides = const []}) async {
  final errors = <String>[];
  final previous = FlutterError.onError;
  FlutterError.onError =
      (d) => errors.add(d.toString().split('\n').take(4).join(' '));

  tester.view.physicalSize = size * 2;
  tester.view.devicePixelRatio = 2;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(ProviderScope(
    overrides: overrides,
    child: MaterialApp(
      theme: AppTheme.light,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      onGenerateRoute: (s) => MaterialPageRoute(
          builder: (_) => Scaffold(body: Text('route:${s.name}'))),
      onGenerateInitialRoutes: (_) => [
        MaterialPageRoute(
          builder: (_) => screen,
          settings: RouteSettings(name: '/test', arguments: arguments),
        ),
      ],
    ),
  ));
  await tester.pump(const Duration(milliseconds: 300));
  // Restore before any expect() runs, or a failure hides the real error
  FlutterError.onError = previous;
  return errors;
}

/// Tests draw text with a placeholder font whose letters are full squares,
/// about twice as wide as Inter; load the real font so widths match phones.
Future<void> loadAppFont() async {
  final loader = FontLoader('Inter');
  for (final w in ['Regular', 'Medium', 'SemiBold', 'Bold']) {
    loader.addFont(rootBundle.load('assets/fonts/Inter-$w.ttf'));
  }
  await loader.load();
}
