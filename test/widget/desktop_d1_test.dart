// iPad и компьютер (1.9.x, просьба владельца 31.10.2026, задание D1):
// перетаскивание писем на папку, разделитель панелей, файлы на окно письма,
// письмо в отдельном окне.

import 'dart:io';
import 'dart:typed_data';
import 'package:path/path.dart' as p;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ogneliss/core/theme/app_icons.dart';
import 'package:ogneliss/data/models/email_model.dart';
import 'package:ogneliss/data/models/folder_model.dart';
import 'package:ogneliss/features/mail/message_window.dart';
import 'package:ogneliss/features/mail/widgets/mail_drag.dart';
import 'package:ogneliss/l10n/app_localizations.dart';
import 'package:ogneliss/widgets/common/adaptive_layout.dart';
import 'package:ogneliss/widgets/common/file_drop_zone.dart';
import 'package:super_clipboard/super_clipboard.dart' show DataReader, DataReaderFile, ReadProgress;
import 'package:super_drag_and_drop/super_drag_and_drop.dart';

EmailModel _mail(String id, {String account = 'a1', String folder = 'INBOX'}) => EmailModel(
      id: id,
      accountId: account,
      folderId: folder,
      from: const EmailAddress(email: 'anna@corp.example', displayName: 'Анна'),
      to: const [EmailAddress(email: 'me@corp.example')],
      subject: 'Письмо $id',
      receivedAt: DateTime(2026, 10, 30, 9),
    );

FolderModel _folder(String id, {String account = 'a1'}) =>
    FolderModel(id: id, accountId: account, displayName: id, type: FolderType.custom);

