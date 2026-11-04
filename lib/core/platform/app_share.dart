// lib/core/platform/app_share.dart
// «Поделиться» с учётом политики организации (MDM, 1.10.5,
// managed_config.dart): «Поделиться», сохранение в облако и в другие
// приложения запрещены — строка «Запрещено организацией» вместо листа,
// результат — «недоступно». Все «Поделиться» приложения — через эту функцию.

import 'package:share_plus/share_plus.dart';

import '../../services/security/managed_config.dart';

Future<ShareResult> appShare(ShareParams params) async {
  if (ManagedPolicy.deny(ManagedRule.share)) return ShareResult.unavailable;
  return SharePlus.instance.share(params);
}
