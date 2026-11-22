// lib/services/mail/mail_tags.dart
// Поля {в фигурных скобках} в подписях и приветствиях — один набор на все
// конструкторы (просьба владельца 18.11.2026: «пользователи просят
// настраиваемые приветствия с поддержкой {тэгов}; в конструкторе подписи и
// приветствия — набор таких тэгов»).
//
// У каждого поля два написания: английское — как в подписях раньше
// ({name}, {title}, {phone}…), и русское ({имя}, {должность}, {телефон}…).
// Работают оба, в любом регистре. Кнопки конструктора вставляют русское
// написание, если приложение на русском, иначе английское.
//
// Группы:
//   адресат   — {обращение} («Иван Петрович», как в стандартном
//               приветствии; несколько адресатов — через запятую, больше
//               трёх коллег — «коллеги»), {имя_адресата}, {фамилия_адресата},
//               {фио_адресата};
//   время     — {время_суток} («Доброе утро» / «Добрый день» / «Добрый
//               вечер» по часам отправки), {дата}, {время};
//   отправитель (вы) — {имя}, {должность}, {отдел}, {компания}, {телефон},
//               {почта} — из настроек ящика и карточки в адресной книге
//               организации, как в подписях раньше.
// Поле без значения пропадает вместе с лишней запятой: «Здравствуйте,
// {обращение}!» без имени адресата — «Здравствуйте!».

import '../../core/utils/greeting_helper.dart';
import '../../core/utils/person_name_parts.dart';
import '../../l10n/strings_store.dart';

enum MailTagGroup { recipient, time, sender }

class MailTag {
  /// Английское написание (как в подписях раньше).
  final String key;

  /// Русское написание.
  final String ru;

  final MailTagGroup group;

  /// Ключ строки с подписью кнопки.
  final String label;

  const MailTag(this.key, this.ru, this.group, this.label);

  /// Что вставляет кнопка конструктора.
  String insertText(String localeCode) => '{${localeCode.toLowerCase().startsWith('ru') ? ru : key}}';
}

/// Значения полей для одной подстановки. null — поле неизвестно
/// (например, адресата нет в подписи): тогда оно пропадает.
class MailTagValues {
  final Map<String, String> _byKey;
  const MailTagValues._(this._byKey);

  /// [anyTime] — {время_суток} всеми вариантами («Доброе утро/день/вечер»):
  /// подпись шаблона в меню, а не значение на сейчас (21.11.2026).
  factory MailTagValues({
    Map<String, String> sender = const {},
    Map<String, String> recipient = const {},
    DateTime? now,
    String? lang,
    bool anyTime = false,
  }) {
    final t = now ?? DateTime.now();
    String two(int n) => n.toString().padLeft(2, '0');
    return MailTagValues._({
      ...sender,
      ...recipient,
      'date': '${two(t.day)}.${two(t.month)}.${t.year}',
      'time': '${two(t.hour)}:${two(t.minute)}',
      'part_of_day': anyTime ? MailTags.partOfDayAll(lang ?? 'ru') : MailTags.partOfDay(lang ?? 'ru', t),
    });
  }

  String? operator [](String key) => _byKey[key];
}

abstract final class MailTags {
  static const all = <MailTag>[
    MailTag('to_address', 'обращение', MailTagGroup.recipient, 'tagToAddress'),
    MailTag('to_first_name', 'имя_адресата', MailTagGroup.recipient, 'tagToFirst'),
    MailTag('to_last_name', 'фамилия_адресата', MailTagGroup.recipient, 'tagToLast'),
    MailTag('to_full_name', 'фио_адресата', MailTagGroup.recipient, 'tagToFull'),
    MailTag('part_of_day', 'время_суток', MailTagGroup.time, 'tagPartOfDay'),
    MailTag('date', 'дата', MailTagGroup.time, 'tagDate'),
    MailTag('time', 'время', MailTagGroup.time, 'tagTime'),
    MailTag('name', 'имя', MailTagGroup.sender, 'tagMyName'),
    MailTag('title', 'должность', MailTagGroup.sender, 'tagMyTitle'),
    MailTag('department', 'отдел', MailTagGroup.sender, 'tagMyDepartment'),
    MailTag('company', 'компания', MailTagGroup.sender, 'tagMyCompany'),
    MailTag('phone', 'телефон', MailTagGroup.sender, 'tagMyPhone'),
    MailTag('email', 'почта', MailTagGroup.sender, 'tagMyEmail'),
  ];

