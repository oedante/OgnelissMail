#!/usr/bin/env python3
"""Проверки скриптов CI: лицензии (license_check.py), отчёт уязвимостей
(osv_report.py), замеры скорости (tool/perf/perf_check.py).

    python3 -m unittest discover -s tool/dev -p 'test_*.py'

Только стандартная библиотека (1.9.x, просьба владельца 31.10.2026).
"""

import json
import os
import sys
import tempfile
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(HERE, '..', 'perf'))

import license_check as lc  # noqa: E402
import osv_report as osv  # noqa: E402
import perf_check as pc  # noqa: E402

MIT = '''MIT License

Copyright (c) 2020 Someone

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.
'''

BSD3 = '''Copyright 2014, the Dart project authors.

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are
met:
    * Redistributions of source code must retain the above copyright
      notice, this list of conditions and the following disclaimer.
    * Neither the name of Google LLC nor the names of its
      contributors may be used to endorse or promote products derived
      from this software without specific prior written permission.
'''

BSD2 = '''Copyright (c) 2019 X
Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are met:
1. Redistributions of source code must retain the above copyright notice.
2. Redistributions in binary form must reproduce the above copyright notice.
'''

APACHE = '''
                                 Apache License
                           Version 2.0, January 2004
                        http://www.apache.org/licenses/
'''

MPL = '''Mozilla Public License Version 2.0
==================================
1.12. "Secondary License"
    means either the GNU General Public License, Version 2.0, the GNU Lesser
    General Public License, Version 2.1, the GNU Affero General Public
    License, Version 3.0, or any later versions of those licenses.
'''

GPL = '''                    GNU GENERAL PUBLIC LICENSE
                       Version 3, 29 June 2007
'''

LGPL = '''                   GNU LESSER GENERAL PUBLIC LICENSE
                       Version 2.1, February 1999
'''

AGPL = 'GNU AFFERO GENERAL PUBLIC LICENSE\nVersion 3, 19 November 2007\n'

NONCOMMERCIAL = 'You may use this software for non-commercial purposes only. All other rights reserved.'


class LicenseTextTest(unittest.TestCase):
    def test_permissive(self):
        self.assertEqual(lc.text_verdict(MIT), ('MIT', 'ok'))
        self.assertEqual(lc.text_verdict(BSD3), ('BSD-3-Clause', 'ok'))
        self.assertEqual(lc.text_verdict(BSD2), ('BSD-2-Clause', 'ok'))
        self.assertEqual(lc.text_verdict(APACHE), ('Apache-2.0', 'ok'))

    def test_mpl_mentions_gpl_only_as_definition(self):
        # MPL-2.0 называет GPL/LGPL/AGPL «вторичными лицензиями» — это не GPL.
        self.assertEqual(lc.text_verdict(MPL), ('MPL-2.0', 'ok'))

    def test_copyleft_and_noncommercial_fail(self):
        for text, name in ((GPL, 'GPL'), (LGPL, 'LGPL'), (AGPL, 'AGPL'), (NONCOMMERCIAL, 'non-commercial')):
            lic, verdict = lc.text_verdict(text)
            self.assertEqual(verdict, 'bad', text)
            self.assertIn(name, lic)

    def test_dual_license_needs_allowlist(self):
        lic, verdict = lc.text_verdict(MIT + '\n\nAlternatively:\n' + GPL)
        self.assertEqual(verdict, 'bad')
        self.assertIn('MIT', lic)

    def test_unknown_and_missing(self):
        self.assertEqual(lc.text_verdict('All rights reserved.')[1], 'unknown')
        self.assertEqual(lc.text_verdict(None)[1], 'unknown')


class SpdxTest(unittest.TestCase):
    def test_expressions(self):
        self.assertEqual(lc.spdx_verdict('MIT'), ('MIT', 'ok'))
        self.assertEqual(lc.spdx_verdict('(MIT OR GPL-3.0)'), ('MIT', 'ok'))
        self.assertEqual(lc.spdx_verdict('(MIT AND BSD-3-Clause)')[1], 'ok')
        self.assertEqual(lc.spdx_verdict('MIT AND GPL-2.0')[1], 'bad')
        self.assertEqual(lc.spdx_verdict('GPL-2.0-only')[1], 'bad')
        self.assertEqual(lc.spdx_verdict('SSPL-1.0')[1], 'bad')
        self.assertEqual(lc.spdx_verdict('')[1], 'unknown')
        self.assertEqual(lc.spdx_verdict('SEE LICENSE IN LICENSE.txt')[1], 'unknown')
        self.assertEqual(lc.spdx_verdict('WTFPL')[1], 'unknown')


class AllowlistTest(unittest.TestCase):
    def test_parse(self):
        with tempfile.NamedTemporaryFile('w', suffix='.txt', delete=False, encoding='utf-8') as f:
            f.write('# comment\n\npub:a MIT dual MIT/GPL, used under MIT\nb BSD-3-Clause reason\n'
                    'npm:c ISC because\nbroken MIT\n')
        try:
            entries, errors = lc.load_allowlist(f.name)
        finally:
            os.unlink(f.name)
        self.assertEqual(set(entries), {'pub:a', 'pub:b', 'npm:c'})
        self.assertEqual(entries['pub:a'], ('MIT', 'dual MIT/GPL, used under MIT'))
        self.assertEqual(len(errors), 1)


