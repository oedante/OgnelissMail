// lib/features/compose/compose_window_launcher.dart
//
// Страница адреса /compose в главном окне, когда редактор открывается
// отдельным окном (2.5.4, compose_window.dart): прозрачная, открывает окно и
// сразу закрывается. Окно не создалось — на её месте редактор, как раньше.

import 'dart:async';

import 'package:flutter/material.dart';

import '../../widgets/common/wide_frame.dart';
import 'compose_window.dart';
import 'screens/compose_screen.dart';

class ComposeWindowLauncher extends StatefulWidget {
  final Map<String, String> query;
  const ComposeWindowLauncher({super.key, required this.query});

  @override
  State<ComposeWindowLauncher> createState() => _ComposeWindowLauncherState();
}

class _ComposeWindowLauncherState extends State<ComposeWindowLauncher> {
  bool _here = false;

  @override
  void initState() {
    super.initState();
    unawaited(_open());
  }

  Future<void> _open() async {
    final ok = await ComposeWindow.open(widget.query);
    if (!mounted) return;
    if (ok) {
      Navigator.of(context).maybePop();
    } else {
      setState(() => _here = true);
    }
  }

  @override
  Widget build(BuildContext context) =>
      _here ? WideFrame.wide(child: ComposeScreen.fromQuery(widget.query)) : const SizedBox.shrink();
}