  /// Кнопки конструктора приветствия: первым — «Доброе утро / Добрый день /
  /// Добрый вечер» (меняется по времени суток), затем адресат, дата и вы.
  static List<MailTag> get forGreeting => [
        for (final t in all) if (t.key == 'part_of_day') t,
        for (final t in all) if (t.key != 'part_of_day') t,
      ];

  /// Кнопки конструктора подписи: вы и дата (адресата подпись не знает).
  static List<MailTag> get forSignature => [
        for (final t in all)
          if (t.group == MailTagGroup.sender || t.key == 'date') t,
      ];

  /// Старые и запасные написания: {фио} и {fullname} — ваше имя, как в
  /// шаблонах ответов.
  static const _aliases = {'фио': 'name', 'fullname': 'name', 'организация': 'company'};

  static final Map<String, String> _canon = {
    for (final t in all) ...{t.key: t.key, t.ru: t.key},
    ..._aliases,
  };

  static final _tagRe = RegExp(r'\{([A-Za-zА-Яа-яЁё_]+)\}');

  /// Подставить поля в [text]. [html] — значения экранируются. Неизвестные
  /// и пустые поля пропадают; [cleanup] — убрать оставшиеся от них
  /// запятые и пробелы (приветствие — одна строка).
  static String apply(String text, MailTagValues values, {bool html = false, bool cleanup = false}) {
    var out = text.replaceAllMapped(_tagRe, (m) {
      final key = _canon[m.group(1)!.toLowerCase()];
      final v = key == null ? '' : (values[key] ?? '');
      return html ? _esc(v) : v;
    });
    if (cleanup) {
      out = tidy(out);
      // Строка начиналась с поля: «{обращение}, добрый день!» → «Добрый
      // день!» без имени, «Коллеги, добрый день!» с ним.
      if (text.trimLeft().startsWith('{') && out.isNotEmpty) {
        out = out[0].toUpperCase() + out.substring(1);
      }
    }
    return out;
  }

  /// Есть ли в тексте поля.
  static bool hasTags(String text) => _tagRe.hasMatch(text);

  /// Строка после подстановки без лишних пробелов и запятых:
  /// «Здравствуйте, !» → «Здравствуйте!», «, коллеги» → «коллеги».
  /// Знаки — и китайские, японские, арабские (21.11.2026: «おはようございます、！»
  /// без имени).
  static String tidy(String s) {
    final lines = [
      for (final line in s.split('\n'))
        line
            .replaceAll(RegExp(r'[ \t]+'), ' ')
            .replaceAllMapped(RegExp(r'[ \t]+([,.!?;:，、。！？；：،؟])'), (m) => m.group(1)!)
            .replaceAllMapped(RegExp(r'([,，、،])(\s*[,，、،])+'), (m) => m.group(1)!)
            .replaceAll(RegExp(r'[,，、،](?=[!?.;:。！？；：؟])'), '')
            .replaceFirst(RegExp(r'^\s*[,;:，、；：،]\s*'), '')
            .trim(),
    ];
    // Пустые строки по краям — от полей без значения.
    while (lines.isNotEmpty && lines.first.isEmpty) {
      lines.removeAt(0);
    }
    while (lines.isNotEmpty && lines.last.isEmpty) {
      lines.removeLast();
    }
    return lines.join('\n');
  }

  static String _esc(String s) =>
      s.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;').replaceAll('"', '&quot;');

