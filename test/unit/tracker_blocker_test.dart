// Блокировка трекеров: только настоящие трекеры, с причиной для журнала.
import 'package:flutter_test/flutter_test.dart';
import 'package:ogneliss/services/security/tracker_blocker.dart';

void main() {
  const keepImages = TrackerBlockOptions(enabled: true, blockExternal: false);

  test('пиксель 1×1 — трекер', () {
    final r = TrackerBlockerNotifier.block(
        '<img width="1" height="1" src="https://news.example.com/o.gif?u=me@corp.ru">', keepImages);
    expect(r.blockedCount, 1);
    expect(r.items.single.reason, BlockReason.pixel);
    expect(r.items.single.path, '/o.gif'); // без параметров
  });

  test('пиксель стилем и скрытая картинка', () {
    final r = TrackerBlockerNotifier.block(
        '<img style="width:1px;height:1px" src="https://a.ru/p.png">'
        '<img style="display: none" src="https://b.ru/x.png">', keepImages);
    expect(r.items.map((i) => i.reason), [BlockReason.pixel, BlockReason.hidden]);
  });

  test('сервис отслеживания — по хосту', () {
    final r = TrackerBlockerNotifier.block('<img src="https://u123.ct.sendgrid.net/wf/open?x=1">', keepImages);
    expect(r.items.single.reason, BlockReason.trackerService);
    expect(r.items.single.host, 'u123.ct.sendgrid.net');
  });

  test('слова open/track/analytics в ПУТИ — не трекер (раньше блокировалось)', () {
    const html = '<img src="https://cdn.company.ru/img/open-door.png">'
        '<img src="https://corp.ru/analytics/chart.png" width="600" height="300">';
    final r = TrackerBlockerNotifier.block(html, keepImages);
    expect(r.blockedCount, 0);
    expect(r.html, contains('open-door.png'));
  });

  test('внешние картинки скрываются отдельно и не считаются трекерами', () {
    final r = TrackerBlockerNotifier.block('<img src="https://x.ru/logo.png">',
        const TrackerBlockOptions(enabled: true, blockExternal: true));
    expect(r.blockedCount, 0);
    expect(r.externalBlocked, 1);
    expect(r.items.single.reason, BlockReason.external);
  });

  test('встроенные картинки (cid:, data:) не трогаются', () {
    const html = '<img src="cid:logo@x"><img width="1" height="1" src="data:image/gif;base64,R0lG">';
    final r = TrackerBlockerNotifier.block(html, const TrackerBlockOptions(enabled: true, blockExternal: true));
    expect(r.items, isEmpty);
    expect(r.html, html);
  });

  test('сводка для журнала', () {
    expect(describeBlocked(const [
      BlockedImage(reason: BlockReason.pixel, host: 'a.ru', path: '/'),
      BlockedImage(reason: BlockReason.pixel, host: 'a.ru', path: '/2'),
    ]), 'pixel: a.ru ×2');
  });
}
