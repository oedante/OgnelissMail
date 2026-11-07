#!/usr/bin/env python3
"""Образцы PDF для теста текста PDF (lib/services/documents/pdf_text.dart, 1.15.1).

Пишет test/fixtures/pdf/:
  winansi.pdf      — Helvetica (WinAnsi), TJ с кернингом, экранирование, ä
  differences.pdf  — кириллица через /Differences (afii100xx, uni0416)
  type0.pdf        — составной шрифт Identity-H с таблицей ToUnicode
  objstm.pdf       — страница и шрифт в сжатом потоке объектов (PDF 1.5)
  rc4_40.pdf, rc4_128.pdf, aes_128.pdf, aes_256.pdf — winansi.pdf под
                     стандартной защитой без пароля на открытие (pypdf)
  locked.pdf       — с паролем на открытие (текста быть не должно)

    python3 tool/dev/pdf_fixtures.py

Нужен pypdf (BSD-3-Clause, только для этого скрипта, в приложение не
входит). Тексты — свои, без чужих документов.
"""

import os
import sys
import zlib

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
OUT = os.path.join(ROOT, 'test', 'fixtures', 'pdf')


def build(objects, root=1, version='1.4'):
    """PDF из списка тел объектов (bytes), с таблицей xref."""
    out = bytearray(f'%PDF-{version}\n%\xe2\xe3\xcf\xd3\n'.encode('latin-1'))
    offsets = []
    for i, body in enumerate(objects, 1):
        offsets.append(len(out))
        out += f'{i} 0 obj\n'.encode() + body + b'\nendobj\n'
    xref = len(out)
    out += f'xref\n0 {len(objects) + 1}\n0000000000 65535 f \n'.encode()
    for off in offsets:
        out += f'{off:010d} 00000 n \n'.encode()
    out += f'trailer\n<< /Size {len(objects) + 1} /Root {root} 0 R /ID [<0123456789ABCDEF0123456789ABCDEF> <0123456789ABCDEF0123456789ABCDEF>] >>\nstartxref\n{xref}\n%%EOF\n'.encode()
    return bytes(out)


def stream(dict_body, data, compress=True):
    if compress:
        data = zlib.compress(data)
        dict_body += b' /Filter /FlateDecode'
    return b'<< ' + dict_body + f' /Length {len(data)} >>\nstream\n'.encode() + data + b'\nendstream'


def page_doc(font_obj, content, extra=()):
    objs = [
        b'<< /Type /Catalog /Pages 2 0 R >>',
        b'<< /Type /Pages /Kids [3 0 R] /Count 1 >>',
        b'<< /Type /Page /Parent 2 0 R /MediaBox [0 0 595 842] /Resources << /Font << /F1 4 0 R >> >> /Contents 5 0 R >>',
        font_obj,
        stream(b'', content),
        *extra,
    ]
    return build(objs)


def winansi():
    content = (
        b'BT /F1 12 Tf 72 760 Td (Invoice No. 2026-117) Tj 0 -16 Td '
        b'[(Sm) 20 (eta) -400 (total)] TJ 0 -16 Td (\\(net\\) price: 100 \\344 EUR) Tj ET\n'
        b'BT /F1 12 Tf 1 0 0 1 72 700 Tm (Second) Tj 1 0 0 1 72 684 Tm (line) Tj ET'
    )
    return page_doc(b'<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica /Encoding /WinAnsiEncoding >>', content)


def differences():
    # Коды 0x80..: П р и в е т , Ж у к (uni0416 — «Ж»).
    names = '/afii10033 /afii10082 /afii10074 /afii10067 /afii10070 /afii10084 /uni0416 /afii10085 /afii10076'
    enc = f'<< /Type /Encoding /BaseEncoding /WinAnsiEncoding /Differences [128 {names}] >>'.encode()
    content = b'BT /F1 14 Tf 72 760 Td <808182838485> Tj ( ) Tj <868788> Tj ET'
    return page_doc(b'<< /Type /Font /Subtype /Type1 /BaseFont /Times-Roman /Encoding 6 0 R >>', content, (enc,))


