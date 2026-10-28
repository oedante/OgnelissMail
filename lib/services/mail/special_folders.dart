// lib/services/mail/special_folders.dart
// Папки «Архив» и «Спам» ящика (1.7.2+106, просьба владельца 24.10.2026:
// «В архив» не работала, кнопки «В спам» не было).
//
// ActiveSync таких типов не знает: «Архив» и «Нежелательная почта» Exchange
// приходят обычными папками писем (тип 12), и приложение их не находило —
// «Папка «Архив» не найдена», а письма из «Нежелательной почты» попадали во
// «Всю почту» и в уведомления. EWS и IMAP без SPECIAL-USE (\Archive, \Junk) —
// так же. Имена зависят от языка ящика: язык выбирается при первом входе в
// Outlook или OWA и потом сам не меняется («Junk Email», «Нежелательная
// почта», «Junk-E-Mail», «Courrier indésirable»…). Поэтому:
//  · тип, который дал сервер, — главный; по названию распознаём, только если
//    такой папки сервер не указал, и только папки верхнего уровня (или прямо
//    во «Входящих» — так их кладут некоторые IMAP-серверы);
//  · названия — на распространённых языках, без учёта регистра, пробелов,
//    дефисов и диакритики;
//  · ручной выбор («Настройки → ящик → Папка «Архив» / «Спам»», как в Nine и
//    OfficeMail) сильнее всего: выбранная папка получает тип, у прежней тип
//    снимается. Хранится в SharedPreferences — его читает и фоновая проверка.
//
// Применяется при каждом сохранении списка папок с сервера
// (SyncService._batchSaveFolders) и сразу к базе при выборе в настройках
// ([reapplyStored]): ActiveSync запрашивает список папок раз в час.

import 'package:drift/drift.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/logging/app_logger.dart';
import '../../data/database/app_database.dart';
import '../../data/models/folder_model.dart';
import '../../features/mail/providers/mail_providers.dart' show folderFromRow;

/// Какая из двух особых папок.
enum SpecialKind {
  archive,
  junk;

  FolderType get type => this == SpecialKind.archive ? FolderType.archive : FolderType.junk;
}

class SpecialFolders {
  SpecialFolders._();

  static String _key(String accountId, SpecialKind k) => 'special_folder_${k.name}_$accountId';

  /// Папка, выбранная вручную (её id), или null — «автоматически».
  static String? chosen(SharedPreferences p, String accountId, SpecialKind k) {
    final v = p.getString(_key(accountId, k));
    return (v == null || v.isEmpty) ? null : v;
  }

  /// Выбрать папку вручную ([folderId]) или вернуть «автоматически» (null).
  static Future<void> setChosen(SharedPreferences p, String accountId, SpecialKind k, String? folderId) async {
    if (folderId == null || folderId.isEmpty) {
      await p.remove(_key(accountId, k));
    } else {
      await p.setString(_key(accountId, k), folderId);
    }
  }

  /// Выбор в настройках ящика: запомнить и сразу применить к базе.
  ///
  /// Прежней выбранной вручную папке сначала возвращается обычный тип: в
  /// базе не видно, кто дал папке тип — сервер или выбор, а сервер такие
  /// папки не помечал (иначе выбирать вручную было бы незачем). Дальше решает
  /// новый выбор или распознавание по названию. Тип от сервера (IMAP
  /// \Archive, \Junk) вернётся при ближайшем обновлении списка папок.
  static Future<void> choose(
      AppDatabase db, SharedPreferences p, String accountId, SpecialKind k, String? folderId) async {
    final old = chosen(p, accountId, k);
    await setChosen(p, accountId, k, folderId);
    if (old != null && old != folderId) {
      final row = await (db.select(db.folders)
            ..where((f) => f.id.equals(old) & f.accountId.equals(accountId) & f.type.equals(k.type.index)))
          .getSingleOrNull();
      if (row != null) {
        final plain = _retype(folderFromRow(row), FolderType.custom);
        await (db.update(db.folders)..where((f) => f.id.equals(old) & f.accountId.equals(accountId)))
            .write(FoldersCompanion(type: Value(plain.type.index), showInUnified: Value(plain.showInUnified)));
      }
    }
    await reapplyStored(db, p, accountId);
    AppLogger.info('Папка для ${k == SpecialKind.archive ? 'архива' : 'спама'}: '
        '${folderId == null ? 'автоматически' : 'выбрана вручную'}');
  }

