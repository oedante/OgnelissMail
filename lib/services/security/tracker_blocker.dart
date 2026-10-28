// lib/services/security/tracker_blocker.dart
// Блокировка email-трекеров:
// - Удаление шпионских пикселей (до 2×2), скрытых картинок, картинок
//   сервисов отслеживания (по имени хоста)
// - Блокировка внешних изображений по умолчанию
// - Белый список доменов
// - Подсчёт заблокированных трекеров

import '../../core/utils/text_safe.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';

import '../../data/providers/shared_prefs_provider.dart';

/// Провайдер
final trackerBlockerProvider = StateNotifierProvider<TrackerBlockerNotifier, TrackerBlockerState>((ref) {
  final prefs = ref.watch(sharedPrefsProvider);
  return TrackerBlockerNotifier(prefs);
});

class TrackerBlockerState {
  final bool isEnabled;
  final bool blockExternalImages;
  final Set<String> whitelistedDomains;
  final int totalBlocked;
  /// Хост трекера → сколько раз заблокирован. Раньше в настройках было
  /// только общее число — непонятно, что именно блокируется.
  final Map<String, int> byHost;
  /// Последние письма с трекерами (новые первыми, не больше [recentMax]).
  final List<TrackerLogEntry> recent;
  /// Сервисы, которые пользователь разблокировал: их картинки не считаются
  /// трекерами (остальные правила — внешние изображения — действуют).
  final Set<String> allowedHosts;

  const TrackerBlockerState({
    this.isEnabled = true,
    this.blockExternalImages = true,
    this.whitelistedDomains = const {},
    this.totalBlocked = 0,
    this.byHost = const {},
    this.recent = const [],
    this.allowedHosts = const {},
  });

  static const recentMax = 50;

  TrackerBlockerState copyWith({
    bool? isEnabled,
    bool? blockExternalImages,
    Set<String>? whitelistedDomains,
    int? totalBlocked,
    Map<String, int>? byHost,
    List<TrackerLogEntry>? recent,
    Set<String>? allowedHosts,
  }) {
    return TrackerBlockerState(
      isEnabled: isEnabled ?? this.isEnabled,
      blockExternalImages: blockExternalImages ?? this.blockExternalImages,
      whitelistedDomains: whitelistedDomains ?? this.whitelistedDomains,
      totalBlocked: totalBlocked ?? this.totalBlocked,
      byHost: byHost ?? this.byHost,
      recent: recent ?? this.recent,
      allowedHosts: allowedHosts ?? this.allowedHosts,
    );
  }
}

/// Запись журнала блокировок: от кого письмо, тема, какие хосты.
class TrackerLogEntry {
  final String key; // id письма — чтобы повторное открытие не считалось
  final String sender;
  final String subject;
  final List<String> hosts;
  final DateTime at;
  /// Домен отправителя (для «Доверять отправителю») и сколько внешних
  /// изображений скрыто в письме.
  final String senderDomain;
  final int images;
  const TrackerLogEntry({
    required this.key,
    required this.sender,
    required this.subject,
    required this.hosts,
    required this.at,
    this.senderDomain = '',
    this.images = 0,
  });

  Map<String, dynamic> toJson() => {
        'k': key, 's': sender, 'u': subject, 'h': hosts, 'a': at.millisecondsSinceEpoch,
        'd': senderDomain, 'i': images,
      };

  static TrackerLogEntry? fromJson(Object? j) {
    if (j is! Map) return null;
    try {
      return TrackerLogEntry(
        key: j['k'] as String? ?? '',
        sender: j['s'] as String? ?? '',
        subject: j['u'] as String? ?? '',
        hosts: (j['h'] as List?)?.cast<String>() ?? const [],
        at: DateTime.fromMillisecondsSinceEpoch(j['a'] as int? ?? 0),
        senderDomain: j['d'] as String? ?? '',
        images: j['i'] as int? ?? 0,
      );
    } catch (_) {
      return null;
    }
  }
}

class TrackerBlockerNotifier extends StateNotifier<TrackerBlockerState> {
  final SharedPreferences _prefs;
  static const _key = 'tracker_blocker';

