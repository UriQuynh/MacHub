# Kiểm thử đầu-cuối MacHub Responsive trên Chromium thật (Playwright).
#   pip install playwright && python -m playwright install chromium
#   python extensions/responsive/tests/e2e_test.py
# Ảnh chụp ở tests/out/. Site test cố tình gửi X-Frame-Options: DENY + CSP frame-ancestors 'none'.
import asyncio, sys, json, os, subprocess, time, tempfile, shutil
from playwright.async_api import async_playwright
HERE = os.path.dirname(os.path.abspath(__file__))
EXT = os.path.dirname(HERE)
OUT = os.environ.get("OUT_DIR", os.path.join(HERE, "out"))
CHROME = os.environ.get("CHROME_PATH")  # mặc định: Chromium của Playwright
SITE = "http://127.0.0.1:8765/"
results = []
def ok(name, cond, extra=""):
    results.append((name, bool(cond))); print(("  ✅ " if cond else "  ❌ ") + name + (f"  ({extra})" if extra else ""))

async def frame_info(fr):
    return await fr.evaluate("""() => ({bp: getComputedStyle(document.querySelector('.bp'),'::after').content,
      w: innerWidth, h: innerHeight, y: scrollY, max: document.documentElement.scrollHeight - innerHeight, path: location.pathname})""")

async def wait_frame(page, prefix, timeout=10):
    """Chờ tới khi khung có tên bắt đầu bằng prefix tải xong trang test."""
    for _ in range(int(timeout * 5)):
        for f in page.frames:
            if f.name.startswith(prefix):
                try:
                    if await f.evaluate("!!document.querySelector('.bp')"):
                        return await frame_info(f)
                except Exception:
                    pass
        await page.wait_for_timeout(200)
    return None