  /// Ящик удалён — его выбор забыть.
  static Future<void> forgetAccount(SharedPreferences p, String accountId) async {
    for (final k in SpecialKind.values) {
      await p.remove(_key(accountId, k));
    }
  }

  // ── Названия ──

  /// Стандартные названия папки спама на разных языках (Outlook и Exchange,
  /// Gmail, Яндекс, Mail.ru, Yahoo, iCloud, Dovecot и др.).
  static const _junkNames = [
    'Junk', 'Junk Email', 'Junk E-mail', 'Junk Mail', 'Spam', 'Bulk Mail', 'Bulk',
    'Нежелательная почта', 'Нежелательные', 'Спам', // ru
    'Небажана пошта', // uk
    'Непажаданая пошта', // be
    'Junk-E-Mail', // de
    'Courrier indésirable', 'Courriers indésirables', 'Indésirables', 'Pourriel', 'Pourriels', // fr
    'Correo no deseado', 'Correo basura', // es
    'Posta indesiderata', // it
    'Lixo Eletrônico', 'Lixo Eletrónico', 'Lixo Electrónico', 'Correio Eletrónico de Lixo', // pt
    'Ongewenste e-mail', 'Ongewenste mail', // nl
    'Wiadomości-śmieci', // pl
    'Nevyžádaná pošta', // cs
    'Nevyžiadaná pošta', // sk
    'Levélszemét', // hu
    'E-mail nedorit', 'E-mailuri nedorite', // ro
    'Нежелана поща', // bg
    'Нежељена е-пошта', 'Neželjena e-pošta', 'Neželjena pošta', 'Bezvrijedna pošta', // sr, hr
    'Neželena e-pošta', // sl
    'Skräppost', // sv
    'Uønsket mail', 'Uønsket e-mail', // da
    'Søppelpost', // nb
    'Roskaposti', // fi
    'Rämpspost', // et
    'Nevēlamais e-pasts', // lv
    'Nepageidaujamas el. paštas', 'Šlamštas', // lt
    'Gereksiz E-posta', 'İstenmeyen', // tr
    'Ανεπιθύμητη αλληλογραφία', // el
    'דואר זבל', // he
    'البريد الإلكتروني العشوائي', 'البريد العشوائي', // ar
    '迷惑メール', // ja
    '垃圾邮件', '垃圾郵件', // zh
    '정크 메일', '스팸', '스팸메일함', // ko
    'Email Rác', 'Thư rác', // vi
    'อีเมลขยะ', // th
    'Email Sampah', // id
    'Қажетсіз пошта', // kk
  ];

  /// Стандартные названия папки архива.
  static const _archiveNames = [
    'Archive', 'Archives', 'Archived',
    'Архив', // ru, bg
    'Архів', // uk
    'Архіў', // be
    'Archiv', // de, cs
    'Archivo', 'Archivados', // es
    'Archivio', // it
    'Arquivo', 'Arquivo Morto', 'Arquivados', // pt
    'Archief', // nl
    'Archiwum', // pl
    'Archív', // sk
    'Archívum', // hu
    'Arhivă', 'Arhiva', // ro, hr
    'Архива', // sr
    'Arhiv', // sl
    'Arkiv', // sv, da, nb
    'Arkisto', // fi
    'Arhiiv', // et
    'Arhīvs', // lv
    'Archyvas', // lt
    'Arşiv', // tr
    'Αρχειοθέτηση', 'Αρχείο', // el
    'ארכיון', // he
    'أرشيف', // ar
    'アーカイブ', // ja
    '存档', '归档', '封存', '存檔', '歸檔', // zh
    '보관', '보관함', '아카이브', // ko
    'Lưu trữ', // vi
    'เก็บถาวร', // th
    'Arsip', // id
    'Мұрағат', // kk
  ];