  /// Хосты сервисов отслеживания открытий. Сравнение — по ИМЕНИ ХОСТА
  /// картинки (сам домен или его поддомен), а не по подстроке во всём адресе:
  /// прежний список «open.», «click.», «track.», «pixel.», «analytics.»
  /// срабатывал на любые картинки с такими словами в пути (logo-open.png,
  /// /analytics/chart.png) и на легальные изображения рассылок — блокировка
  /// «что-то скрывала, а что — непонятно».
  static const trackerHosts = {
    'mailtrack.io', 'mailtrack.com', 'getnotify.com', 'bananatag.com',
    'yesware.com', 't.yesware.com', 'mailfoogae.appspot.com', 'streak.com',
    'track.hubspot.com', 'hubspotemail.net', 'mixmax.com', 'superhuman.com',
    'pixel.mailchimp.com', 'list-manage.com', 'mandrillapp.com',
    'sendgrid.net', 'ct.sendgrid.net', 'mailgun.org', 'sparkpostmail.com',
    'mailjet.com', 'sendibt3.com', 'sendinblue.com', 'brevo.com',
    'exct.net', 'rs6.net', 'cmail19.com', 'cmail20.com', 'createsend1.com',
    'mkt.com', 'mktoresp.com', 'eloqua.com', 'en25.com', 'pardot.com',
    'google-analytics.com', 'doubleclick.net', 'facebook.com/tr',
    // Российские сервисы рассылок и аналитики
    'mc.yandex.ru', 'unisender.com', 'sendsay.ru', 'mindbox.ru', 'dashamail.ru',
    'esputnik.com', 'mailganer.com', 'notisend.ru', 'sendpulse.com',
  };

  /// Первая метка хоста, характерная для пикселей открытия (open.example.com).
  static const trackerLabels = {'pixel', 'track', 'tracking', 'trk', 'open', 'opens', 'beacon', 'email-tracking'};

  TrackerBlockerNotifier(this._prefs) : super(const TrackerBlockerState()) {
    _load();
  }

  void _load() {
    final json = _prefs.getString(_key);
    if (json != null) {
      try {
        final m = jsonDecode(json) as Map<String, dynamic>;
        state = TrackerBlockerState(
          isEnabled: m['isEnabled'] as bool? ?? true,
          blockExternalImages: m['blockExternalImages'] as bool? ?? true,
          whitelistedDomains: (m['whitelistedDomains'] as List?)?.cast<String>().toSet() ?? {},
          totalBlocked: m['totalBlocked'] as int? ?? 0,
          byHost: (m['byHost'] as Map?)?.map((k, v) => MapEntry('$k', (v as num).toInt())) ?? const {},
          allowedHosts: (m['allowedHosts'] as List?)?.cast<String>().toSet() ?? const {},
          recent: [
            for (final e in (m['recent'] as List? ?? const []))
              if (TrackerLogEntry.fromJson(e) case final t?) t,
          ],
        );
      } catch (_) {}
    }
  }

  Future<void> _save() async {
    await _prefs.setString(_key, jsonEncode({
      'isEnabled': state.isEnabled,
      'blockExternalImages': state.blockExternalImages,
      'whitelistedDomains': state.whitelistedDomains.toList(),
      'totalBlocked': state.totalBlocked,
      'byHost': state.byHost,
      'recent': state.recent.map((e) => e.toJson()).toList(),
      'allowedHosts': state.allowedHosts.toList(),
    }));
  }

  void setEnabled(bool v) { state = state.copyWith(isEnabled: v); _save(); }
  void setBlockExternalImages(bool v) { state = state.copyWith(blockExternalImages: v); _save(); }
  void addWhitelist(String domain) {
    state = state.copyWith(whitelistedDomains: {...state.whitelistedDomains, domain.toLowerCase()});
    _save();
  }
  void removeWhitelist(String domain) {
    state = state.copyWith(whitelistedDomains: state.whitelistedDomains.where((d) => d != domain).toSet());
    _save();
  }

  /// Обработать HTML письма — удалить трекеры
  /// Возвращает (очищенный HTML, количество заблокированных)
  TrackerBlockResult processHtml(String html,
      {String? senderDomain, bool allowExternalImages = false, bool countStats = true}) {
    final r = block(html, options(senderDomain: senderDomain, allowExternalImages: allowExternalImages));
    countBlocked(r, countStats: countStats);
    return r;
  }

  /// Параметры обработки — простые значения, чтобы [block] можно было
  /// выполнить в отдельном изоляте.
  TrackerBlockOptions options({String? senderDomain, bool allowExternalImages = false}) =>
      TrackerBlockOptions(
        enabled: state.isEnabled,
        allowedHosts: state.allowedHosts,
        blockExternal: state.blockExternalImages && !allowExternalImages &&
            !(senderDomain != null && state.whitelistedDomains.contains(senderDomain.toLowerCase())),
      );