def _osv_result(name, version, eco, fixed, score, sev, intro='0'):
    events = [{'introduced': intro}] + ([{'fixed': fixed}] if fixed else [])
    return {'results': [{'source': {'path': '/github/workspace/server/x/package-lock.json'}, 'packages': [{
        'package': {'name': name, 'version': version, 'ecosystem': eco},
        'vulnerabilities': [{'id': 'GHSA-test', 'summary': 'DoS', 'database_specific': {'severity': sev},
                             'affected': [{'package': {'name': name, 'ecosystem': eco},
                                           'ranges': [{'type': 'SEMVER', 'events': events}]}]}],
        'groups': [{'ids': ['GHSA-test'], 'aliases': ['CVE-1'], 'max_severity': score}],
    }]}]}


class OsvReportTest(unittest.TestCase):
    def setUp(self):
        self.project = tempfile.mkdtemp()

    def test_high_with_fix_blocks(self):
        f = osv.findings(_osv_result('body-parser', '1.20.8', 'npm', '1.20.9', '7.5', 'HIGH'), self.project)
        self.assertEqual(len(f), 1)
        self.assertTrue(f[0]['blocking'])
        self.assertEqual(f[0]['fixed'], ['1.20.9'])
        self.assertEqual(f[0]['source'], 'server/x/package-lock.json')

    def test_moderate_or_unfixed_warn(self):
        self.assertFalse(osv.findings(_osv_result('qs', '6.16.0', 'npm', '6.16.1', '5.3', 'MODERATE'),
                                      self.project)[0]['blocking'])
        self.assertFalse(osv.findings(_osv_result('qs', '6.16.0', 'npm', None, '9.8', 'CRITICAL'),
                                      self.project)[0]['blocking'])

    def test_severity_without_score(self):
        f = osv.findings(_osv_result('a', '1.0.0', 'Pub', '1.0.1', '', 'CRITICAL'), self.project)
        self.assertEqual(f[0]['severity'], 'CRITICAL')

    def test_fix_for_other_branch_only(self):
        # Исправлено только в старой ветке (1.x), у нас 2.x без исправления.
        data = _osv_result('lib', '2.1.0', 'npm', '1.5.0', '8.0', 'HIGH')
        data['results'][0]['packages'][0]['vulnerabilities'][0]['affected'][0]['ranges'].append(
            {'type': 'SEMVER', 'events': [{'introduced': '2.0.0'}]})
        f = osv.findings(data, self.project)
        # Диапазон 2.x без исправления, но известное исправление есть —
        # осторожный вариант: считаем, что исправление есть.
        self.assertTrue(f[0]['fixed'])

    def test_versions(self):
        self.assertLess(osv.vkey('6.2.0-beta.3'), osv.vkey('6.2.0'))
        self.assertLess(osv.vkey('1.20.8'), osv.vkey('1.20.9'))
        self.assertLess(osv.vkey('1.9.0'), osv.vkey('1.10.0'))

    def test_report_missing_file_is_warning(self):
        self.assertEqual(osv.main([os.path.join(self.project, 'nope.json')]), 0)


class PerfCheckTest(unittest.TestCase):
    def test_extract_from_machine_and_plain(self):
        payload = {'name': 'mail_open_cold_ms', 'ms': 900, 'marks': {'создано': 300}}
        line = pc.MARKER + ' ' + json.dumps(payload, ensure_ascii=False)
        machine = json.dumps({'type': 'print', 'message': line, 'testID': 3})
        with tempfile.TemporaryDirectory() as d:
            a = os.path.join(d, 'a.jsonl')
            b = os.path.join(d, 'b.txt')
            open(a, 'w').write('{"type":"start"}\n' + machine + '\n')
            open(b, 'w').write('10-31 I/flutter ( 123): ' + line + '\n')
            self.assertEqual(pc.extract([a])['metrics'], {'mail_open_cold_ms': 900})
            self.assertEqual(pc.extract([b])['metrics'], {'mail_open_cold_ms': 900})
            self.assertEqual(pc.extract([os.path.join(d, 'none')])['metrics'], {})

    def test_compare(self):
        rows, bad = pc.compare({'a_ms': 500, 'b_ms': 2500, 'c_ms': 10, 'd_ms': 300},
                               {'a_ms': 400, 'b_ms': 1000, 'd_ms': 400, 'e_ms': 100}, 2.0)
        self.assertEqual([r['metric'] for r in bad], ['b_ms'])
        by = {r['metric']: r['status'] for r in rows}
        self.assertEqual(by, {'a_ms': 'slower', 'b_ms': 'regression', 'c_ms': 'new', 'd_ms': 'ok',
                              'e_ms': 'missing'})

    def test_new_baseline(self):
        base = pc.new_baseline({'a_ms': 1234.0, 'b_ms': 10}, headroom=1.5, step=50)
        self.assertEqual(base, {'a_ms': 1900, 'b_ms': 50})


if __name__ == '__main__':
    unittest.main()
