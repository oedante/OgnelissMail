// lib/widgets/common/hero_email_transition.dart
// Hero-анимация аватарки при открытии письма.
// Плавный переход между списком и детальным просмотром.

import '../../core/utils/text_safe.dart';
import 'package:flutter/material.dart';
import '../../core/utils/avatar_colors.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/settings/providers/module_settings_provider.dart' show moduleSettingsProvider;
import '../../services/contacts/mail_contacts_service.dart' show mailContactsServiceProvider;
import 'animated_appearance.dart' show uiAnimations;
import 'person_photo.dart';

/// Обёртка для Hero-анимации аватарки. Есть фото (контакт, аккаунт) —
/// показывается оно, нет — буква на цветном круге.
class HeroEmailAvatar extends ConsumerWidget {
  final String emailId;
  final String initial;
  final Color color;
  final double radius;
  /// Адрес человека: по нему ищется фото в контактах.
  final String? email;
  /// Фото задано явно (например, у аккаунта).
  final String? photo;

  /// false — без Hero. В split-view (Windows, планшет) список и карточка
  /// письма в одном маршруте: два Hero с одним тегом роняют перерисовку
  /// («multiple heroes share the same tag»).
  final bool hero;

  const HeroEmailAvatar({
    super.key,
    required this.emailId,
    required this.initial,
    required this.color,
    this.radius = 24,
    this.hero = true,
    this.email,
    this.photo,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    String? src = photo;
    if (src == null && email != null && email!.isNotEmpty) {
      final photos = ref.watch(personPhotosProvider);
      src = photos.value?[email!.toLowerCase()];
      // Фото нет — спросить в адресной книге организации, как это делает
      // вкладка «Контакты» (1.6.32). Раньше лента ждала фонового прохода
      // (20 человек за синхронизацию, по частоте переписки), и у редких
      // собеседников фото появлялись только после захода в «Контакты»
      // (замечание 18.10.2026). Адрес — не чаще раза за запуск, «нет фото» —
      // раз в неделю; только когда карта фото уже загружена из базы.
      if (src == null &&
          photos.hasValue &&
          email!.contains('@') &&
          ref.read(moduleSettingsProvider).showContactPhotos) {
        ref.read(mailContactsServiceProvider).requestPhoto(email!);
      }
    }
    final image = photoImage(src);
    // Фото — в рамке (PhotoRing): светлые портреты сливались с белым фоном,
    // тёмные — с тёмным (замечания 07.10 и 10.10.2026).
    final avatar = image != null
        ? PhotoRing(
            width: radius >= 14 ? 1.5 : 1,
            child: CircleAvatar(
              radius: radius,
              backgroundColor: color,
              backgroundImage: image,
              onBackgroundImageError: (_, __) {},
            ),
          )
        : _monogram(context);
    if (!hero || !uiAnimations) return avatar;
    return Hero(tag: 'avatar_$emailId', child: avatar);
  }

  /// Кружок с буквой: с 1.8.0 светлый, буква — оттенком человека
  /// (avatarTones); в высоком контрасте — насыщенный с белой буквой.
  Widget _monogram(BuildContext context) {
    final tones = avatarTones(context, color);
    return CircleAvatar(
      radius: radius,
      backgroundColor: tones.fill,
      child: Text(
        // Половинка эмодзи без пары роняла отрисовку — страховка.
        fixUtf16(initial),
        style: TextStyle(
          color: tones.letter,
          fontSize: radius * 0.75,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  /// Цвет аватарки по email — общая палитра (core/utils/avatar_colors.dart).
  static Color colorForEmail(String email) => Color(avatarColorValue(email));
}

/// Hero-анимация для заголовка письма
class HeroEmailSubject extends StatelessWidget {
  final String emailId;
  final String subject;
  final TextStyle? style;

  const HeroEmailSubject({
    super.key,
    required this.emailId,
    required this.subject,
    this.style,
  });

  @override
  Widget build(BuildContext context) {
    final text = Material(
      color: Colors.transparent,
      child: Text(
        subject,
        style: style ?? Theme.of(context).textTheme.titleMedium,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
    );
    if (!uiAnimations) return text;
    return Hero(
      tag: 'subject_$emailId',
      child: Material(
        color: Colors.transparent,
        child: Text(
          subject,
          style: style ?? Theme.of(context).textTheme.titleMedium,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }
}
