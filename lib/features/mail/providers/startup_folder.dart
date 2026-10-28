// lib/features/mail/providers/startup_folder.dart
// Какую папку открывать при запуске: «Вся почта», «Входящие» или последнюю
// выбранную. Последний выбор запоминается при каждом переходе в меню папок.

import 'package:flutter_riverpod/legacy.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../data/providers/shared_prefs_provider.dart';

enum StartupFolder { allMail, inbox, last }

const _kStartup = 'startup_folder';
const _kLastFolder = 'startup_last_folder'; // id папки или пусто — «Вся почта»
const _kLastAccount = 'startup_last_account';

class StartupFolderNotifier extends StateNotifier<StartupFolder> {
  final SharedPreferences _p;
  StartupFolderNotifier(this._p)
      : super(StartupFolder.values[(_p.getInt(_kStartup) ?? 0).clamp(0, StartupFolder.values.length - 1)]);

  Future<void> set(StartupFolder v) async {
    state = v;
    await _p.setInt(_kStartup, v.index);
  }

  /// Запомнить выбор в меню папок. [folderId] null — «Вся почта».
  Future<void> rememberSelection({String? folderId, String? accountId}) async {
    await _p.setString(_kLastFolder, folderId ?? '');
    await _p.setString(_kLastAccount, accountId ?? '');
  }

  /// Последняя выбранная папка: (id папки или null, аккаунт).
  ({String? folderId, String? accountId}) get lastSelection {
    final f = _p.getString(_kLastFolder);
    final a = _p.getString(_kLastAccount);
    return (
      folderId: (f == null || f.isEmpty) ? null : f,
      accountId: (a == null || a.isEmpty) ? null : a,
    );
  }
}

final startupFolderProvider = StateNotifierProvider<StartupFolderNotifier, StartupFolder>(
  (ref) => StartupFolderNotifier(ref.watch(sharedPrefsProvider)),
);
