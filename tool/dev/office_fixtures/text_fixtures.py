#!/usr/bin/env python3
"""Образцы текстовых документов для тестов предпросмотра (DOCX, ODT, RTF).

1.11.x, предпросмотр документов, план владельца 04.11.2026 (задача O1).

Что получается в test/fixtures/office/:
  text_sample.docx   — WordprocessingML, написанный здесь вручную так, как его
                       пишет Word: заголовки, оформление, списки в два уровня,
                       таблица с объединением ячеек, картинка, ссылки (связью и
                       полем HYPERLINK), сноска, разрыв страницы, кириллица;
  text_sample.odt    — тот же документ, пересохранённый LibreOffice;
  text_sample.rtf    — то же в RTF (LibreOffice: \\uN и \\'hh);
  text_cp1251.rtf    — RTF «как из русского Word»: \\ansicpg1251, \\fcharset204,
                       буквы \\'e0, список \\listtext, таблица, ссылка, картинка;
  text_unicode.rtf   — RTF с \\uN и \\ucN, без кодовой страницы кириллицы.

Запуск из корня проекта: python3 tool/dev/office_fixtures/text_fixtures.py
Нужен LibreOffice (soffice) — для ODT и RTF из DOCX; свой профиль, чтобы не
мешать другим запускам soffice.
"""

import os
import shutil
import struct
import subprocess
import sys
import tempfile
import zipfile
import zlib

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))
OUT = os.path.join(ROOT, 'test', 'fixtures', 'office')

W = 'http://schemas.openxmlformats.org/wordprocessingml/2006/main'
R = 'http://schemas.openxmlformats.org/officeDocument/2006/relationships'
NS = (f'xmlns:w="{W}" xmlns:r="{R}" '
      'xmlns:wp="http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing" '
      'xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" '
      'xmlns:pic="http://schemas.openxmlformats.org/drawingml/2006/picture" '
      'xmlns:mc="http://schemas.openxmlformats.org/markup-compatibility/2006" '
      'xmlns:w14="http://schemas.microsoft.com/office/word/2010/wordml" mc:Ignorable="w14"')


def png(w, h, pixels):
    """PNG без сторонних библиотек: pixels — список строк из (r, g, b)."""
    raw = b''.join(b'\x00' + b''.join(bytes(p) for p in row) for row in pixels)

    def chunk(kind, data):
        c = kind + data
        return struct.pack('>I', len(data)) + c + struct.pack('>I', zlib.crc32(c) & 0xFFFFFFFF)

    return (b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>IIBBBBB', w, h, 8, 2, 0, 0, 0)) +
            chunk(b'IDAT', zlib.compress(raw, 9)) + chunk(b'IEND', b''))


IMAGE = png(4, 4, [[(220, 40, 40) if (x + y) % 2 == 0 else (40, 80, 200) for x in range(4)] for y in range(4)])


def run(text, rpr=''):
    sp = ' xml:space="preserve"' if text != text.strip() else ''
    return f'<w:r>{f"<w:rPr>{rpr}</w:rPr>" if rpr else ""}<w:t{sp}>{text}</w:t></w:r>'


def para(content, ppr=''):
    return f'<w:p>{f"<w:pPr>{ppr}</w:pPr>" if ppr else ""}{content}</w:p>'


def styled(style, text, extra=''):
    return para(run(text), f'<w:pStyle w:val="{style}"/>{extra}')


def list_item(num_id, lvl, text):
    return para(run(text), f'<w:pStyle w:val="ListParagraph"/><w:numPr><w:ilvl w:val="{lvl}"/>'
                           f'<w:numId w:val="{num_id}"/></w:numPr>')


def cell(content, width, tcpr=''):
    return f'<w:tc><w:tcPr><w:tcW w:w="{width}" w:type="dxa"/>{tcpr}</w:tcPr>{content}</w:tc>'


