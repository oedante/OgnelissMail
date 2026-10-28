import sys
from playwright.sync_api import sync_playwright
pages = sys.argv[1].split(',')
FULL = len(sys.argv) < 3
with sync_playwright() as p:
    b = p.chromium.launch()
    for scheme in ('light', 'dark'):
        for name, w, h in (('desk', 1280, 900), ('phone', 390, 844)):
            ctx = b.new_context(viewport={'width': w, 'height': h}, color_scheme=scheme, device_scale_factor=1)
            pg = ctx.new_page()
            for u in pages:
                pg.goto('http://127.0.0.1:8765' + u)
                sw = pg.evaluate('document.documentElement.scrollWidth')
                if sw > w: print('HSCROLL', u, name, sw)
                fn = f"{u.strip('/').replace('/', '_') or 'home'}_{name}_{scheme}.png"
                pg.screenshot(path=fn, full_page=FULL)
            ctx.close()
    b.close()
