// lib/services/sync/push_health.dart
// Пульс push-соединений: когда цикл push по аккаунту в последний раз
// подтвердил, что жив (начал ожидание, получил событие, переподключился).
//
// Зачем: push «тихо умирал». IMAP IDLE висел на оборванном соединении (у
// IDLE-клиента не было таймаута ответа — DONE ждал вечно), цикл EAS Ping
// завершался исключением, а подписка оставалась в списке — и start() считал
// push живым до перезапуска приложения. Сторож (ImapPushService.ensureAlive)
// сравнивает пульс с допустимым возрастом и перезапускает зависший push.
//
// Глобальная карта, а не провайдер: пишут её три транспорта (IMAP, EAS, EWS)
// из разных сервисов, читает один сторож; всё — в главном изоляте.

final Map<String, DateTime> _lastAlive = {};

/// Цикл push аккаунта жив (вызывать в начале каждого ожидания и на событиях).
void markPushAlive(String accountId) => _lastAlive[accountId] = DateTime.now();

/// Последний пульс аккаунта; null — push ещё не отчитывался.
DateTime? pushLastAlive(String accountId) => _lastAlive[accountId];

/// Забыть пульс (push аккаунта остановлен).
void clearPushAlive(String accountId) => _lastAlive.remove(accountId);