  /// Буквы с диакритикой → без неё: «Courrier indesirable» без ударения или
  /// «Nevyzadana posta» латиницей тоже узнаются. Обе стороны сравнения
  /// проходят через [norm], поэтому таблица не обязана быть полной.
  static const _fold = {
    'ё': 'е', 'ї': 'і', 'ґ': 'г',
    'á': 'a', 'à': 'a', 'â': 'a', 'ä': 'a', 'ã': 'a', 'å': 'a', 'ā': 'a', 'ă': 'a', 'ą': 'a',
    'ç': 'c', 'ć': 'c', 'č': 'c', 'ď': 'd', 'đ': 'd',
    'é': 'e', 'è': 'e', 'ê': 'e', 'ë': 'e', 'ē': 'e', 'ę': 'e', 'ě': 'e',
    'í': 'i', 'ì': 'i', 'î': 'i', 'ï': 'i', 'ī': 'i', 'ı': 'i',
    'ł': 'l', 'ľ': 'l', 'ĺ': 'l', 'ñ': 'n', 'ń': 'n', 'ň': 'n',
    'ó': 'o', 'ò': 'o', 'ô': 'o', 'ö': 'o', 'õ': 'o', 'ø': 'o', 'ő': 'o',
    'ŕ': 'r', 'ř': 'r', 'ś': 's', 'š': 's', 'ş': 's', 'ș': 's', 'ť': 't', 'ț': 't', 'ţ': 't',
    'ú': 'u', 'ù': 'u', 'û': 'u', 'ü': 'u', 'ū': 'u', 'ů': 'u', 'ű': 'u', 'ư': 'u',
    'ý': 'y', 'ÿ': 'y', 'ź': 'z', 'ż': 'z', 'ž': 'z', 'ğ': 'g', 'ß': 'ss', 'æ': 'ae', 'œ': 'oe',
    'ά': 'α', 'έ': 'ε', 'ή': 'η', 'ί': 'ι', 'ό': 'ο', 'ύ': 'υ', 'ώ': 'ω', 'ϊ': 'ι', 'ϋ': 'υ', 'ς': 'σ',
  };

  /// Знаки, которые в названиях пишут по-разному: пробелы, дефисы,
  /// подчёркивания, точки, апострофы.
  static const _drop = {
    ' ', '\u00a0', '\u2009', '-', '\u2010', '\u2011', '_', '.', "'", '\u2019', '\u00b7', '\u0307',
  };

  /// Название без регистра, диакритики, пробелов и знаков.
  static String norm(String s) {
    final b = StringBuffer();
    for (final r in s.trim().toLowerCase().runes) {
      final c = String.fromCharCode(r);
      if (_drop.contains(c)) continue;
      b.write(_fold[c] ?? c);
    }
    return b.toString();
  }

  static final Set<String> _junk = {for (final n in _junkNames) norm(n)};
  static final Set<String> _archive = {for (final n in _archiveNames) norm(n)};

  /// Тип папки по стандартному названию или null.
  static FolderType? typeByName(String name) {
    final n = norm(name);
    if (n.isEmpty) return null;
    if (_junk.contains(n)) return FolderType.junk;
    if (_archive.contains(n)) return FolderType.archive;
    return null;
  }

  // ── Применение к списку папок ──

  /// Список папок ящика с типами «Архив» и «Спам»: ручной выбор
  /// ([archiveId], [junkId]), иначе — по названию, если сервер такой папки
  /// не указал. Изменённые папки — копиями (тип и «Вся почта» пересчитаны),
  /// порядок и остальные поля — как были.
  static List<FolderModel> apply(List<FolderModel> folders, {String? archiveId, String? junkId}) {
    final out = [...folders];
    final picked = <FolderType, int>{};
    // Сначала ручной выбор обеих папок, потом распознавание: иначе папка,
    // выбранная для спама, могла стать архивом по названию.
    for (final (t, id) in [(FolderType.archive, archiveId), (FolderType.junk, junkId)]) {
      if (id == null) continue;
      final i = out.indexWhere((f) => f.id == id);
      // Системную папку другого вида («Входящие», «Удалённые») не трогаем.
      if (i >= 0 && (out[i].type == FolderType.custom || out[i].type == t) && !picked.containsValue(i)) {
        picked[t] = i;
      }
    }
    for (final t in const [FolderType.archive, FolderType.junk]) {
      final i = picked[t];
      if (i != null) {
        for (var j = 0; j < out.length; j++) {
          if (j == i) {
            if (out[j].type != t) out[j] = _retype(out[j], t);
          } else if (out[j].type == t) {
            out[j] = _retype(out[j], FolderType.custom);
          }
        }
        continue;
      }
      if (out.any((f) => f.type == t)) continue; // сервер указал сам
      final found = _byName(out, t, exclude: picked.values.toSet());
      if (found != null) out[found] = _retype(out[found], t);
    }
    return out;
  }