async def main():
    async with async_playwright() as p:
        ctx = await p.chromium.launch_persistent_context(tempfile.mkdtemp(prefix="mh-resp-"), executable_path=CHROME,
            headless=False, viewport={"width": 1600, "height": 1000},
            args=["--headless=new", f"--disable-extensions-except={EXT}", f"--load-extension={EXT}", "--no-sandbox"])
        sw = ctx.service_workers[0] if ctx.service_workers else await ctx.wait_for_event("serviceworker")
        ext_id = sw.url.split("/")[2]
        ok("Extension nạp được, service worker chạy", ext_id, ext_id)

        # Đối chứng: trang thường nhúng site → phải bị chặn (rule chỉ áp cho tab viewer)
        ctl = await ctx.new_page()
        await ctl.goto("http://127.0.0.1:8766/embed.html"); await ctl.wait_for_timeout(1500)
        child = [f for f in ctl.frames if f != ctl.main_frame]
        blocked = True
        for f in child:
            try:
                blocked = not (await f.evaluate("!!document.querySelector('.bp')"))
            except Exception: blocked = True
        ok("Tab thường: site vẫn bị chặn nhúng (không nới lỏng ngoài viewer)", blocked)
        await ctl.close()

        page = await ctx.new_page()
        errors = []
        page.on("pageerror", lambda e: errors.append(str(e)))
        await page.goto(f"chrome-extension://{ext_id}/viewer.html?url=" + SITE)
        await page.wait_for_timeout(3000)
        frames = {f.name: f for f in page.frames if f.name.startswith("mh-frame:")}
        ok("Hiện 3 khung mặc định", len(frames) == 3, ",".join(frames))
        exp = {"mh-frame:iphone-15": ('"MOBILE"', 393), "mh-frame:ipad-mini": ('"TABLET"', 768), "mh-frame:laptop": ('"DESKTOP"', 1366)}
        for name, (bp, w) in exp.items():
            f = frames.get(name)
            info = await frame_info(f) if f else {}
            ok(f"{name.split(':')[1]}: render dù site gửi X-Frame-Options DENY, breakpoint {bp}, rộng {w}px",
               info.get("bp") == bp and info.get("w") == w, json.dumps(info))
        await page.screenshot(path=os.path.join(OUT, "viewer-fit.png"))

        # Đồng bộ cuộn
        m = frames["mh-frame:iphone-15"]
        await m.evaluate("() => scrollTo(0, (document.documentElement.scrollHeight - innerHeight) / 2)")
        await page.wait_for_timeout(800)
        ratios = {}
        for n, f in frames.items():
            i = await frame_info(f); ratios[n.split(':')[1]] = round(i["y"] / i["max"], 2) if i["max"] > 0 else None
        ok("Đồng bộ cuộn: các khung cùng cuộn ~50%", all(r is not None and abs(r - 0.5) < 0.05 for r in ratios.values()), json.dumps(ratios))

        # Đồng bộ điều hướng
        await m.evaluate("() => document.getElementById('next').click()")
        await page.wait_for_timeout(2500)
        frames = {f.name: f for f in page.frames if f.name.startswith("mh-frame:")}
        paths = {n.split(':')[1]: (await frame_info(f))["path"] for n, f in frames.items()}
        ok("Đồng bộ điều hướng: bấm link ở mobile → mọi khung sang /page2", set(paths.values()) == {"/page2"}, json.dumps(paths))
        ok("Ô URL cập nhật theo", (await page.input_value("#url-input")).endswith("/page2"))
        await page.wait_for_timeout(1500)
        paths2 = {n.split(':')[1]: (await frame_info(f))["path"] for n, f in frames.items()}
        ok("Không lặp điều hướng sau khi đồng bộ", paths2 == paths)

        # Xoay khung mobile
        await page.click('section[data-device="iphone-15"] .rotate'); await page.wait_for_timeout(600)
        f = [f for f in page.frames if f.name == "mh-frame:iphone-15"][0]
        i = await frame_info(f)
        ok("Xoay: iPhone thành 852×393, không tải lại trang", i["w"] == 852 and i["h"] == 393 and i["path"] == "/page2", json.dumps(i))
        await page.click('section[data-device="iphone-15"] .rotate')

        # Thu phóng 50%
        await page.select_option("#zoom", "0.5"); await page.wait_for_timeout(300)
        box = await page.eval_on_selector('section[data-device="laptop"] .device-body', "e => e.getBoundingClientRect().width")
        ok("Thu phóng 50%: khung Laptop rộng 683px", abs(box - 683) < 1, str(box))
        await page.select_option("#zoom", "fit"); await page.wait_for_timeout(300)
        fit = await page.evaluate("() => { const s = document.getElementById(\"stage\"); return [s.scrollWidth <= s.clientWidth + 1, s.scrollHeight <= s.clientHeight + 1] }")
        ok("Vừa màn hình: mọi khung lọt trọn, không cần cuộn viewer", all(fit), str(fit))
        await page.screenshot(path=os.path.join(OUT, "viewer-fit2.png"))
        await page.select_option("#zoom", "fit")

        # Thêm kích thước tùy chỉnh
        await page.click("#devices-btn")
        await page.fill("#custom-name", "Galaxy Fold"); await page.fill("#custom-w", "344"); await page.fill("#custom-h", "882")
        await page.click("#custom-form button[type=submit]")
        info = await wait_frame(page, "mh-frame:custom-")
        ok("Thêm kích thước tùy chỉnh 344×882 → khung mới tải trang", info and info["w"] == 344, json.dumps(info))
        await page.screenshot(path=os.path.join(OUT, "viewer-panel.png"))
        await page.keyboard.press("Escape")

        # Lưu cài đặt: mở viewer mới vẫn còn 4 khung
        p2 = await ctx.new_page()
        await p2.goto(f"chrome-extension://{ext_id}/viewer.html?url=" + SITE); await p2.wait_for_timeout(2500)
        ok("Cài đặt được lưu (viewer mới có 4 khung)", len([f for f in p2.frames if f.name.startswith('mh-frame:')]) == 4)
        await p2.screenshot(path=os.path.join(OUT, "viewer-4.png"))

        # Đóng viewer → session rule bị gỡ
        await page.close(); await p2.close(); await asyncio.sleep(0.5)
        rules = await sw.evaluate("chrome.declarativeNetRequest.getSessionRules()")
        ok("Đóng viewer → quy tắc gỡ header bị xóa", len(rules) == 0, str(len(rules)))

        # Trạng thái trống
        p3 = await ctx.new_page(); await p3.goto(f"chrome-extension://{ext_id}/viewer.html"); await p3.wait_for_timeout(800)
        ok("Không có URL → hiện hướng dẫn", await p3.is_visible("#empty"))
        await p3.fill("#url-input", "127.0.0.1:8765"); await p3.press("#url-input", "Enter"); await p3.wait_for_timeout(2000)
        ok("Nhập '127.0.0.1:8765' → tự thêm http:// và tải", (await p3.input_value("#url-input")) == "http://127.0.0.1:8765/")
        sizes = [await f.evaluate("innerWidth") for f in p3.frames if f.name.startswith("mh-frame:")]
        txt = [await f.evaluate("document.getElementById(\"w\").textContent") for f in p3.frames if f.name.startswith("mh-frame:")]
        ok("Trang con đo đúng kích thước ngay lúc tải (không 0×0)", all(not t.startswith("0") for t in txt), str(txt))
        await p3.evaluate("document.documentElement.dataset.theme='dark'")
        await p3.screenshot(path=os.path.join(OUT, "viewer-dark.png"))
        ok("Không có lỗi JavaScript trong viewer", not errors, "; ".join(errors))
        await ctx.close()
    bad = [n for n, c in results if not c]
    print(f"\nKết quả: {len(results)-len(bad)}/{len(results)} đạt")
    sys.exit(1 if bad else 0)
if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    servers = [subprocess.Popen([sys.executable, os.path.join(HERE, "test_site.py"), "8765"]),
               subprocess.Popen([sys.executable, "-m", "http.server", "8766", "--bind", "127.0.0.1", "--directory", HERE],
                                stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)]
    time.sleep(1)
    try:
        asyncio.run(main())
    finally:
        for s in servers: s.terminate()
