// lib/widgets/common/pin_lock_screen.dart
// Экран ввода PIN-кода при блокировке.

import 'dart:async';
import 'package:flutter/material.dart';
import '../../core/theme/app_icons.dart';
import '../../core/theme/tokens.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../l10n/app_localizations.dart';
import '../../services/security/pin_lock_service.dart';

class PinLockScreen extends ConsumerStatefulWidget {
  final VoidCallback? onUnlocked;
  const PinLockScreen({super.key, this.onUnlocked});

  @override
  ConsumerState<PinLockScreen> createState() => _PinLockScreenState();
}

class _PinLockScreenState extends ConsumerState<PinLockScreen> {
  String _pin = '';
  bool _hasError = false;
  final _focus = FocusNode();

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  /// Ввод с физической клавиатуры (Windows, планшет с клавиатурой).
  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.backspace) {
      _onKeyTap('⌫');
      return KeyEventResult.handled;
    }
    final ch = event.character;
    if (ch != null && ch.length == 1 && RegExp(r'\d').hasMatch(ch)) {
      _onKeyTap(ch);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final pinState = ref.watch(pinLockProvider);

    final blocked = pinState.isBlocked;
    final left = blocked
        ? pinState.blockedUntil!.difference(DateTime.now()).inSeconds + 1
        : 0;
    return Focus(
      focusNode: _focus,
      autofocus: true,
      onKeyEvent: _onKey,
      child: Scaffold(
      backgroundColor: AppColors.brandDark,
      body: SafeArea(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(AppIcons.lock, color: Colors.white, size: 48),
            const SizedBox(height: Space.l),
            Text(
              l10n.tr('enterPin'),
              style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: Space.s),

            if (blocked)
              Text(
                '${l10n.tr('blockedUseBiometrics')} (${left}s)',
                style: const TextStyle(color: Color(0xFFE06A62), fontSize: 14), // спокойный красный на тёмном фоне
                textAlign: TextAlign.center,
              ),

            if (_hasError && !blocked)
              Text(
                '${l10n.tr('wrongPin')} (${pinState.failedAttempts}/${PinLockNotifier.maxAttempts})',
                style: const TextStyle(color: Color(0xFFE06A62), fontSize: 14), // спокойный красный на тёмном фоне
              ),

            const SizedBox(height: Space.xxl),

            // Индикатор PIN
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(pinState.pinLength, (i) {
                return Container(
                  margin: const EdgeInsets.symmetric(horizontal: Space.s),
                  width: 16, height: 16,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: i < _pin.length ? Colors.white : Colors.white.withValues(alpha: 0.3),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.5)),
                  ),
                );
              }),
            ),
            const SizedBox(height: 48),

            // Клавиатура
            ..._buildKeypad(theme),

            const SizedBox(height: Space.xl),

            // Биометрия
            TextButton.icon(
              onPressed: () async {
                // Реальная проверка отпечатка/лица — разблокировка только при успехе.
                final ok = await ref.read(pinLockProvider.notifier).authenticateBiometric();
                if (ok && context.mounted) {
                  widget.onUnlocked?.call();
                }
              },
              icon: const Icon(AppIcons.fingerprint, color: Colors.white70),
              label: Text(l10n.tr('loginBiometric'), style: const TextStyle(color: Colors.white70)),
            ),
          ],
        ),
      ),
    ),
    );
  }

  List<Widget> _buildKeypad(ThemeData theme) {
    return [
      _keyRow(['1', '2', '3']),
      _keyRow(['4', '5', '6']),
      _keyRow(['7', '8', '9']),
      _keyRow(['', '0', '⌫']),
    ];
  }

  Widget _keyRow(List<String> keys) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Space.xs),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: keys.map((key) {
          if (key.isEmpty) return const SizedBox(width: 80);
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: Space.m),
            child: InkWell(
              onTap: () => _onKeyTap(key),
              borderRadius: BorderRadius.circular(40),
              child: Container(
                width: 72, height: 72,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withValues(alpha: 0.1),
                ),
                child: key == '⌫'
                    ? const Icon(AppIcons.backspace, color: Colors.white, size: 24)
                    : Text(key, style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.w300)),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  void _onKeyTap(String key) {
    HapticFeedback.selectionClick();

    if (key == '⌫') {
      if (_pin.isNotEmpty) {
        setState(() { _pin = _pin.substring(0, _pin.length - 1); _hasError = false; });
      }
      return;
    }

    final len = ref.read(pinLockProvider).pinLength;
    if (_pin.length >= len) return;

    setState(() { _pin += key; _hasError = false; });

    // Проверяем, когда введено столько цифр, сколько в установленном PIN.
    if (_pin.length >= len) {
      _verifyPin();
    }
  }

  Future<void> _verifyPin() async {
    final success = await ref.read(pinLockProvider.notifier).verifyPin(_pin);
    if (success) {
      unawaited(HapticFeedback.mediumImpact());
      widget.onUnlocked?.call();
    } else {
      unawaited(HapticFeedback.heavyImpact());
      setState(() { _pin = ''; _hasError = true; });
    }
  }
}