def docx_document():
    body = []
    body.append(styled('Title', 'Отчёт о работе отдела'))
    body.append(para(
        run('Документ для проверки предпросмотра: ') +
        run('жирный', '<w:b/>') + run(', ') +
        run('курсив', '<w:i/>') + run(', ') +
        run('подчёркнутый', '<w:u w:val="single"/>') + run(', ') +
        run('красный', '<w:color w:val="C00000"/>') + run(', ') +
        run('выделенный', '<w:highlight w:val="yellow"/>') + run(' и ') +
        run('зачёркнутый', '<w:strike/>') + run(' текст.') +
        '<w:r><w:rPr><w:rStyle w:val="FootnoteReference"/></w:rPr><w:footnoteReference w:id="1"/></w:r>'))
    body.append(styled('Heading1', 'Списки'))
    body.append(list_item(1, 0, 'Первый пункт'))
    body.append(list_item(1, 1, 'Вложенный пункт'))
    body.append(list_item(1, 0, 'Второй пункт'))
    body.append(list_item(2, 0, 'Подготовка'))
    body.append(list_item(2, 1, 'Сбор данных'))
    body.append(list_item(2, 1, 'Проверка'))
    body.append(list_item(2, 0, 'Выпуск'))
    body.append(styled('Heading2', 'Таблица'))
    shd = '<w:shd w:val="clear" w:color="auto" w:fill="D9E2F3"/>'
    rows = [
        cell(para(run('Показатель', '<w:b/>')), 3000, shd) +
        cell(para(run('Значение', '<w:b/>'), '<w:jc w:val="center"/>'), 6000, '<w:gridSpan w:val="2"/>' + shd),
        cell(para(run('Период')), 3000, '<w:vMerge w:val="restart"/><w:vAlign w:val="center"/>') +
        cell(para(run('Январь')), 3000) + cell(para(run('100'), '<w:jc w:val="right"/>'), 3000),
        cell(para(''), 3000, '<w:vMerge/>') +
        cell(para(run('Февраль')), 3000) + cell(para(run('120'), '<w:jc w:val="right"/>'), 3000),
    ]
    body.append(
        '<w:tbl><w:tblPr><w:tblStyle w:val="TableGrid"/><w:tblW w:w="0" w:type="auto"/>'
        '<w:tblLook w:val="04A0" w:firstRow="1" w:lastRow="0" w:firstColumn="1" w:lastColumn="0" w:noHBand="0" w:noVBand="1"/>'
        '</w:tblPr><w:tblGrid><w:gridCol w:w="3000"/><w:gridCol w:w="3000"/><w:gridCol w:w="3000"/></w:tblGrid>' +
        ''.join(f'<w:tr>{r}</w:tr>' for r in rows) + '</w:tbl>')
    body.append(styled('Heading2', 'Картинка и ссылки'))
    emu = 4 * 9525 * 8  # 32×32 px
    drawing = (
        '<w:r><w:drawing><wp:inline distT="0" distB="0" distL="0" distR="0">'
        f'<wp:extent cx="{emu}" cy="{emu}"/><wp:docPr id="1" name="Рисунок 1" descr="Клетка"/>'
        '<a:graphic><a:graphicData uri="http://schemas.openxmlformats.org/drawingml/2006/picture">'
        '<pic:pic><pic:nvPicPr><pic:cNvPr id="1" name="image1.png"/><pic:cNvPicPr/></pic:nvPicPr>'
        '<pic:blipFill><a:blip r:embed="rId10"/><a:stretch><a:fillRect/></a:stretch></pic:blipFill>'
        f'<pic:spPr><a:xfrm><a:off x="0" y="0"/><a:ext cx="{emu}" cy="{emu}"/></a:xfrm>'
        '<a:prstGeom prst="rect"><a:avLst/></a:prstGeom></pic:spPr></pic:pic>'
        '</a:graphicData></a:graphic></wp:inline></w:drawing></w:r>')
    body.append(para(run('Картинка: ') + drawing))
    body.append(para(run('Сайт: ') + '<w:hyperlink r:id="rId11" w:history="1">' +
                     run('example.org', '<w:rStyle w:val="Hyperlink"/>') + '</w:hyperlink>'))
    body.append(para(
        run('Почта: ') +
        '<w:r><w:fldChar w:fldCharType="begin"/></w:r>'
        '<w:r><w:instrText xml:space="preserve"> HYPERLINK "mailto:info@example.org" </w:instrText></w:r>'
        '<w:r><w:fldChar w:fldCharType="separate"/></w:r>' +
        run('написать письмо', '<w:rStyle w:val="Hyperlink"/>') +
        '<w:r><w:fldChar w:fldCharType="end"/></w:r>'))
    body.append(para(''))
    body.append(para('<w:r><w:br w:type="page"/></w:r>'))
    body.append(styled('Heading1', 'Приложение'))
    body.append(para(run('Конец документа.'), '<w:jc w:val="center"/>'))
    body.append('<w:sectPr><w:pgSz w:w="11906" w:h="16838"/>'
                '<w:pgMar w:top="1134" w:right="850" w:bottom="1134" w:left="1701" w:header="708" w:footer="708" w:gutter="0"/>'
                '</w:sectPr>')
    return f'<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n<w:document {NS}><w:body>{"".join(body)}</w:body></w:document>'


