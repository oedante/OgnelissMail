// Один префикс темы при ответе и пересылке, как в Outlook (1.5.12).

import 'package:flutter_test/flutter_test.dart';
import 'package:ogneliss/core/utils/subject_prefix.dart';

void main() {
  test('ответ и пересылка — один префикс RE: / FW:', () {
    expect(SubjectPrefix.reply('RE: ЦФО у специалистов ТОиРО'), 'RE: ЦФО у специалистов ТОиРО');
    expect(SubjectPrefix.forward('RE: ЦФО у специалистов ТОиРО'), 'FW: ЦФО у специалистов ТОиРО');
    expect(SubjectPrefix.reply('Fwd: RE: ЦФО'), 'RE: ЦФО');
    expect(SubjectPrefix.forward('Re[2]: RE(3): fw: Тема'), 'FW: Тема');
    expect(SubjectPrefix.reply('Ответ: Отв: Тема'), 'RE: Тема');
    expect(SubjectPrefix.reply('Пер: AW: WG: x'), 'RE: x');
    expect(SubjectPrefix.reply('Отчёт'), 'RE: Отчёт');
  });

  test('слова в начале темы, похожие на префикс, остаются', () {
    expect(SubjectPrefix.reply('Report: q3'), 'RE: Report: q3');
    expect(SubjectPrefix.reply('Тема: Re: внутри'), 'RE: Тема: Re: внутри');
    expect(SubjectPrefix.forward('Resume'), 'FW: Resume');
  });
}
