// lib/widgets/desktop/tray_window_listener.dart
// Перехватывает закрытие окна на desktop и прячет его в трей.

import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

class TrayWindowListener extends StatefulWidget {
  final Widget child;
  const TrayWindowListener({super.key, required this.child});

  @override
  State<TrayWindowListener> createState() => _TrayWindowListenerState();
}

class _TrayWindowListenerState extends State<TrayWindowListener> with WindowListener {
  bool get _isDesktop =>
      !kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS);

  @override
  void initState() {
    super.initState();
    if (_isDesktop) windowManager.addListener(this);
  }

  @override
  void dispose() {
    if (_isDesktop) windowManager.removeListener(this);
    super.dispose();
  }

  @override
  // Переопределение void-метода WindowListener.
  // ignore: avoid_void_async
  void onWindowClose() async {
    if (_isDesktop) {
      final prevent = await windowManager.isPreventClose();
      if (prevent) await windowManager.hide();
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
