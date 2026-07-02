import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import 'screens/home_screen.dart';
import 'theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await windowManager.ensureInitialized();

  const windowOptions = WindowOptions(
    size: Size(920, 640),
    minimumSize: Size(560, 480),
    center: true,
    title: 'SgfScrcpy',
    titleBarStyle: TitleBarStyle.normal,
    backgroundColor: Color(0xFF0E0F13),
  );
  windowManager.waitUntilReadyToShow(windowOptions, () async {
    await windowManager.show();
    await windowManager.focus();
  });

  runApp(const SgfScrcpyApp());
}

class SgfScrcpyApp extends StatelessWidget {
  const SgfScrcpyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SgfScrcpy',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark,
      home: const HomeScreen(),
    );
  }
}