def type0():
    cmap = (
        b'/CIDInit /ProcSet findresource begin 12 dict begin begincmap\n'
        b'/CMapName /Test def 1 begincodespacerange <0000> <FFFF> endcodespacerange\n'
        b'2 beginbfchar <0003> <0020> <0010> <0421> endbfchar\n'
        b'1 beginbfrange <0020> <0022> [<043C> <0435> <0442>] endbfrange\n'
        b'1 beginbfrange <0030> <0032> <0430> endbfrange\n'
        b'endcmap CMapName currentdict /CMap defineresource pop end end'
    )
    font = b'<< /Type /Font /Subtype /Type0 /BaseFont /TestFont /Encoding /Identity-H /DescendantFonts [7 0 R] /ToUnicode 6 0 R >>'
    desc = b'<< /Type /Font /Subtype /CIDFontType2 /BaseFont /TestFont /CIDSystemInfo << /Registry (Adobe) /Ordering (Identity) /Supplement 0 >> >>'
    # «С» «м» «е» «т», пробел, «а» «б» «в»: 0010 0020 0021 0022 0003 0030 0031 0032
    content = b'BT /F1 12 Tf 72 760 Td <0010002000210022> Tj <0003> Tj <003000310032> Tj ET'
    return page_doc(font, content, (stream(b'', cmap), desc))


def objstm():
    """1 — каталог, 6 — поток объектов (3–5), 7 — содержимое, 2 — поток xref."""
    packed = [
        b'<< /Type /Pages /Kids [4 0 R] /Count 1 >>',
        b'<< /Type /Page /Parent 3 0 R /MediaBox [0 0 595 842] /Resources << /Font << /F1 5 0 R >> >> /Contents 7 0 R >>',
        b'<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica /Encoding /WinAnsiEncoding >>',
    ]
    header, body = [], bytearray()
    for i, o in enumerate(packed, 3):
        header.append(f'{i} {len(body)}')
        body += o + b'\n'
    head = (' '.join(header) + '\n').encode()
    objstm_body = stream(f'/Type /ObjStm /N {len(packed)} /First {len(head)}'.encode(), head + bytes(body))
    content = stream(b'', b'BT /F1 12 Tf 72 760 Td (Packed objects work) Tj ET')
    out = bytearray(b'%PDF-1.5\n%\xe2\xe3\xcf\xd3\n')
    offsets = {}
    for num, obj in [(1, b'<< /Type /Catalog /Pages 3 0 R >>'), (6, objstm_body), (7, content)]:
        offsets[num] = len(out)
        out += f'{num} 0 obj\n'.encode() + obj + b'\nendobj\n'
    offsets[2] = len(out)
    rows = bytearray()
    for n in range(8):
        if n == 0:
            rows += bytes([0, 0, 0, 0, 0, 0xFF, 0xFF])
        elif n in (3, 4, 5):
            rows += bytes([2]) + (6).to_bytes(4, 'big') + (n - 3).to_bytes(2, 'big')
        else:
            rows += bytes([1]) + offsets[n].to_bytes(4, 'big') + (0).to_bytes(2, 'big')
    xref = stream(b'/Type /XRef /Size 8 /W [1 4 2] /Root 1 0 R', bytes(rows))
    out += b'2 0 obj\n' + xref + b'\nendobj\n'
    out += f'startxref\n{offsets[2]}\n%%EOF\n'.encode()
    return bytes(out)


def encrypted(src, name, algorithm, user=''):
    from pypdf import PdfReader, PdfWriter  # pylint: disable=import-outside-toplevel
    import io  # pylint: disable=import-outside-toplevel
    w = PdfWriter(clone_from=PdfReader(io.BytesIO(src)))
    w.encrypt(user_password=user, owner_password='owner-secret', algorithm=algorithm)
    with open(os.path.join(OUT, name), 'wb') as f:
        w.write(f)


def main():
    os.makedirs(OUT, exist_ok=True)
    files = {'winansi.pdf': winansi(), 'differences.pdf': differences(), 'type0.pdf': type0(), 'objstm.pdf': objstm()}
    for name, data in files.items():
        with open(os.path.join(OUT, name), 'wb') as f:
            f.write(data)
    for name, alg in [('rc4_40.pdf', 'RC4-40'), ('rc4_128.pdf', 'RC4-128'), ('aes_128.pdf', 'AES-128'),
                      ('aes_256.pdf', 'AES-256')]:
        encrypted(files['winansi.pdf'], name, alg)
    # С паролем на открытие — текста нет (пароль приложению не известен).
    encrypted(files['winansi.pdf'], 'locked.pdf', 'AES-128', user='secret')
    print('\n'.join(sorted(os.listdir(OUT))))
    return 0


if __name__ == '__main__':
    sys.exit(main())
