// lib/features/mail/providers/drawer_prefs.dart
// Настройки бокового меню, которые пользователь меняет сам:
//  · какие быстрые разделы видны в «Избранном» (Все письма, Непрочитанные…);
//  · какие ветки дерева папок свёрнуты.
// Хранятся в SharedPreferences — это вид меню, а не данные ящика; при
// переустановке теряются без вреда. Избранные ПАПКИ хранятся в базе
// (folders.is_favorite), рядом с самой папкой.

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/providers/shared_prefs_provider.dart';

/// Быстрые разделы «Избранного». Порядок — как в меню.
/// fileHub — «Файловый хаб» (все вложения): по умолчанию виден.
/// notes — «Заметки» (раньше отдельный раздел «Разделы»), tasks — «Задачи»,
/// показываются, только если их вкладка скрыта в нижней панели.
/// myDay, settings, theme — из бывшего меню «Ещё» (1.6.40): по умолчанию
/// видны (у тех, кто уже настраивал избранное, тоже — их нет в сохранённом
/// списке скрытых).
enum DrawerQuickItem { allAccounts, allMail, unread, flagged, vip, attachments, fileHub, notes, tasks, control, later, triage, myDay, settings, theme }

const _kHiddenQuick = 'drawer_quick_hidden';
const _kCollapsed = 'drawer_collapsed_folders';

/// Скрытые быстрые разделы (по умолчанию видны все).
class HiddenQuickItemsNotifier extends Notifier<Set<DrawerQuickItem>> {
  @override
  Set<DrawerQuickItem> build() {
    final raw = ref.read(sharedPrefsProvider).getStringList(_kHiddenQuick);
    // По умолчанию фильтры (Непрочитанные, С флагом, VIP, Вложения) скрыты:
    // они дублируют кнопку фильтра в шапке списка и занимали полменю.
    // Включаются в настройке избранного.
    if (raw == null) return _defaultHidden;
    return {
      for (final name in raw)
        for (final v in DrawerQuickItem.values)
          if (v.name == name) v,
      // Появились позже — скрыты, пока их не включат явно (11.10.2026):
      // иначе у тех, кто уже менял избранное, они показались бы сами.
      for (final v in _optIn)
        if (!(ref.read(sharedPrefsProvider).getBool('$_kOptInOn${v.name}') ?? false)) v,
    };
  }

  Future<void> setVisible(DrawerQuickItem item, bool visible) async {
    if (_optIn.contains(item)) {
      await ref.read(sharedPrefsProvider).setBool('$_kOptInOn${item.name}', visible);
    }
    final next = {...state};
    visible ? next.remove(item) : next.add(item);
    state = next;
    await ref.read(sharedPrefsProvider)
        .setStringList(_kHiddenQuick, [for (final v in next) v.name]);
  }
}

/// Разделы, которые нужно включить явно (по умолчанию скрыты всегда).
const _optIn = {DrawerQuickItem.triage};
const _kOptInOn = 'drawer_quick_on_';

const _defaultHidden = {
  DrawerQuickItem.triage,
  DrawerQuickItem.unread,
  DrawerQuickItem.flagged,
  DrawerQuickItem.vip,
  DrawerQuickItem.attachments,
};

final hiddenQuickItemsProvider =
    NotifierProvider<HiddenQuickItemsNotifier, Set<DrawerQuickItem>>(
        HiddenQuickItemsNotifier.new);

/// Свёрнутые ветки дерева папок: ключ «аккаунт|папка». По умолчанию дерево
/// развёрнуто — как было раньше; свёрнутое запоминается между запусками.
class CollapsedFoldersNotifier extends Notifier<Set<String>> {
  @override
  Set<String> build() =>
      (ref.read(sharedPrefsProvider).getStringList(_kCollapsed) ?? const []).toSet();

  static String key(String accountId, String folderId) => '$accountId|$folderId';

  bool isCollapsed(String accountId, String folderId) =>
      state.contains(key(accountId, folderId));