void main() {
  group('письма на папку', () {
    test('в папку своего ящика — да; другого ящика или ту же — нет', () {
      final d = MailDragData([_mail('1'), _mail('2', folder: 'Work')]);
      expect(d.fitsFolder(_folder('Work')), isTrue);
      expect(d.movingTo(_folder('Work')).map((e) => e.id), ['1']);
      expect(d.fitsFolder(_folder('Work', account: 'a2')), isFalse);
      expect(MailDragData([_mail('3', folder: 'Work')]).fitsFolder(_folder('Work')), isFalse);
    });

    Future<List<MailDragData>> drag(WidgetTester tester,
        {required bool touchDraggable, required PointerDeviceKind kind, Duration hold = Duration.zero}) async {
      final dropped = <MailDragData>[];
      await tester.pumpWidget(MaterialApp(
        home: Row(children: [
          SizedBox(
            width: 200,
            height: 100,
            child: MailDraggable(
              touch: touchDraggable,
              data: MailDragData([_mail('1')]),
              feedback: const Material(child: Text('1 письмо')),
              child: const ColoredBox(color: Colors.blue, child: SizedBox.expand(key: Key('row'))),
            ),
          ),
          SizedBox(
            width: 200,
            height: 100,
            child: DragTarget<MailDragData>(
              onAcceptWithDetails: (d) => dropped.add(d.data),
              builder: (_, __, ___) => const SizedBox.expand(key: Key('folder')),
            ),
          ),
        ]),
      ));
      final from = tester.getCenter(find.byKey(const Key('row')));
      final to = tester.getCenter(find.byKey(const Key('folder')));
      final g = await tester.startGesture(from, kind: kind);
      if (hold > Duration.zero) await tester.pump(hold);
      for (var i = 1; i <= 8; i++) {
        await g.moveTo(Offset.lerp(from, to, i / 8)!);
        await tester.pump(const Duration(milliseconds: 16));
      }
      await g.up();
      await tester.pumpAndSettle();
      return dropped;
    }

    testWidgets('мышью — сразу', (tester) async {
      expect(await drag(tester, touchDraggable: false, kind: PointerDeviceKind.mouse), hasLength(1));
    });

    testWidgets('пальцем без удержания — не перетаскивание (прокрутка и свайп строки)', (tester) async {
      expect(await drag(tester, touchDraggable: false, kind: PointerDeviceKind.touch), isEmpty);
      expect(await drag(tester, touchDraggable: true, kind: PointerDeviceKind.touch), isEmpty);
    });

    testWidgets('пальцем — после удержания', (tester) async {
      final r = await drag(tester,
          touchDraggable: true, kind: PointerDeviceKind.touch, hold: MailDrag.touchDelay + const Duration(milliseconds: 50));
      expect(r.single.emails.single.id, '1');
    });
  });

  testWidgets('разделитель панелей: тянется, двойное нажатие — сброс', (tester) async {
    var width = 300.0;
    var ended = 0, reset = 0;
    await tester.pumpWidget(MaterialApp(
      home: StatefulBuilder(
        builder: (context, setState) => Row(children: [
          SizedBox(width: width),
          PaneSplitter(
            onDrag: (dx) => setState(() => width = (width + dx).clamp(200, 400)),
            onDragEnd: () => ended++,
            onReset: () => reset++,
          ),
          const Expanded(child: SizedBox()),
        ]),
      ),
    ));
    final at = tester.getCenter(find.byType(PaneSplitter));
    await tester.dragFrom(at, const Offset(60, 0), kind: PointerDeviceKind.mouse);
    await tester.pumpAndSettle();
    expect(width, greaterThan(320)); // минус порог начала перетаскивания
    expect(ended, 1);
    await tester.dragFrom(tester.getCenter(find.byType(PaneSplitter)), const Offset(500, 0));
    await tester.pumpAndSettle();
    expect(width, 400);
    await tester.tap(find.byType(PaneSplitter));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(find.byType(PaneSplitter));
    await tester.pumpAndSettle();
    expect(reset, 1);
  });

  // 1.15.0: приём — пакетом super_drag_and_drop (вместо desktop_drop). Его
  // нативной части в тестах нет: проверяется разбор брошенного и что без
  // неё окно письма остаётся как есть.
  test('файлы на окно (компьютер): пути file:// — в список, прочее — нет', () async {
    final paths = await droppedPaths([
      _DroppedItem(Uri.file('/tmp/smeta.xlsx')),
      _DroppedItem(Uri.parse('https://example.com/a.pdf')),
      _DroppedItem(null),
      _DroppedItem(Uri.file('/tmp/photo.jpg')),
    ]);
    expect(paths, ['/tmp/smeta.xlsx', '/tmp/photo.jpg']);
  });

  // 1.15.1: iPad, Android, вложение из Outlook — файл без пути: содержимое
  // во временную папку под своим именем; текст и ссылки файлом не считаются.
  test('файл без пути — во временную папку; текст — не файл', () async {
    final dir = Directory.systemTemp.createTempSync('drop_test');
    addTearDown(() => dir.deleteSync(recursive: true));
    final items = [
      _DroppedItem(null, formats: const ['application/pdf'], content: [1, 2, 3], name: 'Смета: итог.pdf'),
      _DroppedItem(null, formats: const ['text/plain', 'public.utf8-plain-text'], content: [65]),
      _DroppedItem(Uri.file('/tmp/photo.jpg')),
      _DroppedItem(null, formats: const ['image/jpeg'], content: [9, 9]),
    ];
    expect(looksLikeFile(items[0]), isTrue);
    expect(looksLikeFile(items[1]), isFalse);
    expect(looksLikeFile(items[2]), isTrue);
    final paths = await receiveDroppedFiles(items, into: dir);
    expect(paths, hasLength(3));
    expect(p.basename(paths[0]), 'Смета_ итог.pdf');
    expect(File(paths[0]).readAsBytesSync(), [1, 2, 3]);
    expect(paths[1], '/tmp/photo.jpg');
    // Без имени — «file-N».
    expect(p.basename(paths[2]), 'file-4');
  });

  testWidgets('без нативной части перетаскивания — окно как было', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: FileDropZone(hint: 'Отпустите', onFiles: (_) {}, child: const Text('письмо')),
    ));
    expect(FileDropZone.supported, isFalse);
    expect(find.text('письмо'), findsOneWidget);
  });

  group('письмо в отдельном окне', () {
    const p = MessageWindowPayload(
      accountId: 'a1',
      emailId: 'INBOX:7',
      folderId: 'INBOX',
      subject: 'Смета',
      from: (name: 'Анна', email: 'anna@corp.example'),
      to: [(name: '', email: 'me@corp.example')],
      html: '<p>Текст письма</p>',
      images: {'logo': 'data:image/png;base64,AA=='},
      attachments: [(id: 'att1', name: 'smeta.xlsx', size: 1200)],
      dark: true,
      locale: 'ru',
    );

    test('данные окна — туда и обратно', () {
      final back = MessageWindowPayload.fromJson(p.toJson())!;
      expect(back.emailId, 'INBOX:7');
      expect(back.from.name, 'Анна');
      expect(back.to.single.email, 'me@corp.example');
      expect(back.images['logo'], startsWith('data:image/png'));
      expect(back.attachments.single.name, 'smeta.xlsx');
      expect(back.dark, isTrue);
      // Чужие аргументы окна — не письмо.
      expect(MessageWindowPayload.fromJson({'kind': 'other'}), isNull);
      expect(MessageWindowPayload.fromJson('x'), isNull);
    });

    testWidgets('кнопки окна просят главное окно', (tester) async {
      final asked = <(String, Map<String, Object?>)>[];
      await tester.pumpWidget(MaterialApp(
        locale: const Locale('ru'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: MessageWindowScreen(payload: p, ask: (m, a) async => asked.add((m, a))),
      ));
      await tester.pumpAndSettle();
      expect(find.text('Смета'), findsOneWidget);
      expect(find.text('Анна'), findsOneWidget);
      await tester.tap(find.byIcon(AppIcons.reply));
      expect(asked.single.$1, 'reply');
      await tester.tap(find.text('smeta.xlsx'));
      await tester.pump();
      expect(asked.map((e) => e.$1), contains('openAttachment'));
      expect(asked.last.$2['attachmentId'], 'att1');
      expect(asked.last.$2['emailId'], 'INBOX:7');
    });
  });
}

