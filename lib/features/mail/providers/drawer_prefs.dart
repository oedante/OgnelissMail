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
/// calendar, contacts — «Календарь» и «Контакты» (2.2.0, просьба
/// пользователя 10.11.2026: раздел, убранный с нижней панели, — в
/// «Избранном»); по умолчанию скрыты, пока их не включат или не уберут с
/// панели.
enum DrawerQuickItem { allAccounts, allMail, unread, flagged, vip, attachments, fileHub, notes, tasks, control, later, triage, myDay, settings, theme, assignments, calendar, contacts }

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
const _optIn = {DrawerQuickItem.triage, DrawerQuickItem.calendar, DrawerQuickItem.contacts};
const _kOptInOn = 'drawer_quick_on_';

const _defaultHidden = {
  DrawerQuickItem.triage,
  DrawerQuickItem.calendar,
  DrawerQuickItem.contacts,
  DrawerQuickItem.unread,
  DrawerQuickItem.flagged,
  DrawerQuickItem.vip,
  DrawerQuickItem.attachments,
};

final hiddenQuickItemsProvider =
    NotifierProvider<HiddenQuickItemsNotifier, Set<DrawerQuickItem>>(
        HiddenQuickItemsNotifier.new);

/// Плитки «Избранного» (1.10.2, просьба владельца: «панелями в стиле пуска
/// Windows 10»): ключи пунктов, показанных только значком; остальные — значок
/// с подписью. Ключ — DrawerQuickItem.name, «group:<id>» или
/// «folder:<ящик>/<папка>».
class FavoriteIconOnlyNotifier extends Notifier<Set<String>> {
  static const _k = 'drawer_fav_icon_only';

  @override
  Set<String> build() => (ref.read(sharedPrefsProvider).getStringList(_k) ?? const []).toSet();

  static String folderKey(String accountId, String folderId) => 'folder:$accountId/$folderId';
  static String groupKey(String id) => 'group:$id';

  Future<void> set(String key, bool iconOnly) async {
    final next = {...state};
    iconOnly ? next.add(key) : next.remove(key);
    state = next;
    await ref.read(sharedPrefsProvider).setStringList(_k, next.toList());
  }
}

final favoriteIconOnlyProvider =
    NotifierProvider<FavoriteIconOnlyNotifier, Set<String>>(FavoriteIconOnlyNotifier.new);

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

  /// Сторона меню; портрет «Меню» на нижней панели — с края этой стороны
  /// (phoneBarProvider следит сам).
  Future<void> set(bool right) async {
    state = right;
    await ref.read(sharedPrefsProvider).setBool(_k, right);
  }
}

final menuOnRightProvider = NotifierProvider<MenuOnRightNotifier, bool>(MenuOnRightNotifier.new);

/// Разделы нижней панели телефона (2.2.0, просьба пользователя 10.11.2026:
/// «контакты редко нужны — в избранное, а „Мой день“ — в нижний бар»).
/// Четыре места — по два слева и справа от кнопки «Создать», она всегда в
/// центре. «Почта» и «Меню» на панели всегда (решение владельца 10.11.2026):
/// «Почту» можно поставить на любое место, «Меню» — только с края, слева
/// или справа, с той же стороны выезжает меню (настройка «Общие → Меню
/// ящиков и папок», menuOnRightProvider).
enum BarItem { mail, calendar, contacts, tasks, myDay, notes, assignments, files, menu }

/// Пункт «Избранного» того же раздела (у почты и меню — нет).
DrawerQuickItem? quickItemOf(BarItem i) => switch (i) {
      BarItem.calendar => DrawerQuickItem.calendar,
      BarItem.contacts => DrawerQuickItem.contacts,
      BarItem.tasks => DrawerQuickItem.tasks,
      BarItem.myDay => DrawerQuickItem.myDay,
      BarItem.notes => DrawerQuickItem.notes,
      BarItem.assignments => DrawerQuickItem.assignments,
      BarItem.files => DrawerQuickItem.fileHub,
      BarItem.mail || BarItem.menu => null,
    };

/// Порядок разделов на панели: «Меню» с края по стороне меню и три места
/// рядом. Хранятся только три места (без «Меню»); пока пользователь панель
/// не менял — как раньше: «Почта · Календарь · Контакты».
class PhoneBarNotifier extends Notifier<List<BarItem>> {
  static const prefKey = 'phone_bar';
  static const slots = 4;
  static const defaultRest = [BarItem.mail, BarItem.calendar, BarItem.contacts];

  /// Вся панель: три места [rest] и «Меню» с края.
  static List<BarItem> compose(List<BarItem> rest, {required bool menuOnRight}) =>
      List.unmodifiable(menuOnRight ? [...rest, BarItem.menu] : [BarItem.menu, ...rest]);

  static List<BarItem> defaults({required bool menuOnRight}) => compose(defaultRest, menuOnRight: menuOnRight);