  /// Папка верхнего уровня (или прямо во «Входящих») со стандартным
  /// названием; верхний уровень — первым.
  static int? _byName(List<FolderModel> list, FolderType t, {Set<int> exclude = const {}}) {
    final ids = {for (final f in list) f.id};
    final inboxIds = {for (final f in list) if (f.type == FolderType.inbox) f.id};
    int? inInbox;
    for (var i = 0; i < list.length; i++) {
      final f = list[i];
      if (exclude.contains(i) || f.type != FolderType.custom || typeByName(f.displayName) != t) continue;
      final p = f.parentId;
      if (p == null || p.isEmpty || !ids.contains(p)) return i;
      if (inboxIds.contains(p)) inInbox ??= i;
    }
    return inInbox;
  }

  /// Копия папки с другим типом. «Вся почта»: спам — никогда; папка, бывшая
  /// спамом, — да; остальное — как было (виртуальные папки Gmail остаются
  /// вне «Всей почты»).
  static FolderModel _retype(FolderModel f, FolderType t) => FolderModel(
        id: f.id,
        accountId: f.accountId,
        parentId: f.parentId,
        displayName: f.displayName,
        type: t,
        serverPath: f.serverPath,
        unreadCount: f.unreadCount,
        totalCount: f.totalCount,
        showInUnified: t == FolderType.junk ? false : (f.type == FolderType.junk ? true : f.showInUnified),
        isFavorite: f.isFavorite,
        sortOrder: f.sortOrder,
        isSynced: f.isSynced,
        iconName: f.iconName,
      );

  /// Применить к папкам ящика в базе сразу: выбор в настройках, кнопка
  /// «В архив» до ближайшего обновления списка папок. Возвращает, сколько
  /// папок изменилось.
  static Future<int> reapplyStored(AppDatabase db, SharedPreferences p, String accountId) async {
    final rows = await (db.select(db.folders)..where((f) => f.accountId.equals(accountId))).get();
    if (rows.isEmpty) return 0;
    final before = [for (final r in rows) folderFromRow(r)];
    final after = apply(before,
        archiveId: chosen(p, accountId, SpecialKind.archive), junkId: chosen(p, accountId, SpecialKind.junk));
    final changes = <String>[];
    for (var i = 0; i < before.length; i++) {
      final a = before[i], b = after[i];
      if (a.type == b.type && a.showInUnified == b.showInUnified) continue;
      await (db.update(db.folders)..where((f) => f.id.equals(a.id) & f.accountId.equals(accountId)))
          .write(FoldersCompanion(type: Value(b.type.index), showInUnified: Value(b.showInUnified)));
      changes.add(describe(a, b));
    }
    if (changes.isNotEmpty) AppLogger.info('Папки «Архив» и «Спам»: ${changes.join(', ')}');
    return changes.length;
  }

  /// Для журнала: «Нежелательная почта» custom → junk.
  static String describe(FolderModel before, FolderModel after) =>
      '«${before.displayName}» ${before.type.name} → ${after.type.name}';

  /// Папка вида [k] ящика из базы; если её нет — сначала распознать по
  /// названию среди сохранённых (список папок мог прийти до этой версии).
  static Future<String?> resolve(AppDatabase db, SharedPreferences p, String accountId, SpecialKind k) async {
    final id = await db.folderIdOfType(accountId, k.type.index);
    if (id != null) return id;
    if (await reapplyStored(db, p, accountId) == 0) return null;
    return db.folderIdOfType(accountId, k.type.index);
  }
}
