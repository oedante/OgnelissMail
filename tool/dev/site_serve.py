# Повторяет правила nginx-landing.conf: публичный адрес → файл в site/
import http.server, re, sys, os
ROOT = sys.argv[1]
L = '(ru|de|fr)'
D = '(privacy|terms|eula|licenses)'
def resolve(p):
    p = p.split('?')[0].split('#')[0]
    rules = [
        (r'^/$', 'home.html'),
        (rf'^/{L}/$', r'\1/home.html'),
        (r'^/dialer/$', 'index.html'),
        (rf'^/dialer/{D}$', r'\1.html'),
        (rf'^/dialer/{L}/$', r'\1/index.html'),
        (rf'^/dialer/{L}/{D}$', r'\1/\2.html'),
        (r'^/mail/$', 'mail/index.html'),
        (rf'^/mail/{D}$', r'mail/\1.html'),
        (rf'^/mail/{L}/$', r'\1/mail/index.html'),
        (rf'^/mail/{L}/{D}$', r'\1/mail/\2.html'),
        (r'^/mail/en/$', 'mail/en/index.html'),
        (r'^/mail/en/privacy/$', 'mail/en/privacy/index.html'),
        (r'^/dialer/(.+)$', r'\1'),
        (r'^/mail/(.+)$', r'mail/\1'),
        (r'^/(sitemap\.xml|robots\.txt)$', r'\1'),
    ]
    for rx, rep in rules:
        if re.match(rx, p):
            return re.sub(rx, rep, p)
    return None
class H(http.server.SimpleHTTPRequestHandler):
    def translate_path(self, path):
        f = resolve(path)
        return os.path.join(ROOT, f) if f else '/nonexistent'
    def log_message(self, *a): pass
http.server.ThreadingHTTPServer(('127.0.0.1', 8765), H).serve_forever()