  Future<void> toggle(String accountId, String folderId) async {
    final k = key(accountId, folderId);
    final next = {...state};
    if (!next.remove(k)) next.add(k);
    state = next;
    await ref.read(sharedPrefsProvider).setStringList(_kCollapsed, next.toList());
  }
}

final collapsedFoldersProvider =
    NotifierProvider<CollapsedFoldersNotifier, Set<String>>(CollapsedFoldersNotifier.new);

/// Меню папок закреплено постоянной панелью (планшет и компьютер, 1.6.40,
/// просьба владельца — «значок фиксации панели»). null — как раньше: на
/// широком окне (от 1040) закреплено, уже — выдвигается.
class DrawerPinnedNotifier extends Notifier<bool?> {
  static const _k = 'drawer_pinned';

  @override
  bool? build() => ref.read(sharedPrefsProvider).getBool(_k);

  Future<void> set(bool pinned) async {
    state = pinned;
    await ref.read(sharedPrefsProvider).setBool(_k, pinned);
  }
}

final drawerPinnedProvider = NotifierProvider<DrawerPinnedNotifier, bool?>(DrawerPinnedNotifier.new);

/// Меню ящиков и папок на телефоне — справа (портрет «Меню» внизу справа,
/// свайп от правого края) или слева (по умолчанию: портрет внизу слева,
/// свайп от левого края). Настройка — «Общие → Меню», 1.6.40: части
/// тестировщиков удобнее справа, части — слева.
class MenuOnRightNotifier extends Notifier<bool> {
  static const _k = 'menu_on_right';

  @override
  bool build() => ref.read(sharedPrefsProvider).getBool(_k) ?? false;

  Future<void> set(bool right) async {
    state = right;
    await ref.read(sharedPrefsProvider).setBool(_k, right);
  }
}

final menuOnRightProvider = NotifierProvider<MenuOnRightNotifier, bool>(MenuOnRightNotifier.new);

/// Быстрые фильтры строкой над лентой (1.6.45, из плана интерфейса 05.10:
/// «фильтры — чипами над списком»): «Непрочитанные», «Мне лично», «Сегодня»…
/// одним нажатием, без шторки фильтров. Включаются в «Настройки → Почта»;
/// по умолчанию выключены — лента остаётся спокойной.
class QuickFiltersNotifier extends Notifier<bool> {
  static const _k = 'mail_quick_filters';

  @override
  bool build() => ref.read(sharedPrefsProvider).getBool(_k) ?? false;

  Future<void> set(bool on) async {
    state = on;
    await ref.read(sharedPrefsProvider).setBool(_k, on);
  }
}

final quickFiltersProvider = NotifierProvider<QuickFiltersNotifier, bool>(QuickFiltersNotifier.new);

/// Строка «Ответить…» внизу письма (1.6.49, как поле ввода в Telegram) —
/// по умолчанию включена.
class QuickReplyBarNotifier extends Notifier<bool> {
  static const _k = 'mail_quick_reply_bar';

  @override
  bool build() => ref.read(sharedPrefsProvider).getBool(_k) ?? true;

  Future<void> set(bool on) async {
    state = on;
    await ref.read(sharedPrefsProvider).setBool(_k, on);
  }
}

final quickReplyBarProvider = NotifierProvider<QuickReplyBarNotifier, bool>(QuickReplyBarNotifier.new);

/// Беседа «как чат» (1.6.49): старые письма сверху, новые — внизу, у строки
/// ответа; экран открывается на последнем письме. По умолчанию — как
/// раньше (новые сверху).
class ConvChatOrderNotifier extends Notifier<bool> {
  static const _k = 'conv_chat_order';

  @override
  bool build() => ref.read(sharedPrefsProvider).getBool(_k) ?? false;

  Future<void> set(bool on) async {
    state = on;
    await ref.read(sharedPrefsProvider).setBool(_k, on);
  }
}

final convChatOrderProvider = NotifierProvider<ConvChatOrderNotifier, bool>(ConvChatOrderNotifier.new);

