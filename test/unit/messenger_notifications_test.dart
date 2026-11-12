// Уведомления «как в мессенджерах» (1.9.x): отправитель, аватар, ярлык
// беседы и возврат к прежнему виду (MessengerNotify).
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:ogneliss/core/utils/avatar_colors.dart';
import 'package:ogneliss/features/settings/providers/settings_provider.dart' show AppSettings;
import 'package:ogneliss/services/notifications/messenger_notifications.dart';
import 'package:ogneliss/services/notifications/notification_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('ярлык беседы', () {
    test('один на адрес: регистр и пробелы не важны', () {
      final a = MessengerNotify.shortcutId('Boss@Example.com');
      expect(a, isNotNull);
      expect(a, startsWith(MessengerNotify.shortcutPrefix));
      expect(MessengerNotify.shortcutId('  boss@example.com '), a);
      expect(MessengerNotify.shortcutId('other@example.com'), isNot(a));
      // В id нет самого адреса.
      expect(a, isNot(contains('example')));
    });

    test('без адреса беседы нет', () {
      for (final e in [null, '', '   ', 'no-at-sign', '@example.com', 'name@']) {
        expect(MessengerNotify.shortcutId(e), isNull, reason: '$e');
      }
    });

    test('только Android, оба тумблера, VIP с адресом', () {
      bool want({bool android = true, bool style = true, bool vipConv = true, bool vip = true, String? email = 'vip@example.com'}) =>
          MessengerNotify.wantsShortcut(
              android: android, styleOn: style, vipConversationsOn: vipConv, isVip: vip, email: email);
      expect(want(), isTrue);
      expect(want(android: false), isFalse);
      expect(want(style: false), isFalse);
      expect(want(vipConv: false), isFalse);
      expect(want(vip: false), isFalse);
      expect(want(email: ''), isFalse);
    });

    // 1.11.0: «Беседы для всех писем» — портрет вместо значка приложения
    // в свёрнутом уведомлении у любого письма.
    test('беседы для всех писем — и не VIP, но с адресом и видом мессенджера', () {
      bool want({bool all = true, bool vipConv = false, bool vip = false, bool style = true, String? email = 'a@example.com'}) =>
          MessengerNotify.wantsShortcut(
              android: true, styleOn: style, vipConversationsOn: vipConv, allConversationsOn: all, isVip: vip, email: email);
      expect(want(), isTrue);
      expect(want(all: false), isFalse);
      expect(want(all: false, vipConv: true, vip: true), isTrue);
      expect(want(style: false), isFalse);
      expect(want(email: null), isFalse);
    });

    test('нажатие открывает письмо — формат виджета «Почта»', () {
      final t = MessengerNotify.openTarget('acc 1', 'INBOX:42');
      final u = Uri.parse(t);
      expect(t, startsWith('email?'));
      expect(u.queryParameters['id'], 'INBOX:42');
      expect(u.queryParameters['acc'], 'acc 1');
    });
  });

  group('аватар', () {
    test('буква — как в списке писем', () {
      expect(MessengerNotify.initial('anna smith', 'a@example.com'), 'A');
      expect(MessengerNotify.initial('  ', 'zed@example.com'), 'Z');
      expect(MessengerNotify.initial('', null), '?');
      expect(MessengerNotify.initial('😀 Team', null), '😀');
    });

    test('цвета постоянны и из палитры приложения', () {
      final a = MessengerNotify.avatarColors('Boss@Example.com', 'Boss');
      expect(MessengerNotify.avatarColors('Boss@Example.com', 'Boss'), a);
      // Оттенок — по адресу без учёта регистра (как HeroEmailAvatar).
      expect(MessengerNotify.avatarColors('boss@example.com', 'Другое имя'), a);
      final hc = MessengerNotify.avatarColors('boss@example.com', 'Boss', highContrast: true);
      expect(hc.fill, avatarColorValue('boss@example.com'));
      expect(hc.letter, 0xFFFFFFFF);
      expect(kAvatarColorValues, contains(hc.fill));
      // Светлый вид: заливка светлее оттенка, буква темнее.
      int lum(int c) => ((c >> 16) & 0xFF) + ((c >> 8) & 0xFF) + (c & 0xFF);
      expect(lum(a.fill), greaterThan(lum(hc.fill)));
      expect(lum(a.letter), lessThan(lum(hc.fill)));
      expect(a.fill >> 24, 0xFF);
      // Без адреса — по имени.
      expect(MessengerNotify.avatarColors(null, 'Boss', highContrast: true).fill, avatarColorValue('Boss'));
    });

    test('фото из контактов: только data URI разумного размера', () {
      final bytes = Uint8List.fromList(List.generate(64, (i) => i));
      final uri = 'data:image/jpeg;base64,${base64.encode(bytes)}';
      expect(MessengerNotify.photoBytes(uri), bytes);
      expect(MessengerNotify.photoBytes('https://example.com/p.jpg'), isNull);
      expect(MessengerNotify.photoBytes('data:image/jpeg;base64,@@@'), isNull);
      expect(MessengerNotify.photoBytes(uri, maxBytes: 10), isNull);
      expect(MessengerNotify.photoBytes(null), isNull);
    });

    testWidgets('кружок с буквой — PNG нужного размера', (tester) async {
      final png = await tester.runAsync(() => MessengerNotify.renderInitials(
          letter: 'A', fill: 0xFFE0E8F0, letterColor: 0xFF334455, size: 96));
      expect(png, isNotNull);
      expect(png!.sublist(0, 4), [0x89, 0x50, 0x4E, 0x47]);
      final ihdr = ByteData.sublistView(png, 16, 24);
      expect(ihdr.getUint32(0), 96);
      expect(ihdr.getUint32(4), 96);
    });

    // 1.10.5 (замечание владельца 03.11.2026: «в оповещениях портреты
    // квадратные» — оболочка nubia не скругляет значок человека).
    testWidgets('фото — кружком: PNG с прозрачными углами, середина снимка', (tester) async {
      final src = img.Image(width: 60, height: 40);
      img.fill(src, color: img.ColorRgb8(200, 30, 30));
      final png = Uint8List.fromList(img.encodePng(src));
      final out = await tester.runAsync(() => MessengerNotify.circlePhoto(png, size: 64));
      expect(out, isNotNull);
      final d = img.decodePng(out!)!;
      expect(d.width, 64);
      expect(d.height, 64);
      expect(d.getPixel(0, 0).a, 0, reason: 'угол прозрачный');
      final c = d.getPixel(32, 32);
      expect(c.a, 255);
      expect(c.r, greaterThan(150));
      // Через avatar() — тоже кружком.
      final viaAvatar = await tester.runAsync(() => MessengerNotify.avatar(
          name: 'Boss', email: 'boss@example.com', photo: 'data:image/png;base64,${base64.encode(png)}'));
      expect(img.decodePng(viaAvatar!)!.getPixel(0, 0).a, 0);
    });

    // 1.10.5 (замечание владельца 03.11.2026: «звёздочка у VIP жирным
    // шрифтом не очень выглядит») — VIP отмечен на портрете: золотое кольцо
    // и звёздочка внизу справа, углы прозрачные.
    testWidgets('VIP: золотое кольцо и звёздочка на портрете', (tester) async {
      final plain = await tester.runAsync(() => MessengerNotify.avatar(name: 'Boss', email: 'boss@example.com'));
      final vip = await tester.runAsync(() => MessengerNotify.avatar(name: 'Boss', email: 'boss@example.com', vip: true));
      expect(plain, isNotNull);
      expect(vip, isNotNull);
      final d = img.decodePng(vip!)!;
      expect(d.width, 192);
      expect(d.getPixel(0, 0).a, 0, reason: 'угол прозрачный');
      bool golden(img.Pixel p) => p.a > 200 && p.r > 200 && p.g > 140 && p.g < 190 && p.b < 60;
      expect(golden(d.getPixel(96, 3)), isTrue, reason: 'кольцо сверху');
      expect(golden(d.getPixel(3, 96)), isTrue, reason: 'кольцо слева');
      // Звёздочка: белая середина в золотом кружке.
      final star = d.getPixel((192 * 0.81).round(), (192 * 0.81).round());
      expect(star.r > 240 && star.g > 240 && star.b > 240, isTrue, reason: 'белая звезда');
      expect(golden(d.getPixel((192 * 0.81).round(), (192 * 0.81 + 192 * 0.17 * 0.8).round())), isTrue,
          reason: 'золотой кружок под звездой');
      // Без VIP — без кольца.
      expect(golden(img.decodePng(plain!)!.getPixel(96, 3)), isFalse);
    });

    testWidgets('фото важнее буквы (не картинка — как есть)', (tester) async {
      final bytes = Uint8List.fromList([1, 2, 3, 4]);
      final got = await tester.runAsync(() => MessengerNotify.avatar(
          name: 'Boss', email: 'boss@example.com', photo: 'data:image/png;base64,${base64.encode(bytes)}'));
      expect(got, bytes);
    });
  });

  group('Android: MessagingStyle', () {
    test('отправитель — Person с адресом, ключом беседы и фото', () {
      final avatar = Uint8List.fromList([9, 9, 9]);
      final p = MessengerNotify.androidSender(title: 'Boss', email: 'Boss@example.com', avatar: avatar, vip: true);
      expect(p.name, 'Boss');
      expect(p.uri, 'mailto:Boss@example.com');
      expect(p.key, MessengerNotify.shortcutId('boss@example.com'));
      expect(p.important, isTrue);
      expect(p.icon, isA<ByteArrayAndroidIcon>());
      expect((p.icon! as ByteArrayAndroidIcon).data, avatar);
      final noPhoto = MessengerNotify.androidSender(title: 'x', email: '');
      expect(noPhoto.icon, isNull);
      expect(noPhoto.uri, isNull);
    });

    test('сообщение — тема, ниже начало письма; «я» — ящик', () {
      final when = DateTime.utc(2026, 10, 31, 9, 30);
      final style = NotificationService.emailAndroidStyle(
        messenger: true,
        title: 'Boss',
        subject: 'Report',
        preview: 'Please check the numbers.',
        selfName: 'me.work',
        fromEmail: 'boss@example.com',
        when: when,
      );
      expect(style, isA<MessagingStyleInformation>());
      final m = style as MessagingStyleInformation;
      expect(m.person.name, 'me.work');
      expect(m.groupConversation, isFalse);
      expect(m.messages, hasLength(1));
      expect(m.messages!.single.text, 'Report\nPlease check the numbers.');
      expect(m.messages!.single.timestamp, when);
      expect(m.messages!.single.person?.name, 'Boss');
    });

    test('«я» без подписи ящика — всё равно с именем (иначе Android падает)', () {
      final m = MessengerNotify.androidStyle(
          selfName: ' ', sender: const Person(name: 'x'), text: 't', when: DateTime(2026));
      expect(m.person.name, isNotEmpty);
    });

    test('выключено — прежний вид: BigText, жирным отправитель', () {
      final style = NotificationService.emailAndroidStyle(
        messenger: false,
        title: 'Boss',
        subject: 'Report',
        preview: 'Text',
        subText: 'me.work',
        when: DateTime(2026),
      );
      expect(style, isA<BigTextStyleInformation>());
      final b = style as BigTextStyleInformation;
      expect(b.bigText, 'Report\nText');
      expect(b.contentTitle, 'Boss');
      expect(b.summaryText, 'me.work');
    });
  });

  group('iPhone: параметры уведомления', () {
    test('те же группа, категория и payload; беседа — по адресу', () {
      final a = MessengerNotify.iosArgs(
        id: 7, title: '★ Boss', subtitle: 'Report', body: 'Text', threadId: 'email_acc',
        category: 'EMAIL', sound: true, badge: 3, payload: '{"type":"email"}', senderEmail: 'boss@example.com',
      );
      expect(a['thread'], 'email_acc');
      expect(a['category'], 'EMAIL');
      expect(a['payload'], '{"type":"email"}');
      expect(a['senderName'], '★ Boss');
      expect(a['conversation'], MessengerNotify.shortcutId('boss@example.com'));
      final noEmail = MessengerNotify.iosArgs(
        id: 7, title: 'Boss', subtitle: '', body: '', threadId: 't', category: 'EMAIL',
        sound: false, badge: 0, payload: '{}',
      );
      expect(noEmail['conversation'], isNotNull);
      expect(noEmail['senderEmail'], '');
    });
  });

  group('настройки', () {
    test('по умолчанию включено; выключенное читается и в фоне', () async {
      SharedPreferences.setMockInitialValues({});
      final p = await SharedPreferences.getInstance();
      expect(MessengerNotify.styleOn(p), isTrue);
      expect(MessengerNotify.vipConversationsOn(p), isTrue);
      expect(MessengerNotify.styleOn(null), isTrue);
      await p.setBool(MessengerNotify.prefStyle, false);
      await p.setBool(MessengerNotify.prefVipConversations, false);
      expect(MessengerNotify.styleOn(p), isFalse);
      expect(MessengerNotify.vipConversationsOn(p), isFalse);
      const s = AppSettings(isFirstLaunch: false);
      expect(s.notificationMessengerStyle, isTrue);
      expect(s.notificationVipConversations, isTrue);
      // Беседы для всех писем — по умолчанию выключены.
      expect(MessengerNotify.allConversationsOn(p), isFalse);
      expect(s.notificationAllConversations, isFalse);
      await p.setBool(MessengerNotify.prefAllConversations, true);
      expect(MessengerNotify.allConversationsOn(p), isTrue);
    });
  });

  test('значок ящика: буква на цвете ящика — белая на тёмном, тёмная на светлом', () {
    expect(MessengerNotify.mailboxLetterColor(0xFF1D4F91), 0xFFFFFFFF);
    expect(MessengerNotify.mailboxLetterColor(0xFFFFC928), 0xFF1F1F1F);
    expect(MessengerNotify.mailboxLetterColor(0xFF2E8B57), 0xFFFFFFFF);
    expect(MessengerNotify.initial('', "'aho@engicom.ru'"), 'A');
  });
}
