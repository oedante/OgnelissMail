// lib/widgets/common/app_logo.dart
// Знак приложения — для экрана входа и «О программе»: тот же, что на
// рабочем столе (с 09.10.2026 — конверт с огненной лисой; ресурсы —
// tool/branding/make_icon_v5.py).

import 'package:flutter/material.dart';

class AppLogo extends StatelessWidget {
  final double size;
  const AppLogo({super.key, this.size = 72});

  @override
  Widget build(BuildContext context) => ClipRRect(
        borderRadius: BorderRadius.circular(size * 0.23),
        child: Image.asset(
          'assets/brand/fox_icon.png',
          width: size,
          height: size,
          filterQuality: FilterQuality.medium,
          semanticLabel: 'Ogneliss Mail',
        ),
      );
}
