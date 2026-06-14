import 'package:flutter/material.dart';

import '../features/focus/application/focus_controller.dart';
import '../features/focus/presentation/focus_shell.dart';

class FocusLockApp extends StatefulWidget {
  const FocusLockApp({super.key, this.controller});

  final FocusController? controller;

  @override
  State<FocusLockApp> createState() => _FocusLockAppState();
}

class _FocusLockAppState extends State<FocusLockApp> {
  late final FocusController controller;

  @override
  void initState() {
    super.initState();
    controller = widget.controller ?? FocusController();
    controller.initialize();
  }

  @override
  void dispose() {
    if (widget.controller == null) controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'View Clock',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xff315c55),
          brightness: Brightness.light,
        ),
        useMaterial3: true,
        cardTheme: const CardThemeData(margin: EdgeInsets.zero),
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xff7fc8b8),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: AnimatedBuilder(
        animation: controller,
        builder: (context, _) {
          if (controller.loading) {
            return const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            );
          }
          return FocusShell(controller: controller);
        },
      ),
    );
  }
}
