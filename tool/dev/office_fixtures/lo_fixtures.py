#!/usr/bin/env python3
"""Образцы старых форматов Office из LibreOffice (1.15.1): книга Excel 97 со
стандартным паролем «VelvetSweatshop» и с паролем на открытие, Word 97 с колонтитулами и примечанием, PowerPoint 97 с заметками
докладчика и диаграммой.

    soffice --headless --accept="socket,host=localhost,port=2002;urp;" &
    python3 tool/dev/office_fixtures/lo_fixtures.py test/fixtures/office

Нужны LibreOffice и его модуль uno (только для этого скрипта). Тексты —
свои. Excel 95 LibreOffice больше не записывает — книгу BIFF5 с кодовой
страницей 1251 собирает biff5_fixture.py.
"""

import os
import sys
import time

import uno  # pylint: disable=import-error
from com.sun.star.beans import PropertyValue  # pylint: disable=import-error


def props(**kw):
    out = []
    for k, v in kw.items():
        p = PropertyValue()
        p.Name = k
        p.Value = v
        out.append(p)
    return tuple(out)


def connect():
    local = uno.getComponentContext()
    resolver = local.ServiceManager.createInstanceWithContext('com.sun.star.bridge.UnoUrlResolver', local)
    for _ in range(60):
        try:
            ctx = resolver.resolve('uno:socket,host=localhost,port=2002;urp;StarOffice.ComponentContext')
            return ctx.ServiceManager.createInstanceWithContext('com.sun.star.frame.Desktop', ctx)
        except Exception:  # pylint: disable=broad-except
            time.sleep(1)
    raise SystemExit('LibreOffice не отвечает')


def url(path):
    return uno.systemPathToFileUrl(os.path.abspath(path))


def calc(desktop, out):
    doc = desktop.loadComponentFromURL('private:factory/scalc', '_blank', 0, props(Hidden=True))
    sheet = doc.Sheets.getByIndex(0)
    sheet.Name = 'Смета'
    rows = [('Наименование', 'Кол-во', 'Цена'), ('Кирпич облицовочный', 1200, 35.5), ('Цемент М500', 40, 420.0),
            ('Итого', None, None)]
    for r, row in enumerate(rows):
        for c, v in enumerate(row):
            if v is None:
                continue
            cell = sheet.getCellByPosition(c, r)
            if isinstance(v, str):
                cell.setString(v)
            else:
                cell.setValue(v)
    sheet.getCellByPosition(2, 3).setFormula('=B2*C2+B3*C3')
    doc.Sheets.insertNewByName('Склад', 1)
    doc.Sheets.getByName('Склад').getCellByPosition(0, 0).setString('Остатки на 01.11.2026')
    doc.storeToURL(url(os.path.join(out, 'velvet.xls')), props(FilterName='MS Excel 97', Password='VelvetSweatshop'))
    doc.storeToURL(url(os.path.join(out, 'xls_password.xls')), props(FilterName='MS Excel 97', Password='secret'))
    doc.close(True)


def writer(desktop, out):
    doc = desktop.loadComponentFromURL('private:factory/swriter', '_blank', 0, props(Hidden=True))
    text = doc.Text
    cursor = text.createTextCursor()
    text.insertString(cursor, 'Договор поставки № 17', False)
    text.insertControlCharacter(cursor, 0, False)  # PARAGRAPH_BREAK
    text.insertString(cursor, 'Поставщик обязуется передать товар в срок.', False)
    style = doc.StyleFamilies.getByName('PageStyles').getByName('Standard')
    style.HeaderIsOn = True
    style.FooterIsOn = True
    style.HeaderText.setString('ООО «Ромашка» — конфиденциально')
    style.FooterText.setString('Страница договора')
    note = doc.createInstance('com.sun.star.text.textfield.Annotation')
    note.Author = 'Иванов'
    note.Content = 'Проверить сроки оплаты'
    text.insertTextContent(cursor, note, False)
    doc.storeToURL(url(os.path.join(out, 'doc_header_comment.doc')), props(FilterName='MS Word 97'))
    doc.close(True)


def impress(desktop, out):
    doc = desktop.loadComponentFromURL('private:factory/simpress', '_blank', 0, props(Hidden=True))
    page = doc.DrawPages.getByIndex(0)
    for i in range(page.Count):
        shape = page.getByIndex(i)
        if shape.ShapeType == 'com.sun.star.presentation.TitleTextShape':
            shape.String = 'Итоги квартала'
        elif shape.ShapeType == 'com.sun.star.presentation.SubtitleShape':
            shape.String = 'Продажи выросли'
    notes = page.NotesPage
    for i in range(notes.Count):
        shape = notes.getByIndex(i)
        if shape.ShapeType == 'com.sun.star.presentation.NotesShape':
            shape.String = 'Сказать про новых клиентов из Казани'
    # Диаграмма: OLE-объект Chart с подписями рядов.
    chart = doc.createInstance('com.sun.star.drawing.OLE2Shape')
    page.add(chart)
    chart.CLSID = '12dcae26-281f-416f-a234-c3086127382e'
    size = uno.createUnoStruct('com.sun.star.awt.Size')
    size.Width, size.Height = 12000, 7000
    chart.Size = size
    model = chart.Model
    if model is not None:
        data = model.Data
        data.setRowDescriptions(('Москва', 'Казань'))
        data.setColumnDescriptions(('Январь', 'Февраль'))
        data.setData(((10.0, 12.0), (7.0, 9.0)))
        model.Title.String = 'Выручка по городам' if model.HasMainTitle else ''
        model.HasMainTitle = True
        model.Title.String = 'Выручка по городам'
    doc.storeToURL(url(os.path.join(out, 'ppt_notes_chart.ppt')), props(FilterName='MS PowerPoint 97'))
    doc.close(True)


def main():
    out = sys.argv[1] if len(sys.argv) > 1 else 'test/fixtures/office'
    os.makedirs(out, exist_ok=True)
    desktop = connect()
    calc(desktop, out)
    writer(desktop, out)
    impress(desktop, out)
    print('готово:', out)
    return 0


if __name__ == '__main__':
    sys.exit(main())