STYLES = f'''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<w:styles xmlns:w="{W}">
<w:docDefaults><w:rPrDefault><w:rPr><w:rFonts w:ascii="Calibri" w:hAnsi="Calibri" w:eastAsia="Calibri" w:cs="Times New Roman"/>
<w:sz w:val="22"/><w:szCs w:val="22"/><w:lang w:val="ru-RU" w:eastAsia="en-US" w:bidi="ar-SA"/></w:rPr></w:rPrDefault>
<w:pPrDefault><w:pPr><w:spacing w:after="160" w:line="259" w:lineRule="auto"/></w:pPr></w:pPrDefault></w:docDefaults>
<w:style w:type="paragraph" w:default="1" w:styleId="Normal"><w:name w:val="Normal"/><w:qFormat/></w:style>
<w:style w:type="paragraph" w:styleId="Heading1"><w:name w:val="heading 1"/><w:basedOn w:val="Normal"/><w:next w:val="Normal"/>
<w:pPr><w:keepNext/><w:spacing w:before="240" w:after="0"/><w:outlineLvl w:val="0"/></w:pPr>
<w:rPr><w:rFonts w:ascii="Calibri Light" w:hAnsi="Calibri Light"/><w:color w:val="2F5496"/><w:sz w:val="32"/></w:rPr></w:style>
<w:style w:type="paragraph" w:styleId="Heading2"><w:name w:val="heading 2"/><w:basedOn w:val="Normal"/><w:next w:val="Normal"/>
<w:pPr><w:keepNext/><w:spacing w:before="40" w:after="0"/><w:outlineLvl w:val="1"/></w:pPr>
<w:rPr><w:b/><w:color w:val="2F5496"/><w:sz w:val="26"/></w:rPr></w:style>
<w:style w:type="paragraph" w:styleId="Title"><w:name w:val="Title"/><w:basedOn w:val="Normal"/><w:next w:val="Normal"/>
<w:pPr><w:spacing w:after="0" w:line="240" w:lineRule="auto"/><w:contextualSpacing/></w:pPr>
<w:rPr><w:spacing w:val="-10"/><w:kern w:val="28"/><w:sz w:val="56"/></w:rPr></w:style>
<w:style w:type="paragraph" w:styleId="ListParagraph"><w:name w:val="List Paragraph"/><w:basedOn w:val="Normal"/>
<w:pPr><w:ind w:left="720"/><w:contextualSpacing/></w:pPr></w:style>
<w:style w:type="paragraph" w:styleId="FootnoteText"><w:name w:val="footnote text"/><w:basedOn w:val="Normal"/>
<w:pPr><w:spacing w:after="0" w:line="240" w:lineRule="auto"/></w:pPr><w:rPr><w:sz w:val="20"/></w:rPr></w:style>
<w:style w:type="character" w:default="1" w:styleId="DefaultParagraphFont"><w:name w:val="Default Paragraph Font"/></w:style>
<w:style w:type="character" w:styleId="FootnoteReference"><w:name w:val="footnote reference"/><w:rPr><w:vertAlign w:val="superscript"/></w:rPr></w:style>
<w:style w:type="character" w:styleId="Hyperlink"><w:name w:val="Hyperlink"/><w:rPr><w:color w:val="0563C1"/><w:u w:val="single"/></w:rPr></w:style>
<w:style w:type="table" w:default="1" w:styleId="TableNormal"><w:name w:val="Normal Table"/>
<w:tblPr><w:tblInd w:w="0" w:type="dxa"/><w:tblCellMar><w:top w:w="0" w:type="dxa"/><w:left w:w="108" w:type="dxa"/>
<w:bottom w:w="0" w:type="dxa"/><w:right w:w="108" w:type="dxa"/></w:tblCellMar></w:tblPr></w:style>
<w:style w:type="table" w:styleId="TableGrid"><w:name w:val="Table Grid"/><w:basedOn w:val="TableNormal"/>
<w:pPr><w:spacing w:after="0" w:line="240" w:lineRule="auto"/></w:pPr>
<w:tblPr><w:tblBorders><w:top w:val="single" w:sz="4" w:space="0" w:color="auto"/><w:left w:val="single" w:sz="4" w:space="0" w:color="auto"/>
<w:bottom w:val="single" w:sz="4" w:space="0" w:color="auto"/><w:right w:val="single" w:sz="4" w:space="0" w:color="auto"/>
<w:insideH w:val="single" w:sz="4" w:space="0" w:color="auto"/><w:insideV w:val="single" w:sz="4" w:space="0" w:color="auto"/>
</w:tblBorders></w:tblPr></w:style>
</w:styles>'''


