// lib/services/calendar/meeting_link_service.dart
//
// Распознавание ссылки на онлайн-встречу в приглашении.
//
// Ссылки приходят в разных полях: в «месте проведения», в теле приглашения,
// иногда обоими способами сразу. Организаторы вставляют их вперемешку с
// текстом («Подключиться: https://…», «Идентификатор конференции: 123»),
// поэтому просто открыть location нельзя — нужно вытащить именно URL.
//
// Поддержаны площадки, распространённые в российских организациях, плюс
// западные для переписки с подрядчиками.


class MeetingLink {
  /// Название площадки для подписи кнопки («Подключиться в Teams»).
  final String platform;
  final String url;

  const MeetingLink(this.platform, this.url);
}

class MeetingLinkService {
  MeetingLinkService._();

  /// Площадка → шаблон домена. Порядок важен: более специфичные проверяются
  /// раньше общих.
  static const _platforms = <String, List<String>>{
    'Teams': ['teams.microsoft.com', 'teams.live.com'],
    'VK Звонки': ['vk.com/call', 'vkvideo.ru', 'okmeet.ru'],
    'Яндекс Телемост': ['telemost.yandex'],
    'СБЕР Джаз': ['sberjazz.ru', 'jazz.sber.ru'],
    'TrueConf': ['trueconf'],
    'Vinteo': ['vinteo.com', 'vinteo.ru'],
    'Skype': ['join.skype.com', 'skype.com/join', 'meet.lync.com'],
    'Контур.Толк': ['ktalk.ru'],
    'Zoom': ['zoom.us', 'zoom.com'],
    'Google Meet': ['meet.google.com'],
    'Webex': ['webex.com'],
  };

  static final _urlPattern = RegExp(r'https?://[^\s<>"\)\]]+', caseSensitive: false);

  /// Ищет ссылку на встречу в месте проведения и описании события.
  /// Возвращает null, если встреча очная или ссылки нет.
  static MeetingLink? find({String? location, String? description}) {
    // Место проведения проверяем первым: организаторы чаще кладут ссылку туда,
    // а в описании может оказаться посторонняя (например, на регламент).
    for (final source in [location, description]) {
      if (source == null || source.isEmpty) continue;
      for (final match in _urlPattern.allMatches(source)) {
        final url = _clean(match.group(0)!);
        final platform = _platformOf(url);
        if (platform != null) return MeetingLink(platform, url);
      }
    }
    return null;
  }

  /// Шаблоны без зоны верхнего уровня: TrueConf и Телемост часто стоят на
  /// собственных серверах организаций (trueconf.company.ru, telemost.yandex.ru).
  static const _partialHosts = {'trueconf', 'telemost.yandex'};

  /// Площадка определяется по ХОСТУ ссылки (и началу пути), а не по вхождению
  /// подстроки в адрес: раньше «https://evil.example/?teams.microsoft.com»
  /// получал кнопку «Подключиться к Teams».
  /// Название площадки по ссылке («Teams», «Телемост»…) или null.
  static String? platformOf(String url) => _platformOf(url);

  static String? _platformOf(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null || uri.host.isEmpty || !(uri.scheme == 'https' || uri.scheme == 'http')) {
      return null;
    }
    if (uri.userInfo.isNotEmpty) return null; // «https://teams.microsoft.com@evil»
    final host = uri.host.toLowerCase();
    final path = uri.path.toLowerCase();
    for (final entry in _platforms.entries) {
      for (final pattern in entry.value) {
        final slash = pattern.indexOf('/');
        final hp = slash < 0 ? pattern : pattern.substring(0, slash);
        final pp = slash < 0 ? '' : pattern.substring(slash);
        final hostOk = _partialHosts.contains(hp)
            ? '.$host.'.contains('.$hp.') || host.split('.').any((l) => l.startsWith(hp))
            : host == hp || host.endsWith('.$hp');
        if (hostOk && (pp.isEmpty || path.startsWith(pp))) return entry.key;
      }
    }
    return null;
  }

  /// Убирает хвостовую пунктуацию: ссылка часто стоит в конце предложения
  /// («Подключиться: https://…/abc.») — точка в URL не входит.
  static String _clean(String url) {
    var u = url;
    while (u.isNotEmpty && '.,;:!?)»"\''.contains(u[u.length - 1])) {
      u = u.substring(0, u.length - 1);
    }
    return u;
  }
}
