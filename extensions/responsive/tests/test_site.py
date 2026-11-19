# Site test: cố tình gửi header CHẶN nhúng iframe (X-Frame-Options + CSP frame-ancestors).
# Trang test responsive: cố tình gửi header CHẶN nhúng iframe.
import http.server, sys
PAGE = """<!doctype html><html><head><meta charset=utf-8>
<meta name=viewport content="width=device-width,initial-scale=1"><title>%(title)s</title>
<style>
body{margin:0;font:16px system-ui;color:#222}
header{padding:16px;color:#fff;background:#555}
.bp::after{content:"DESKTOP"} @media (max-width:1023px){.bp::after{content:"TABLET"}} @media (max-width:599px){.bp::after{content:"MOBILE"}}
@media (max-width:599px){header{background:#3a6}} @media (min-width:600px) and (max-width:1023px){header{background:#36a}}
.grid{display:grid;grid-template-columns:repeat(auto-fill,minmax(160px,1fr));gap:12px;padding:16px}
.card{height:120px;border-radius:12px;background:#eee;display:flex;align-items:center;justify-content:center}
</style></head><body>
<header><b class=bp></b> · <span id=w></span> · %(title)s</header>
<p style="padding:0 16px"><a id=next href="%(next)s">Đi tới %(nextname)s</a></p>
<div class=grid>%(cards)s</div>
<script>const u=()=>document.getElementById('w').textContent=innerWidth+'×'+innerHeight;u();addEventListener('resize',u)</script>
</body></html>"""
class H(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        p = self.path.split('?')[0]
        if p not in ('/', '/page2'):
            self.send_response(404); self.end_headers(); return
        two = p == '/page2'
        body = (PAGE % dict(title='Trang 2' if two else 'Trang chủ', next='/' if two else '/page2',
                           nextname='trang chủ' if two else 'trang 2',
                           cards=''.join(f'<div class=card>Thẻ {i}</div>' for i in range(60)))).encode()
        self.send_response(200)
        self.send_header('Content-Type', 'text/html; charset=utf-8')
        self.send_header('X-Frame-Options', 'DENY')
        self.send_header('Content-Security-Policy', "frame-ancestors 'none'")
        self.send_header('Content-Length', str(len(body)))
        self.end_headers(); self.wfile.write(body)
    def log_message(self, *a): pass
http.server.ThreadingHTTPServer(('127.0.0.1', int(sys.argv[1])), H).serve_forever()
