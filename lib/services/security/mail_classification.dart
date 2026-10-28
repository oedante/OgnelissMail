// lib/services/security/mail_classification.dart
//
// 1.5.9 (12.10.2026): гриф письма убран из приложения по решению владельца —
// пользователям мешал. Нет ни выбора грифа (письмо, редактор), ни меток в
// ленте, ни скрытого предпросмотра, входа по отпечатку, запрета снимков и
// запрета пересылки. Здесь остался разбор строки «sensitivity» (MailLabel):
// в ней едут отметки S/MIME при отправке и пометка Outlook при приёме.
// Описание ниже — как было до 1.5.9 (код грифа удалён в 1.6.1, он в истории
// git — версия 1.5.12).
// Локальная классификация писем (гриф): ДСП, конфиденциально, коммерческая
// тайна, персональные данные, для внутреннего использования, публично.
//
// Откуда берётся гриф письма (по убыванию силы):
//   1. выбран вручную в письме («Ещё» → «Гриф») — хранится только на
//      телефоне (emails.classification);
//   1а. заголовок письма X-Ogneliss-Classification (гриф в MIME, ставит
//      Ogneliss Mail отправителя; с ним же — режим «не пересылать» /
//      «только внутри организации», см. [MailLabel]);
//   2. по теме: «[ДСП]», «Для служебного пользования», «Конфиденциально»,
//      «Коммерческая тайна», «Персональные данные»/«ПДн», «Для внутреннего
//      использования» (и английские варианты) — так гриф ставят в
//      организациях, и он виден в любом клиенте;
//   3. метка Outlook «Конфиденциальность» (Sensitivity: Private /
//      Company-Confidential).
//
// Защищённые грифы (ДСП, коммерческая тайна, конфиденциально, ПДн) меняют
// поведение клиента (каждое — переключатель в настройках):
//   · предпросмотр скрыт — в ленте, уведомлениях и виджетах;
//   · открыть письмо — только после отпечатка, лица или кода телефона;
//   · пока письмо открыто — запрет снимков и записи экрана, показа на
//     внешнем экране и миниатюры в «Недавних» (Android FLAG_SECURE);
//   · вложения удаляются с телефона, когда письмо закрыли.
// Это не замена DLP или Microsoft Purview, а защита от случайной утечки:
// уведомление на экране блокировки, снимок экрана, демонстрация экрана.


import '../../data/models/account_model.dart';
import '../mail/own_addresses.dart';
import '../../l10n/app_localizations.dart';

/// Гриф письма. Порядок — по строгости (больше индекс — строже).
enum MailClass { none, public, internal, personalData, confidential, tradeSecret, dsp }


/// Гриф внутри письма (11.10.2026): гриф и режим обращения передаются
/// заголовками MIME, а не только меткой в теме.
///
///   X-Ogneliss-Classification: dsp | tradeSecret | confidential | personalData | internal | public
///   X-Ogneliss-Handling: no-forward, internal-only
///
/// Метка в теме («[ДСП] …») и пометка Outlook (Sensitivity) остаются — их
/// видит любой почтовый клиент. Заголовки читает Ogneliss Mail у получателя:
/// точный гриф (даже если тему переписали или она на другом языке) и
/// ограничения — «не пересылать» (пересылка письма отключена) и «только
/// внутри организации» (ответ и пересылка — только на адреса домена
/// отправителя или своего ящика). Это договорённость клиентов, а не DRM:
/// другие программы заголовки не соблюдают.
///
/// Чтобы не менять схему базы и цепочку отправки (очередь, отложенная
/// отправка, три протокола), метка едет в строке «sensitivity» — и в базе
/// (emails.sensitivity), и в параметрах отправки:
///   «Confidential|dsp|no-forward,internal-only»; без грифа и ограничений —
///   просто «Normal»/«Confidential», как раньше.
class MailLabel {
  /// Пометка Outlook: Normal / Personal / Private / Confidential.
  final String outlook;
  final MailClass cls;
  final bool noForward;
  final bool internalOnly;

  /// S/MIME при отправке: подписать / зашифровать (только для исходящего
  /// письма — едет в «sensitivity» через очередь и транспорт, как гриф;
  /// четвёртая часть строки: «Normal|||sign,encrypt»). В заголовки письма
  /// и в базу не попадает.
  final bool smimeSign;
  final bool smimeEncrypt;
  const MailLabel({
    this.outlook = 'Normal',
    this.cls = MailClass.none,
    this.noForward = false,
    this.internalOnly = false,
    this.smimeSign = false,
    this.smimeEncrypt = false,
  });

  bool get smime => smimeSign || smimeEncrypt;

  /// Та же метка с отметками S/MIME.
  MailLabel withSmime({required bool sign, required bool encrypt}) => MailLabel(
        outlook: outlook,
        cls: cls,
        noForward: noForward,
        internalOnly: internalOnly,
        smimeSign: sign,
        smimeEncrypt: encrypt,
      );

