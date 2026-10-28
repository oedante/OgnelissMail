// lib/features/mail/providers/selected_email_provider.dart
// Выбранное письмо для Master-Detail режима (широкие экраны).
// На узких экранах не используется — переход через навигацию.

import 'package:flutter_riverpod/legacy.dart';

class SelectedEmailRef {
  final String emailId;
  final String accountId;
  const SelectedEmailRef(this.emailId, this.accountId);
}

final selectedEmailProvider = StateProvider<SelectedEmailRef?>((ref) => null);