/// Брошенный элемент с адресом файла (или без него) — для [droppedPaths].
class _DroppedItem extends DropItem {
  _DroppedItem(this.uri, {this.formats = const [], this.content, this.name});
  final Uri? uri;
  final List<String> formats;

  /// Содержимое файла без пути (iPad, Android, «виртуальный» файл).
  final List<int>? content;
  final String? name;

  @override
  bool canProvide(DataFormat f) => uri != null && f == Formats.fileUri;

  @override
  DataReader? get dataReader => uri == null && content == null ? null : _Reader(uri, content, name);

  @override
  Object? get localData => null;

  @override
  List<String> get platformFormats => formats;
}

class _Reader implements DataReader {
  _Reader(this.uri, this.content, this.name);
  final Uri? uri;
  final List<int>? content;
  final String? name;

  @override
  bool canProvide(DataFormat format) => uri != null && format == Formats.fileUri;

  @override
  ReadProgress? getValue<T extends Object>(ValueFormat<T> format, onValue, {onError}) {
    if (uri == null) return null;
    onValue(uri as T);
    return _Progress();
  }

  @override
  ReadProgress? getFile(FileFormat? format, onFile, {onError, allowVirtualFiles = true, synthesizeFilesFromURIs = true}) {
    final c = content;
    if (c == null) return null;
    onFile(_File(name, c));
    return _Progress();
  }

  @override
  Future<String?> getSuggestedName() async => null;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _File implements DataReaderFile {
  _File(this.fileName, this.content);
  @override
  final String? fileName;
  final List<int> content;

  @override
  int? get fileSize => content.length;

  @override
  Stream<Uint8List> getStream() => Stream.value(Uint8List.fromList(content));

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Progress implements ReadProgress {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
