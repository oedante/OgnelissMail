// lib/features/mail/providers/email_selection_provider.dart
// Множественный выбор писем для batch-операций:
// - Выбрать несколько → удалить, пометить, переместить, тегировать
// - Select All / Deselect All
// - Счётчик выбранных
// - Действия через toolbar

import 'package:flutter_riverpod/legacy.dart';

import '../../../data/models/email_model.dart';

/// Состояние выбора
class EmailSelectionState {
  final bool isSelectionMode;
  final Set<String> selectedIds;

  const EmailSelectionState({
    this.isSelectionMode = false,
    this.selectedIds = const {},
  });

  int get count => selectedIds.length;
  bool get hasSelection => selectedIds.isNotEmpty;

  bool isSelected(String emailId) => selectedIds.contains(emailId);

  EmailSelectionState copyWith({
    bool? isSelectionMode,
    Set<String>? selectedIds,
  }) {
    return EmailSelectionState(
      isSelectionMode: isSelectionMode ?? this.isSelectionMode,
      selectedIds: selectedIds ?? this.selectedIds,
    );
  }
}

/// Провайдер выбора
final emailSelectionProvider =
    StateNotifierProvider<EmailSelectionNotifier, EmailSelectionState>((ref) {
  return EmailSelectionNotifier();
});

class EmailSelectionNotifier extends StateNotifier<EmailSelectionState> {
  EmailSelectionNotifier() : super(const EmailSelectionState());

  /// Войти в режим выбора
  void enterSelectionMode(String firstEmailId) {
    state = EmailSelectionState(
      isSelectionMode: true,
      selectedIds: {firstEmailId},
    );
  }

  /// Выйти из режима выбора
  void exitSelectionMode() {
    state = const EmailSelectionState();
  }

  /// Переключить выбор письма
  void toggle(String emailId) {
    final newIds = Set<String>.from(state.selectedIds);
    if (newIds.contains(emailId)) {
      newIds.remove(emailId);
    } else {
      newIds.add(emailId);
    }

    if (newIds.isEmpty) {
      state = const EmailSelectionState();
    } else {
      state = state.copyWith(selectedIds: newIds);
    }
  }

  /// Выбрать все из списка
  void selectAll(List<EmailModel> emails) {
    state = state.copyWith(
      isSelectionMode: true,
      selectedIds: emails.map((e) => e.id).toSet(),
    );
  }

  /// Снять выбор со всех
  void deselectAll() {
    state = const EmailSelectionState();
  }

  /// Получить ID выбранных
  List<String> getSelectedIds() => state.selectedIds.toList();
}