  /// Сохранённые три места: разные разделы, среди них «Почта»; «Меню» из
  /// записи (её первого вида, где оно было одним из четырёх) — убирается.
  /// Иначе null.
  static List<BarItem>? parse(List<String>? raw) {
    if (raw == null) return null;
    final out = <BarItem>[];
    for (final name in raw) {
      final v = BarItem.values.where((e) => e.name == name).firstOrNull;
      if (v == null || out.contains(v)) return null;
      if (v != BarItem.menu) out.add(v);
    }
    if (out.length != slots - 1 || !out.contains(BarItem.mail)) return null;
    return List.unmodifiable(out);
  }

  /// Что показать: раздел, выключенный в «Профиле» (задачи, заметки, файлы,
  /// «Мой день»), заменяется первым доступным, которого на панели нет.
  /// Сохранённый порядок не меняется — включил раздел снова, и он на месте.
  static List<BarItem> visible(List<BarItem> bar, bool Function(BarItem) available) {
    const spare = [
      BarItem.mail, BarItem.calendar, BarItem.contacts, BarItem.tasks, BarItem.myDay, BarItem.notes,
      BarItem.assignments, BarItem.files,
    ];
    final out = [...bar];
    for (var i = 0; i < out.length; i++) {
      if (out[i] == BarItem.menu || out[i] == BarItem.mail || available(out[i])) continue;
      final sub = spare.where((s) => available(s) && !out.contains(s)).firstOrNull;
      if (sub != null) out[i] = sub;
    }
    return out;
  }

  bool get customized => ref.read(sharedPrefsProvider).getStringList(prefKey) != null;

  /// Раздел, который нельзя убрать с панели, — только переставить.
  static bool fixed(BarItem i) => i == BarItem.mail || i == BarItem.menu;

  @override
  List<BarItem> build() => compose(
        parse(ref.read(sharedPrefsProvider).getStringList(prefKey)) ?? defaultRest,
        menuOnRight: ref.watch(menuOnRightProvider),
      );

  /// [item] — на место [slot]. Место «Меню» не меняется (его сторона — в
  /// menuOnRightProvider). Раздел, который уже на панели, меняется местами с
  /// прежним; «Почту» можно только переставить. Возвращает раздел, ушедший с
  /// панели, или null.
  Future<BarItem?> place(int slot, BarItem item) async {
    final old = state[slot];
    if (old == item || old == BarItem.menu || item == BarItem.menu) return null;
    final rest = [for (final v in state) if (v != BarItem.menu) v];
    final i = rest.indexOf(old);
    final at = rest.indexOf(item);
    if (at >= 0) {
      rest[at] = old;
      rest[i] = item;
      await _save(rest);
      return null;
    }
    if (old == BarItem.mail) return null;
    rest[i] = item;
    await _save(rest);
    // Убранный раздел — в «Избранное», чтобы не потерять к нему дорогу.
    final quick = quickItemOf(old);
    if (quick != null && ref.read(hiddenQuickItemsProvider).contains(quick)) {
      await ref.read(hiddenQuickItemsProvider.notifier).setVisible(quick, true);
    }
    return old;
  }

  /// Как по умолчанию.
  Future<void> reset() async {
    await ref.read(sharedPrefsProvider).remove(prefKey);
    state = defaults(menuOnRight: ref.read(menuOnRightProvider));
  }

  Future<void> _save(List<BarItem> rest) async {
    state = compose(rest, menuOnRight: ref.read(menuOnRightProvider));
    await ref.read(sharedPrefsProvider).setStringList(prefKey, [for (final v in rest) v.name]);
  }
}

final phoneBarProvider = NotifierProvider<PhoneBarNotifier, List<BarItem>>(PhoneBarNotifier.new);

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

/// Порядок плиток «Избранного» (1.10.5, просьба владельца 03.11.2026:
/// «возможность менять порядок пунктов»): ключи плиток в нужном порядке
/// (те же, что у [FavoriteIconOnlyNotifier]). Плитки, которых в списке нет
/// (новые), — после упорядоченных, в обычном порядке.
class FavoriteOrderNotifier extends Notifier<List<String>> {
  static const _k = 'drawer_fav_order';

  @override
  List<String> build() => ref.read(sharedPrefsProvider).getStringList(_k) ?? const [];

  Future<void> set(List<String> keys) async {
    state = List.unmodifiable(keys);
    await ref.read(sharedPrefsProvider).setStringList(_k, keys);
  }

  Future<void> reset() async {
    state = const [];
    await ref.read(sharedPrefsProvider).remove(_k);
  }
}

final favoriteOrderProvider =
    NotifierProvider<FavoriteOrderNotifier, List<String>>(FavoriteOrderNotifier.new);

/// [items] в порядке [order] (по ключу [key]); не упомянутые — следом, в
/// прежнем порядке.
List<T> orderFavorites<T>(List<T> items, String Function(T) key, List<String> order) {
  if (order.isEmpty) return items;
  final pos = {for (final (i, k) in order.indexed) k: i};
  final indexed = [for (final (i, t) in items.indexed) (i, t)];
  indexed.sort((a, b) {
    final pa = pos[key(a.$2)] ?? order.length + a.$1;
    final pb = pos[key(b.$2)] ?? order.length + b.$1;
    return pa.compareTo(pb);
  });
  return [for (final e in indexed) e.$2];
}

