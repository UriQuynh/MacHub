// MacHub Responsive — content script chạy trong mọi frame nhưng chỉ HOẠT ĐỘNG khi frame là
// khung thiết bị nằm trực tiếp trong viewer của extension. Ở mọi trang khác nó thoát ngay.
(() => {
  if (window.top === window) return;
  const ancestors = location.ancestorOrigins;
  const viewerOrigin = `chrome-extension://${chrome.runtime.id}`;
  if (!ancestors || ancestors.length !== 1 || ancestors[0] !== viewerOrigin) return;
  if (!window.name.startsWith("mh-frame:")) return;

  const device = window.name.slice("mh-frame:".length);
  let suppressUntil = 0;
  let scheduled = false;

  const send = (msg) => chrome.runtime.sendMessage({ ...msg, device }).catch(() => {});

  const scrollRatio = () => {
    const el = document.scrollingElement || document.documentElement;
    const maxY = el.scrollHeight - innerHeight;
    const maxX = el.scrollWidth - innerWidth;
    return { y: maxY > 0 ? scrollY / maxY : 0, x: maxX > 0 ? scrollX / maxX : 0 };
  };

  const reportReady = () =>
    send({ type: "mh-frame-ready", href: location.href, title: document.title || location.host });

  addEventListener("DOMContentLoaded", reportReady, { once: true });
  addEventListener("load", reportReady, { once: true });

  addEventListener(
    "scroll",
    () => {
      if (Date.now() < suppressUntil || scheduled) return;
      scheduled = true;
      requestAnimationFrame(() => {
        scheduled = false;
        send({ type: "mh-scroll", ...scrollRatio() });
      });
    },
    { passive: true }
  );

  chrome.runtime.onMessage.addListener((msg) => {
    if (msg?.type === "mh-apply-scroll") {
      const el = document.scrollingElement || document.documentElement;
      suppressUntil = Date.now() + 150; // không phát lại sự kiện cuộn do chính mình gây ra
      scrollTo({
        top: msg.y * Math.max(0, el.scrollHeight - innerHeight),
        left: msg.x * Math.max(0, el.scrollWidth - innerWidth),
        behavior: "instant",
      });
    } else if (msg?.type === "mh-ping") {
      reportReady();
    }
  });
})();
