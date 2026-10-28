// lib/services/mail/ews/ews_directory_extras.dart
// Дополнительные запросы EWS к каталогу организации (1.6.49):
//   · GetUserPhoto — фото человека в высоком качестве (HR240x240 и больше;
//     в адресной книге ActiveSync — миниатюра 96×96 из Active Directory,
//     на телефоне она «мыльная»);
//   · GetRoomLists / GetRooms — переговорные организации по спискам
//     (здание, этаж) для выбора при создании собрания;
//   · стандартная папка — есть ли архив ящика (archivemsgfolderroot) и
//     есть ли доступ к почте и календарю общего ящика.
//
// Запросы и разбор — отдельно от больших EwsXmlBuilder/EwsXmlParser. Разбор —
// по локальным именам элементов: префиксы пространств имён у серверов разные.

import 'dart:convert' show base64;
import 'dart:typed_data';

import 'package:xml/xml.dart';

/// Переговорная или список переговорных.
class DirectoryRoom {
  final String name;
  final String email;
  const DirectoryRoom({required this.name, required this.email});

  @override
  bool operator ==(Object other) => other is DirectoryRoom && other.email == email && other.name == name;

  @override
  int get hashCode => Object.hash(name, email);

  @override
  String toString() => '$name <$email>';
}

abstract final class EwsDirectoryExtras {
  static String _esc(String s) => s
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;');

  static Iterable<XmlElement> _all(XmlNode n, String local) =>
      n.descendants.whereType<XmlElement>().where((e) => e.name.local == local);

  static XmlElement? _first(XmlNode n, String local) {
    for (final e in _all(n, local)) {
      return e;
    }
    return null;
  }

  /// Размеры фото Exchange: HR48x48 … HR648x648. 240 — с запасом для
  /// карточки (96 dp × 3 на плотном экране — 288 точек, ResizeImage).
  static const photoSize = 'HR240x240';

  // ───────────────────────── GetUserPhoto ─────────────────────────

  static String buildGetUserPhoto(String email, {String size = photoSize}) =>
      '<m:GetUserPhoto>'
      '<m:Email>${_esc(email.trim())}</m:Email>'
      '<m:SizeRequested>$size</m:SizeRequested>'
      '</m:GetUserPhoto>';

  /// JPEG из ответа; null — фото нет (или ответ с ошибкой).
  static Uint8List? parseUserPhoto(XmlDocument doc) {
    final resp = _first(doc, 'GetUserPhotoResponse');
    if (resp == null) return null;
    final cls = resp.getAttribute('ResponseClass') ?? 'Success';
    if (cls != 'Success') return null;
    final data = _first(resp, 'PictureData')?.innerText.replaceAll(RegExp(r'\s'), '') ?? '';
    if (data.isEmpty) return null;
    try {
      final bytes = base64.decode(data);
      // Меньше сотни байт — не картинка (пустой ответ, заглушка).
      return bytes.length < 100 ? null : Uint8List.fromList(bytes);
    } catch (_) {
      return null;
    }
  }

  // ───────────────────────── Переговорные ─────────────────────────

  static String buildGetRoomLists() => '<m:GetRoomLists/>';

  static String buildGetRooms(String roomListEmail) =>
      '<m:GetRooms><m:RoomList><t:EmailAddress>${_esc(roomListEmail.trim())}</t:EmailAddress></m:RoomList></m:GetRooms>';

  static List<DirectoryRoom> _addresses(Iterable<XmlElement> items) {
    final out = <DirectoryRoom>[];
    final seen = <String>{};
    for (final a in items) {
      final email = _first(a, 'EmailAddress')?.innerText.trim() ?? '';
      if (!email.contains('@') || !seen.add(email.toLowerCase())) continue;
      final name = _first(a, 'Name')?.innerText.trim() ?? '';
      out.add(DirectoryRoom(name: name.isEmpty ? email : name, email: email));
    }
    out.sort((x, y) => x.name.toLowerCase().compareTo(y.name.toLowerCase()));
    return out;
  }

  /// Списки переговорных (здания, этажи) из ответа GetRoomLists.
  static List<DirectoryRoom> parseRoomLists(XmlDocument doc) {
    final lists = _first(doc, 'RoomLists');
    if (lists == null) return const [];
    return _addresses(_all(lists, 'Address'));
  }

  /// Переговорные списка из ответа GetRooms.
  static List<DirectoryRoom> parseRooms(XmlDocument doc) => _addresses(_all(doc, 'Room'));

  // ─────────────────── Стандартная папка: архив, доступ ───────────────────

  /// GetFolder стандартной папки ([id]: archivemsgfolderroot — архив ящика,
  /// inbox / calendar общего ящика [mailbox] — проверка доступа).
  static String buildGetDistinguishedFolder(String id, {String? mailbox}) {
    final mb = (mailbox ?? '').trim();
    final box = mb.isEmpty ? '' : '<t:Mailbox><t:EmailAddress>${_esc(mb)}</t:EmailAddress></t:Mailbox>';
    return '<m:GetFolder>'
        '<m:FolderShape><t:BaseShape>IdOnly</t:BaseShape></m:FolderShape>'
        '<m:FolderIds><t:DistinguishedFolderId Id="${_esc(id)}">$box</t:DistinguishedFolderId></m:FolderIds>'
        '</m:GetFolder>';
  }

  /// GetFolder сразу для нескольких стандартных папок [ids] (1.7.2+107):
  /// «inbox», «sentitems»… — постоянные имена Exchange, одинаковые на любом
  /// языке ящика. [mailbox] — общий ящик (иначе свой).
  static String buildGetDistinguishedFolders(List<String> ids, {String? mailbox}) {
    final mb = (mailbox ?? '').trim();
    final box = mb.isEmpty ? '' : '<t:Mailbox><t:EmailAddress>${_esc(mb)}</t:EmailAddress></t:Mailbox>';
    final list = ids.map((id) => '<t:DistinguishedFolderId Id="${_esc(id)}">$box</t:DistinguishedFolderId>').join();
    return '<m:GetFolder>'
        '<m:FolderShape><t:BaseShape>IdOnly</t:BaseShape></m:FolderShape>'
        '<m:FolderIds>$list</m:FolderIds>'
        '</m:GetFolder>';
  }

  /// Id папок из ответа GetFolder — по порядку запроса; null — папки нет или
  /// нет доступа (ответ на каждую папку свой, ошибка одной не мешает другим).
  static List<String?> parseFolderIds(XmlDocument doc) =>
      [for (final msg in _all(doc, 'GetFolderResponseMessage')) _successId(msg)];

  static String? _successId(XmlElement msg) {
    if ((msg.getAttribute('ResponseClass') ?? '') != 'Success') return null;
    final id = _first(msg, 'FolderId')?.getAttribute('Id');
    return (id == null || id.isEmpty) ? null : id;
  }

  /// Id папки из ответа GetFolder; null — папки нет или нет доступа
  /// (ErrorFolderNotFound, ErrorAccessDenied…).
  static String? parseFolderId(XmlDocument doc) {
    final msg = _first(doc, 'GetFolderResponseMessage');
    if (msg == null || (msg.getAttribute('ResponseClass') ?? '') != 'Success') return null;
    final id = _first(msg, 'FolderId')?.getAttribute('Id');
    return (id ?? '').isEmpty ? null : id;
  }
}