/// Листать письма ленты свайпом влево-вправо (1.6.49+95) — по умолчанию
/// включено.
class MailSwipePagerNotifier extends Notifier<bool> {
  static const _k = 'mail_swipe_pager';

  @override
  bool build() => ref.read(sharedPrefsProvider).getBool(_k) ?? true;

  Future<void> set(bool on) async {
    state = on;
    await ref.read(sharedPrefsProvider).setBool(_k, on);
  }
}

final mailSwipePagerProvider = NotifierProvider<MailSwipePagerNotifier, bool>(MailSwipePagerNotifier.new);

/// Кнопки нижней панели письма (1.7.3). Черновику к ним добавляется
/// «Изменить» рядом с «Ответить».
enum MailBarAction { reply, replyAll, forward, later, delete, more }

/// Порядок кнопок под письмом (1.7.3, просьба тестировщиков 25.10.2026):
/// «Ответить» — под большим пальцем, «Удалить» — подальше от системной
/// кнопки «Назад» (у многих телефонов она справа внизу, и письма удаляли
/// случайно). По умолчанию — под правую руку: справа налево «Ответить»,
/// «Ответить всем», «Переслать», «Позже», «Удалить», «Ещё». Левшам —
/// зеркально; можно расставить и по-своему.
class MailBarOrderNotifier extends Notifier<List<MailBarAction>> {
  static const _k = 'mail_bar_order';

  /// Под правую руку (по умолчанию): «Ответить» — справа.
  static const rightHand = [
    MailBarAction.more,
    MailBarAction.delete,
    MailBarAction.later,
    MailBarAction.forward,
    MailBarAction.replyAll,
    MailBarAction.reply,
  ];

  /// Под левую руку: «Ответить» — слева (порядок до 1.7.3).
  static const leftHand = [
    MailBarAction.reply,
    MailBarAction.replyAll,
    MailBarAction.forward,
    MailBarAction.later,
    MailBarAction.delete,
    MailBarAction.more,
  ];

  @override
  List<MailBarAction> build() {
    final raw = ref.read(sharedPrefsProvider).getStringList(_k);
    if (raw == null) return rightHand;
    final out = <MailBarAction>[
      for (final name in raw)
        for (final v in MailBarAction.values)
          if (v.name == name) v,
    ];
    // Сохранённый список без какой-то кнопки (появилась позже) — она в конец.
    for (final v in MailBarAction.values) {
      if (!out.contains(v)) out.add(v);
    }
    return out.toSet().toList();
  }

  Future<void> set(List<MailBarAction> order) async {
    state = List.unmodifiable(order);
    await ref.read(sharedPrefsProvider).setStringList(_k, [for (final v in order) v.name]);
  }

  /// Переставить кнопку (ReorderableListView: [to] — до удаления [from]).
  Future<void> move(int from, int to) async {
    final list = [...state];
    if (to > from) to -= 1;
    final v = list.removeAt(from);
    list.insert(to, v);
    await set(list);
  }

  static bool same(List<MailBarAction> a, List<MailBarAction> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

final mailBarOrderProvider =
    NotifierProvider<MailBarOrderNotifier, List<MailBarAction>>(MailBarOrderNotifier.new);

/// Спрашивать перед удалением письма кнопкой «Удалить» в письме (1.7.3):
/// по умолчанию — да (письма удаляли случайно; «Вернуть» над лентой
/// замечают не все). Свайп в ленте и выбор нескольких писем — без вопроса,
/// как раньше: там «Удалено · Вернуть» видно сразу.
class ConfirmMailDeleteNotifier extends Notifier<bool> {
  static const _k = 'mail_confirm_delete';

  @override
  bool build() => ref.read(sharedPrefsProvider).getBool(_k) ?? true;

  Future<void> set(bool on) async {
    state = on;
    await ref.read(sharedPrefsProvider).setBool(_k, on);
  }
}

final confirmMailDeleteProvider =
    NotifierProvider<ConfirmMailDeleteNotifier, bool>(ConfirmMailDeleteNotifier.new);