  /// Учесть заблокированное в статистике (на главном изоляте).
  void countBlocked(TrackerBlockResult r,
      {bool countStats = true, String? messageKey, String? sender, String? subject, String? senderDomain}) {
    if ((r.blockedCount <= 0 && r.externalBlocked <= 0) || !countStats) return;
    // Повторное открытие того же письма — не новая блокировка.
    if (messageKey != null && state.recent.any((e) => e.key == messageKey)) return;
    final hosts = <String>[
      for (final i in r.items)
        if (i.reason != BlockReason.external) i.host,
    ];
    final byHost = {...state.byHost};
    for (final h in hosts) {
      byHost[h] = (byHost[h] ?? 0) + 1;
    }
    // Не раздуваем настройки: держим 100 самых частых хостов.
    if (byHost.length > 100) {
      final top = byHost.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
      byHost
        ..clear()
        ..addEntries(top.take(100));
    }
    final recent = [
      if (messageKey != null)
        TrackerLogEntry(
          key: messageKey,
          sender: sender ?? '',
          subject: subject ?? '',
          hosts: hosts.toSet().toList(),
          at: DateTime.now(),
          senderDomain: senderDomain ?? '',
          images: r.externalBlocked,
        ),
      ...state.recent,
    ].take(TrackerBlockerState.recentMax).toList();
    state = state.copyWith(
      totalBlocked: state.totalBlocked + r.blockedCount,
      byHost: byHost,
      recent: recent,
    );
    _save();
  }

  /// Разблокировать сервис: его картинки больше не считаются трекерами.
  void allowHost(String host) {
    final h = host.toLowerCase();
    final byHost = {...state.byHost}..remove(h);
    state = state.copyWith(allowedHosts: {...state.allowedHosts, h}, byHost: byHost);
    _save();
  }

  /// Снова блокировать ранее разблокированный сервис.
  void disallowHost(String host) {
    state = state.copyWith(allowedHosts: state.allowedHosts.where((h) => h != host.toLowerCase()).toSet());
    _save();
  }

  /// Убрать сервис из статистики (блокировка остаётся).
  void forgetHost(String host) {
    state = state.copyWith(byHost: {...state.byHost}..remove(host));
    _save();
  }

  /// Убрать письмо из журнала.
  void forgetEntry(String key) {
    state = state.copyWith(recent: state.recent.where((e) => e.key != key).toList());
    _save();
  }

  /// Сбросить статистику и журнал.
  void clearStats() {
    state = state.copyWith(totalBlocked: 0, byHost: const {}, recent: const []);
    _save();
  }

  /// Чистая функция: без состояния и побочных эффектов (для Isolate.run).
  /// Каждый тег <img> разбирается отдельно и получает причину блокировки —
  /// она попадает в журнал и в список «Что заблокировано» на экране письма.
  static TrackerBlockResult block(String html, TrackerBlockOptions o) {
    if (!o.enabled) return TrackerBlockResult(html: html, blockedCount: 0);
    final items = <BlockedImage>[];
    var external = 0;
    final imgRe = RegExp(r'<img\b[^>]*>', caseSensitive: false);
    final processed = html.replaceAllMapped(imgRe, (m) {
      final tag = m.group(0)!;
      final src = _attr(tag, 'src') ?? '';
      final uri = Uri.tryParse(src.trim());
      final host = (uri?.host ?? '').toLowerCase();
      final remote = uri != null && (uri.scheme == 'http' || uri.scheme == 'https') && host.isNotEmpty;

      final allowed = host.isNotEmpty &&
          o.allowedHosts.any((a) => host == a || host.endsWith('.$a'));
      final reason = allowed ? null : _trackerReason(tag, uri, host, remote);
      if (reason != null) {
        items.add(BlockedImage(reason: reason, host: host.isEmpty ? '—' : host, path: _shortPath(uri)));
        return '<!-- blocked: ${reason.name} -->';
      }
      if (remote && o.blockExternal) {
        external++;
        items.add(BlockedImage(reason: BlockReason.external, host: host, path: _shortPath(uri)));
        // Подпись «изображения скрыты» показывает экран письма над текстом.
        return '<span style="background:#f0f0f0;padding:2px 6px;border-radius:4px;">🖼</span>';
      }
      return tag;
    });
    final trackers = items.where((i) => i.reason != BlockReason.external).length;
    return TrackerBlockResult(
      html: processed,
      blockedCount: trackers,
      externalBlocked: external,
      items: items,
    );
  }

