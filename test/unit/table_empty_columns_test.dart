// Пустые колонки таблицы рассылки (2.2.1, письмо владельца «Welcome to the
// Community» 10.11.2026): таблица на всю ширину из пустых <td></td> по краям
// и колонки текста width:560px. Раньше «не у всех колонок ширина задана» —
// поровну, и текст шёл узкой третью справа; теперь пустая колонка без
// ширины места не занимает, как в браузере.

import 'package:flutter_test/flutter_test.dart';
import 'package:ogneliss/features/mail/widgets/mail_native_body.dart';
import 'package:ogneliss/features/mail/widgets/span_table.dart' show fitColumnWidths;

NBlock? _firstTable(List<NBlock> blocks) {
  for (final b in blocks) {
    if (b.kind == NBlockKind.table) return b;
  }
  return null;
}

void main() {
  test('доли колонок: пустые без ширины — 0, остальные — по ширине или поровну', () {
    expect(tableColumnWidths([0, 560, 0], [false, true, false]), [0, 560, 0]);
    expect(tableColumnWidths([0, 0, 0], [false, true, true]), [0, 1, 1]);
    expect(tableColumnWidths([20, 560, 0], [false, true, false]), [20, 560, 0], reason: 'отступ с шириной — остаётся');
    expect(tableColumnWidths([300, 0], [true, true]), [1, 1], reason: 'ширина не у всех — поровну, как раньше');
    expect(tableColumnWidths([0, 0], [false, false]), [1, 1], reason: 'всё пусто — поровну');
  });

  test('письмо рассылки: колонка текста — почти вся ширина', () {
    const html = '<table width="100%" border="0" cellpadding="0" cellspacing="0" style="background-color:#f8f8f8">'
        '<tbody><tr height="40"></tr>'
        '<tr><td></td><td style="width: 560px"><center>Логотип</center></td></tr>'
        '<tr height="20"></tr>'
        '<tr><td></td><td style="background:#ffffff;padding:26px 40px">Hi oedante,<br><br>'
        '<p>Welcome to the Google Cloud Security Community! We are excited to have you join.</p></td></tr>'
        '<tr height="60"><td></td><td><center><p>We look forward to seeing you!</p></center></td><td></td></tr>'
        '</tbody></table>';
    final mail = buildNativeMail(html);
    expect(mail, isNotNull);
    final table = _firstTable(mail!.blocks);
    expect(table, isNotNull);
    final rows = table!.table!;
    final cols = rows.map((r) => r.fold<int>(0, (a, c) => a + c.colSpan)).reduce((a, b) => a > b ? a : b);
    expect(cols, 3);
    final flex = List<double>.filled(cols, 0);
    final filled = List<bool>.filled(cols, false);
    for (final r in rows) {
      var c = 0;
      for (final cell in r) {
        if (cell.colSpan == 1 && cell.flex > 1 && flex[c] == 0) flex[c] = cell.flex;
        if (cell.colSpan == 1 && !tableCellIsEmpty(cell)) filled[c] = true;
        c += cell.colSpan;
      }
    }
    final widths = fitColumnWidths(tableColumnWidths(flex, filled), const [8, 60, 8], 390);
    expect(widths[1], greaterThan(390 * 0.9), reason: 'текст — почти вся ширина экрана');
  });
}
