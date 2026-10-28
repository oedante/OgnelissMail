// lib/features/settings/providers/feature_flags_provider.dart
// Пользовательские переключатели поведения ядра: вкладка «Задачи», окно
// отмены отправки, подтверждение адресатов, порог антифишинга.
//
// Прежде здесь были профили «Базовый/Расширенный» и флаги дашборда,
// поручений, ИИ и голоса. Эти модули вынесены из приложения (этап 1 плана:
// сначала крепкое ядро), профили стали не нужны. Ключи ff_dashboard_tab,
// ff_assignments, ff_smart, ff_voice, ff_profile в SharedPreferences
// больше не читаются — при возврате модулей их можно поднять заново.

import 'package:flutter_riverpod/legacy.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../data/providers/shared_prefs_provider.dart';

/// Порог показа антифишинг-баннера.
enum AntiPhishingLevel { off, dangerOnly, all }

class FeatureFlags {
  final bool showTasksTab;
  /// Разделы «Заметки» и «Файловый хаб» (1.5.9): выключенный раздел
  /// пропадает из бокового меню, «Ещё», панели планшета, карточек письма и
  /// человека; ярлыки и виджеты ведут в почту. Данные не удаляются.
  final bool showNotes;
  final bool showFileHub;
  final AntiPhishingLevel antiPhishing;
  final int undoSendSeconds; // окно отмены отправки, 0 = выключено
  final bool confirmRecipients; // подтверждать внешних адресатов/большой список

  /// Размер фото во вложениях при отправке (1.7.2+109): 0 — спрашивать
  /// (шторка «Размер фото»), 100 — как есть, 75 / 50 / 25 — уменьшать до
  /// этой доли ширины и высоты без вопроса.
  final int photoSize;

  const FeatureFlags({
    this.showTasksTab = true,
    this.showNotes = true,
    this.showFileHub = true,
    this.antiPhishing = AntiPhishingLevel.dangerOnly,
    this.undoSendSeconds = 5,
    this.confirmRecipients = true,
    this.photoSize = 0,
  });

  /// Допустимые значения [photoSize].
  static const photoSizes = [0, 100, 75, 50, 25];

  /// Показать ли сигнал антифишинга данного уровня (0..3 = none/info/
  /// warning/danger из sender_safety_service).
  bool showSafetyLevel(int levelIndex) {
    switch (antiPhishing) {
      case AntiPhishingLevel.off:
        return false;
      case AntiPhishingLevel.dangerOnly:
        return levelIndex >= 3;
      case AntiPhishingLevel.all:
        return levelIndex >= 1;
    }
  }
}

class _FK {
  static const tasksTab = 'ff_tasks_tab';
  static const notes = 'ff_notes';
  static const fileHub = 'ff_file_hub';
  static const antiPhishing = 'ff_antiphishing';
  static const undoSend = 'ff_undo_send';
  static const confirmRcpt = 'ff_confirm_rcpt';
  static const photoSize = 'ff_photo_size';
}

class FeatureFlagsNotifier extends StateNotifier<FeatureFlags> {
  final SharedPreferences _p;
  FeatureFlagsNotifier(this._p) : super(_load(_p));

  static FeatureFlags _load(SharedPreferences p) {
    const d = FeatureFlags();
    return FeatureFlags(
      showTasksTab: p.getBool(_FK.tasksTab) ?? d.showTasksTab,
      showNotes: p.getBool(_FK.notes) ?? d.showNotes,
      showFileHub: p.getBool(_FK.fileHub) ?? d.showFileHub,
      antiPhishing: AntiPhishingLevel.values[(p.getInt(_FK.antiPhishing) ?? d.antiPhishing.index)
          .clamp(0, AntiPhishingLevel.values.length - 1)],
      undoSendSeconds: p.getInt(_FK.undoSend) ?? d.undoSendSeconds,
      confirmRecipients: p.getBool(_FK.confirmRcpt) ?? d.confirmRecipients,
      photoSize: FeatureFlags.photoSizes.contains(p.getInt(_FK.photoSize)) ? p.getInt(_FK.photoSize)! : d.photoSize,
    );
  }

  Future<void> setTasksTab(bool v) async {
    await _p.setBool(_FK.tasksTab, v);
    state = _load(_p);
  }

  Future<void> setNotes(bool v) async {
    await _p.setBool(_FK.notes, v);
    state = _load(_p);
  }

  Future<void> setFileHub(bool v) async {
    await _p.setBool(_FK.fileHub, v);
    state = _load(_p);
  }

  Future<void> setAntiPhishing(AntiPhishingLevel v) async {
    await _p.setInt(_FK.antiPhishing, v.index);
    state = _load(_p);
  }

  Future<void> setUndoSendSeconds(int v) async {
    await _p.setInt(_FK.undoSend, v);
    state = _load(_p);
  }

  Future<void> setConfirmRecipients(bool v) async {
    await _p.setBool(_FK.confirmRcpt, v);
    state = _load(_p);
  }

  Future<void> setPhotoSize(int v) async {
    if (!FeatureFlags.photoSizes.contains(v)) return;
    await _p.setInt(_FK.photoSize, v);
    state = _load(_p);
  }
}

final featureFlagsProvider =
    StateNotifierProvider<FeatureFlagsNotifier, FeatureFlags>((ref) {
  final prefs = ref.watch(sharedPrefsProvider);
  return FeatureFlagsNotifier(prefs);
});