  /// Все варианты времени суток одной строкой: «Доброе утро/Добрый
  /// день/Добрый вечер» (21.11.2026, как просил владелец), [sep] — между
  /// ними; языки без пробелов между словами — всегда « / ».
  static String partOfDayAll(String lang, {String sep = '/'}) {
    String s(String k) => StringsStore.get(lang, k) ?? StringsStore.get('en', k) ?? '';
    final parts = [s('greetPartMorning'), s('greetPartDay'), s('greetPartEvening')].where((p) => p.isNotEmpty);
    return parts.join(parts.every((p) => p.contains(' ')) ? sep : ' / ');
  }

  /// «Доброе утро» (5–11 ч), «Добрый день» (12–17), «Добрый вечер» (18–4)
  /// на языке [lang].
  static String partOfDay(String lang, DateTime now) {
    final key = GreetingHelper.partOfDayKey(now);
    return StringsStore.get(lang, key) ?? StringsStore.get('en', key) ?? '';
  }

  /// Поля адресата для адресатов «Кому»: [names] — имена (пустая строка —
  /// имени нет), [emails] — адреса. Обращение — как в стандартном
  /// приветствии ([GreetingHelper.addressOf]); у нескольких адресатов — через
  /// запятую (до трёх), больше трёх коллег — «коллеги».
  static Map<String, String> recipient({
    required List<String> names,
    required List<String> emails,
    required String lang,
    Set<String> ownDomains = const {},
  }) {
    final clean = [for (final n in names) GreetingHelper.cleanName(n)];
    final count = emails.length > clean.length ? emails.length : clean.length;
    if (count == 0) return const {};
    if (count == 1) {
      final n = clean.isEmpty ? '' : clean.first;
      final p = PersonNameParts.parse(n, locale: lang);
      return {
        'to_address': GreetingHelper.addressOf(n, lang: lang),
        'to_first_name': p?.given ?? '',
        'to_last_name': p?.family ?? '',
        'to_full_name': p?.full ?? n,
      };
    }
    final addresses = [
      for (final n in clean)
        if (GreetingHelper.addressOf(n, lang: lang).isNotEmpty) GreetingHelper.addressOf(n, lang: lang),
    ];
    String address;
    if (count <= 3 && addresses.length == count) {
      address = addresses.join(', ');
    } else if (GreetingHelper.allInternal(emails, ownDomains) && ownDomains.isNotEmpty) {
      address = StringsStore.get(lang, 'greetTagColleagues') ?? StringsStore.get('en', 'greetTagColleagues') ?? '';
    } else {
      address = '';
    }
    return {'to_address': address};
  }

  /// Поля отправителя: имя из настроек ящика (если это не логин и не адрес),
  /// иначе из карточки в адресной книге организации [card]; должность,
  /// отдел, компания и телефон — из карточки.
  static Map<String, String> sender({
    required String displayName,
    required String email,
    Map<String, String> card = const {},
  }) {
    final own = displayName.trim();
    final ownIsReal = own.isNotEmpty &&
        own.toLowerCase() != email.toLowerCase() &&
        own.toLowerCase() != email.split('@').first.toLowerCase();
    return {
      'name': ownIsReal ? own : (card['name'] ?? own),
      'title': card['title'] ?? '',
      'department': card['office'] ?? '',
      'company': card['company'] ?? '',
      'phone': card['phone'] ?? card['mobile'] ?? '',
      'email': email,
    };
  }

  /// Образец адресата для предпросмотра в настройках.
  static Map<String, String> sampleRecipient(String lang) {
    final cyr = const {'ru', 'uk', 'bg'}.contains(lang);
    return cyr
        ? const {
            'to_address': 'Иван Петрович',
            'to_first_name': 'Иван',
            'to_last_name': 'Сидоров',
            'to_full_name': 'Сидоров Иван Петрович',
          }
        : const {
            'to_address': 'John',
            'to_first_name': 'John',
            'to_last_name': 'Smith',
            'to_full_name': 'John Smith',
          };
  }
}