  static const headerClass = 'X-Ogneliss-Classification';
  static const headerHandling = 'X-Ogneliss-Handling';

  bool get hasExtras => cls != MailClass.none || noForward || internalOnly;
  bool get restricted => noForward || internalOnly;

  String get handling => [if (noForward) 'no-forward', if (internalOnly) 'internal-only'].join(',');

  String encode() {
    final smimeTokens = [if (smimeSign) 'sign', if (smimeEncrypt) 'encrypt'].join(',');
    if (smimeTokens.isNotEmpty) return '$outlook|${cls == MailClass.none ? '' : cls.name}|$handling|$smimeTokens';
    return hasExtras ? '$outlook|${cls == MailClass.none ? '' : cls.name}|$handling' : outlook;
  }

  static MailClass _cls(String? v) {
    final s = (v ?? '').trim().toLowerCase();
    if (s.isEmpty) return MailClass.none;
    return MailClass.values.where((c) => c.name.toLowerCase() == s).firstOrNull ?? MailClass.none;
  }

  /// «Company-Confidential» (заголовок) / «Confidential» (EWS) → Confidential.
  static String normalizeOutlook(String? v) {
    final s = (v ?? '').trim().toLowerCase();
    if (s.contains('confidential')) return 'Confidential';
    if (s == 'private') return 'Private';
    if (s == 'personal') return 'Personal';
    return 'Normal';
  }

  static MailLabel decode(String? s) {
    if (s == null || s.trim().isEmpty) return const MailLabel();
    final p = s.split('|');
    final h = p.length > 2 ? p[2].toLowerCase() : '';
    final sm = p.length > 3 ? p[3].toLowerCase() : '';
    return MailLabel(
      outlook: normalizeOutlook(p[0]),
      cls: p.length > 1 ? _cls(p[1]) : MailClass.none,
      noForward: h.contains('no-forward'),
      internalOnly: h.contains('internal-only'),
      smimeSign: sm.contains('sign'),
      smimeEncrypt: sm.contains('encrypt'),
    );
  }

  /// Значение для emails.sensitivity из заголовков полученного письма.
  /// null — нечего сохранять (ни пометки Outlook, ни заголовков Ogneliss).
  static String? fromHeaders({String? sensitivity, String? classification, String? handling}) {
    final h = (handling ?? '').toLowerCase();
    final l = MailLabel(
      outlook: normalizeOutlook(sensitivity),
      cls: _cls(classification),
      noForward: h.contains('no-forward'),
      internalOnly: h.contains('internal-only'),
    );
    if (!l.hasExtras && (sensitivity == null || sensitivity.trim().isEmpty)) return null;
    return l.encode();
  }

  /// Обновление письма с сервера: список писем (FindItem, Sync) заголовков
  /// не несёт — гриф из заголовков, прочитанный при открытии, не теряется.
  static String? merge(String? server, String? local) {
    final s = decode(server);
    if (s.hasExtras) return server;
    final l = decode(local);
    if (!l.hasExtras) return server ?? local;
    return MailLabel(
      outlook: (server == null || server.isEmpty) ? l.outlook : s.outlook,
      cls: l.cls,
      noForward: l.noForward,
      internalOnly: l.internalOnly,
    ).encode();
  }

  /// Пересылка письма запрещена отправителем («не пересылать»): чужое
  /// письмо с этой пометкой не пересылается — кнопки «Переслать» в карточке
  /// и в меню неактивны (раньше запрет срабатывал только в редакторе).
  /// Своё письмо (отправитель — адрес ящика) переслать можно.
  static bool forwardBlocked(String? sensitivity, String? fromEmail, AccountModel? account) {
    if (!decode(sensitivity).noForward) return false;
    if (account != null && OwnAddresses.isMine(account, fromEmail)) return false;
    return true;
  }

  /// Заголовки для исходящего письма.
  Map<String, String> get headers => {
        if (cls != MailClass.none) headerClass: cls.name,
        if (handling.isNotEmpty) headerHandling: handling,
      };

  /// Подписи ограничений для карточки письма.
  List<String> handlingLabels(AppLocalizations l10n) => [
        if (noForward) l10n.tr('classNoForward'),
        if (internalOnly) l10n.tr('classInternalOnly'),
      ];

  /// Домен адреса (нижний регистр); '' — не адрес.
  static String domainOf(String email) {
    final at = email.lastIndexOf('@');
    return at < 0 ? '' : email.substring(at + 1).trim().toLowerCase();
  }

  /// Адреса за пределами разрешённых доменов (режим «только внутри организации»).
  static List<String> outside(Iterable<String> emails, Set<String> allowedDomains) => [
        for (final e in emails)
          if (allowedDomains.isNotEmpty && !allowedDomains.contains(domainOf(e))) e,
      ];
}

