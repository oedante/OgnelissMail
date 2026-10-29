// Готовые шаблоны ответов (1.8.0+118).
import 'package:flutter_test/flutter_test.dart';
import 'package:ogneliss/features/compose/providers/templates_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('готовый шаблон хранится ссылкой, текст — на языке приложения', () {
    const t = ReplyTemplate(title: '', body: '', builtIn: 'tmplFyi');
    expect(t.toJson(), {'builtIn': 'tmplFyi'});
    final r = ReplyTemplate.fromJson(t.toJson()).resolve((k) => 'tr:$k');
    expect(r.title, 'tr:tmplFyiT');
    expect(r.body, 'tr:tmplFyiB');
    const own = ReplyTemplate(title: 'A', body: 'B');
    expect(own.resolve((k) => 'x'), same(own));
    expect(ReplyTemplate.fromJson(const {'builtIn': 'unknown', 'title': 'T', 'body': 'B'}).builtIn, isNull);
  });

  test('готовые шаблоны добавляются один раз, удалённые не возвращаются', () async {
    SharedPreferences.setMockInitialValues({});
    final p = await SharedPreferences.getInstance();
    final n = TemplatesNotifier(p);
    expect(n.state.length, builtInTemplateIds.length);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    await n.removeAt(0);
    final again = TemplatesNotifier(p);
    expect(again.state.length, builtInTemplateIds.length - 1);
  });
}
