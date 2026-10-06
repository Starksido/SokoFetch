import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'core/session.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Portrait everywhere; the merchant area unlocks landscape while it's open
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.dark,
  ));

  Session.init();
  runApp(const SessionScope(child: SokoFetchApp()));
}

/// Rebuilds the whole app with fresh providers whenever the session ends,
/// so nothing from the previous account (cart, orders, profile) survives.
class SessionScope extends StatelessWidget {
  const SessionScope({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<int>(
        valueListenable: sessionGeneration,
        builder: (_, generation, __) =>
            ProviderScope(key: ValueKey(generation), child: child),
      );
}
