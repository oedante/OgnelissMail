// lib/widgets/navigation/panel_requests.dart
// Запросы от центральной кнопки нижней панели к экранам разделов: «создать»
// выполняет сам экран (у него форма, текущий список, правая панель на
// планшете). Экран слушает счётчик и открывает свою форму.

import 'package:flutter_riverpod/legacy.dart';

/// Новый контакт (экран «Контакты»).
final contactsAddRequestProvider = StateProvider<int>((ref) => 0);

/// Новая задача (экран «Задачи»).
final tasksAddRequestProvider = StateProvider<int>((ref) => 0);

/// Открыть календарь на дне [DateTime] в режиме «День» (из «Моего дня»).
/// Экран календаря выполняет и сбрасывает запрос.
final calendarDayRequestProvider = StateProvider<DateTime?>((ref) => null);

/// Повторное нажатие на «Почту» в нижней панели (1.6.49, как в Telegram) —
/// лента к началу. Экран ленты слушает счётчик.
final mailScrollTopRequestProvider = StateProvider<int>((ref) => 0);

/// Найти письма в ленте (1.6.49+95: «Все письма от» у контакта). Экран
/// ленты включает поиск с этим запросом и сбрасывает его.
final mailSearchQueryProvider = StateProvider<String?>((ref) => null);