def lvl(i, fmt, text, left, font=None, start=1):
    rpr = f'<w:rPr><w:rFonts w:ascii="{font}" w:hAnsi="{font}" w:hint="default"/></w:rPr>' if font else ''
    return (f'<w:lvl w:ilvl="{i}"><w:start w:val="{start}"/><w:numFmt w:val="{fmt}"/><w:lvlText w:val="{text}"/>'
            f'<w:lvlJc w:val="left"/><w:pPr><w:ind w:left="{left}" w:hanging="360"/></w:pPr>{rpr}</w:lvl>')


NUMBERING = f'''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<w:numbering xmlns:w="{W}">
<w:abstractNum w:abstractNumId="0"><w:multiLevelType w:val="hybridMultilevel"/>
{lvl(0, 'bullet', '&#xF0B7;', 720, 'Symbol')}{lvl(1, 'bullet', 'o', 1440, 'Courier New')}{lvl(2, 'bullet', '&#xF0A7;', 2160, 'Wingdings')}
</w:abstractNum>
<w:abstractNum w:abstractNumId="1"><w:multiLevelType w:val="multilevel"/>
{lvl(0, 'decimal', '%1.', 360)}{lvl(1, 'decimal', '%1.%2.', 792)}{lvl(2, 'lowerLetter', '%3)', 1224)}
</w:abstractNum>
<w:num w:numId="1"><w:abstractNumId w:val="0"/></w:num>
<w:num w:numId="2"><w:abstractNumId w:val="1"/></w:num>
</w:numbering>'''

FOOTNOTES = f'''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<w:footnotes xmlns:w="{W}">
<w:footnote w:type="separator" w:id="-1"><w:p><w:r><w:separator/></w:r></w:p></w:footnote>
<w:footnote w:type="continuationSeparator" w:id="0"><w:p><w:r><w:continuationSeparator/></w:r></w:p></w:footnote>
<w:footnote w:id="1"><w:p><w:pPr><w:pStyle w:val="FootnoteText"/></w:pPr>
<w:r><w:rPr><w:rStyle w:val="FootnoteReference"/></w:rPr><w:footnoteRef/></w:r><w:r><w:t xml:space="preserve"> Данные условные.</w:t></w:r></w:p></w:footnote>
</w:footnotes>'''