  /// Почему картинка — трекер (null — обычная картинка).
  static BlockReason? _trackerReason(String tag, Uri? uri, String host, bool remote) {
    // Скрытая картинка (display:none / visibility:hidden / opacity:0) с адресом
    // в сети — смысла, кроме отслеживания, у неё нет.
    final style = (_attr(tag, 'style') ?? '').toLowerCase().replaceAll(' ', '');
    if (remote &&
        (style.contains('display:none') || style.contains('visibility:hidden') || style.contains('opacity:0;') ||
            style.endsWith('opacity:0'))) {
      return BlockReason.hidden;
    }
    // Пиксель: ширина и высота не больше 2 px (атрибутами или стилем).
    final w = _px(_attr(tag, 'width')) ?? _cssPx(style, 'width');
    final h = _px(_attr(tag, 'height')) ?? _cssPx(style, 'height');
    if (remote && w != null && h != null && w <= 2 && h <= 2) return BlockReason.pixel;
    if (!remote) return null;
    // Известный сервис отслеживания.
    final full = '$host${uri?.path ?? ''}';
    for (final t in trackerHosts) {
      if (t.contains('/')) {
        if (full.startsWith(t) || full.contains('.$t')) return BlockReason.trackerService;
      } else if (host == t || host.endsWith('.$t')) {
        return BlockReason.trackerService;
      }
    }
    final first = host.split('.').first;
    if (trackerLabels.contains(first) && host.split('.').length >= 3) return BlockReason.trackerService;
    return null;
  }

  static String? _attr(String tag, String name) {
    final m = RegExp('(?<![\\w-])$name\\s*=\\s*(?:"([^"]*)"|\'([^\']*)\'|([^\\s>]+))', caseSensitive: false)
        .firstMatch(tag);
    if (m == null) return null;
    return m.group(1) ?? m.group(2) ?? m.group(3);
  }

  static double? _px(String? v) {
    if (v == null) return null;
    return double.tryParse(v.trim().replaceAll('px', ''));
  }

  static double? _cssPx(String style, String prop) {
    final m = RegExp('(?:^|;)$prop:(\\d+(?:\\.\\d+)?)px').firstMatch(style);
    return m == null ? null : double.tryParse(m.group(1)!);
  }

  /// Путь без параметров (в них бывают адрес получателя и метки) и не длиннее 60.
  static String _shortPath(Uri? uri) {
    final p = uri?.path ?? '';
    return p.length > 60 ? '${cutSafe(p, 57)}…' : p;
  }
}

/// Почему картинка заблокирована.
enum BlockReason {
  /// Невидимый пиксель 1×1 (или до 2×2) с адресом в сети.
  pixel,
  /// Скрытая стилем картинка (display:none, visibility:hidden, opacity:0).
  hidden,
  /// Сервис отслеживания открытий (по имени хоста).
  trackerService,
  /// Обычная внешняя картинка — скрыта до «Показать изображения».
  external,
}

class BlockedImage {
  final BlockReason reason;
  final String host;
  final String path;
  const BlockedImage({required this.reason, required this.host, required this.path});
}

/// Сводка для журнала: «pixel: mailtrack.io ×2; trackerService: sendgrid.net».
String describeBlocked(List<BlockedImage> items) {
  final by = <String, int>{};
  for (final i in items) {
    final k = '${i.reason.name}: ${i.host}';
    by[k] = (by[k] ?? 0) + 1;
  }
  return by.entries.map((e) => e.value > 1 ? '${e.key} ×${e.value}' : e.key).join('; ');
}

class TrackerBlockOptions {
  final bool enabled;
  final bool blockExternal;
  /// Разблокированные пользователем сервисы (по имени хоста или домену).
  final Set<String> allowedHosts;
  const TrackerBlockOptions({required this.enabled, required this.blockExternal, this.allowedHosts = const {}});
}

class TrackerBlockResult {
  final String html;
  /// Сколько ТРЕКЕРОВ заблокировано (пиксели, скрытые картинки, сервисы
  /// отслеживания). Внешние картинки сюда больше не входят — раньше счётчик
  /// «заблокировано трекеров» рос от каждой картинки рассылки.
  final int blockedCount;
  /// Сколько внешних изображений скрыто (для кнопки «Показать»).
  final int externalBlocked;
  /// Что именно заблокировано — для журнала и экрана письма.
  final List<BlockedImage> items;
  const TrackerBlockResult({
    required this.html,
    required this.blockedCount,
    this.externalBlocked = 0,
    this.items = const [],
  });
}