CONTENT_TYPES = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
<Default Extension="xml" ContentType="application/xml"/>
<Default Extension="png" ContentType="image/png"/>
<Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>
<Override PartName="/word/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.styles+xml"/>
<Override PartName="/word/numbering.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.numbering+xml"/>
<Override PartName="/word/footnotes.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.footnotes+xml"/>
</Types>'''

PKG_RELS = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/>
</Relationships>'''

DOC_RELS = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>
<Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/numbering" Target="numbering.xml"/>
<Relationship Id="rId3" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/footnotes" Target="footnotes.xml"/>
<Relationship Id="rId10" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/image" Target="media/image1.png"/>
<Relationship Id="rId11" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/hyperlink" Target="https://example.org/" TargetMode="External"/>
</Relationships>'''


def write_docx(path):
    with zipfile.ZipFile(path, 'w', zipfile.ZIP_DEFLATED) as z:
        z.writestr('[Content_Types].xml', CONTENT_TYPES)
        z.writestr('_rels/.rels', PKG_RELS)
        z.writestr('word/_rels/document.xml.rels', DOC_RELS)
        z.writestr('word/document.xml', docx_document())
        z.writestr('word/styles.xml', STYLES)
        z.writestr('word/numbering.xml', NUMBERING)
        z.writestr('word/footnotes.xml', FOOTNOTES)
        z.writestr('word/media/image1.png', IMAGE)


def rtf_hex(text, codepage):
    """Текст для RTF «как пишет Word»: ASCII как есть, остальное — \\'hh."""
    out = []
    for ch in text:
        if ch in '\\{}':
            out.append('\\' + ch)
        elif ord(ch) < 128:
            out.append(ch)
        else:
            out.extend(f"\\'{b:02x}" for b in ch.encode(codepage))
    return ''.join(out)


def rtf_cp1251():
    t = lambda s: rtf_hex(s, 'cp1251')  # noqa: E731
    pict = IMAGE.hex()
    rows = []
    for a, b in [('Город', 'Количество'), ('Тверь', '12'), ('Казань', '7')]:
        rows.append('\\trowd\\trgaph108\\trleft-108'
                    '\\clbrdrt\\brdrs\\brdrw10\\clbrdrl\\brdrs\\brdrw10\\clbrdrb\\brdrs\\brdrw10\\clbrdrr\\brdrs\\brdrw10\\cellx3000'
                    '\\clbrdrt\\brdrs\\brdrw10\\clbrdrl\\brdrs\\brdrw10\\clbrdrb\\brdrs\\brdrw10\\clbrdrr\\brdrs\\brdrw10\\cellx6000'
                    f'\\pard\\intbl {t(a)}\\cell\\pard\\intbl\\qr {t(b)}\\cell\\row\n')
    return (
        '{\\rtf1\\ansi\\ansicpg1251\\deff0\\deflang1049'
        '{\\fonttbl{\\f0\\froman\\fcharset204\\fprq2 Times New Roman;}{\\f1\\fswiss\\fcharset204\\fprq2 Arial;}'
        '{\\f2\\fnil\\fcharset2\\fprq2 Symbol;}{\\f3\\fmodern\\fcharset204\\fprq1 Courier New;}}\n'
        '{\\colortbl ;\\red192\\green0\\blue0;\\red0\\green0\\blue255;\\red255\\green255\\blue0;}\n'
        '{\\stylesheet{\\s0 Normal;}{\\s1 heading 1;}}\n'
        '{\\info{\\title ' + t('Служебная записка') + '}{\\author ' + t('Отдел') + '}}\n'
        '\\paperw11906\\paperh16838\\margl1701\\margr850\\margt1134\\margb1134\n'
        '{\\header \\pard\\plain ' + t('Колонтитул — не показывается') + '\\par}\n'
        '\\pard\\plain\\s1\\qc\\sb240\\sa120\\b\\fs32 ' + t('Служебная записка') + '\\par\n'
        '\\pard\\plain\\fi709\\sa120\\fs28 ' + t('Прошу рассмотреть ') + '{\\b ' + t('вопрос') + '} ' +
        t('о закупке ') + '{\\i ' + t('оборудования') + '} ' + t('и ') +
        '{\\ul ' + t('сообщить') + '} ' + t('решение до ') + '{\\cf1 ' + t('пятницы') + '}' +
        t('. Срок — ') + '{\\highlight3 ' + t('срочно') + '}.\\par\n'
        '{\\pntext\\f2\\\'b7\\tab}\\pard\\fi-360\\li720 ' + t('Пункт первый') + '\\par\n'
        '{\\listtext\\f2\\\'b7\\tab}\\pard\\fi-360\\li720 ' + t('Пункт второй') + '\\par\n'
        '{\\listtext 1.\\tab}\\pard\\fi-360\\li720 ' + t('Нумерованный пункт') + '\\par\n'
        '\\pard\\sa120 ' + ''.join(rows) +
        '\\pard\\sa120 ' + t('Сайт: ') +
        '{\\field{\\*\\fldinst{HYPERLINK "https://example.org/"}}{\\fldrslt{\\ul\\cf2 example.org}}}\\par\n'
        '\\pard ' + t('Схема: ') +
        '{\\pict\\pngblip\\picw4\\pich4\\picwgoal480\\pichgoal480 ' + pict + '}\\par\n'
        '\\pard ' + t('Моноширинный: ') + '{\\f3 code()}\\line ' + t('новая строка') +
        '\\tab ' + t('после табуляции') + '\\par\n'
        '{\\*\\generator Ogneliss fixtures;}'
        '\\pard ' + t('Ёлка и съёмка: ') + "\\'a8\\'b8" + '\\par\n'
        '}')


def rtf_unicode():
    def u(s):
        out = []
        for ch in s:
            if ch in '\\{}':
                out.append('\\' + ch)
            elif ord(ch) < 128:
                out.append(ch)
            else:
                code = ord(ch)
                if code > 32767:
                    code -= 65536
                out.append(f'\\u{code}?')
        return ''.join(out)

    return (
        '{\\rtf1\\ansi\\ansicpg1252\\uc1\\deff0'
        '{\\fonttbl{\\f0\\fswiss Arial;}}'
        '{\\colortbl;\\red0\\green128\\blue0;}'
        '\\pard\\qc\\b\\fs36 ' + u('Привет, мир') + '\\b0\\par'
        '\\pard\\ql\\fs24 ' + u('Греческий: Ωμέγα; ') +
        '{\\uc2\\u8364\\\'80\\\'80}' + u(' — евро, ') + '{\\cf1 ' + u('зелёный') + '}' +
        u(', знак ') + '\\u-10179?\\u-8704?' + u(' и «кавычки».') + '\\par'
        '\\pard\\li360 {\\super 2}\\nosupersub  H{\\sub 2}O\\par'
        '}')


def main():
    os.makedirs(OUT, exist_ok=True)
    docx = os.path.join(OUT, 'text_sample.docx')
    write_docx(docx)
    with open(os.path.join(OUT, 'text_cp1251.rtf'), 'w', encoding='ascii', newline='\r\n') as f:
        f.write(rtf_cp1251())
    with open(os.path.join(OUT, 'text_unicode.rtf'), 'w', encoding='ascii', newline='\r\n') as f:
        f.write(rtf_unicode())

    soffice = shutil.which('soffice')
    if not soffice:
        sys.exit('soffice не найден: ODT и RTF из DOCX не обновлены')
    with tempfile.TemporaryDirectory() as tmp:
        profile = 'file:///tmp/lo_o1'
        for fmt in ('odt', 'rtf'):
            subprocess.run([soffice, '--headless', f'-env:UserInstallation={profile}', '--convert-to', fmt,
                            '--outdir', tmp, docx], check=True, stdout=subprocess.DEVNULL)
            shutil.copy(os.path.join(tmp, f'text_sample.{fmt}'), os.path.join(OUT, f'text_sample.{fmt}'))
    for name in sorted(os.listdir(OUT)):
        if name.startswith('text_'):
            print(f'{name}: {os.path.getsize(os.path.join(OUT, name))} байт')


if __name__ == '__main__':
    main()
