// MacHub Responsive — service worker.
//
// Nhiều trang gửi `X-Frame-Options` hoặc CSP `frame-ancestors` để chặn bị nhúng vào iframe.
// Để xem được trong viewer, extension gỡ hai header này, nhưng CHỈ:
//   • cho request loại sub_frame (iframe), và
//   • trong đúng tab viewer đang mở (session rule theo tabId, tự xóa khi đóng tab).
// Duyệt web bình thường ở các tab khác không bị ảnh hưởng.

const VIEWER_PATH = "viewer.html";
const FRAME_HEADERS = ["x-frame-options", "content-security-policy"];

chrome.action.onClicked.addListener(async (tab) => {
  const url = tab?.url && /^(https?|file):/i.test(tab.url) ? tab.url : "";
  const viewerUrl = chrome.runtime.getURL(VIEWER_PATH) + (url ? `?url=${encodeURIComponent(url)}` : "");
  await chrome.tabs.create({ url: viewerUrl, index: (tab?.index ?? 0) + 1, openerTabId: tab?.id });
});

chrome.runtime.onMessage.addListener((msg, sender, sendResponse) => {
  // Chỉ nhận lệnh từ trang viewer của chính extension (không phải từ content script trong trang web).
  const fromViewer = sender.url?.startsWith(chrome.runtime.getURL(VIEWER_PATH));
  if (!fromViewer || !sender.tab?.id) return;

  if (msg?.type === "mh-register-viewer") {
    allowFramingInTab(sender.tab.id)
      .then(() => sendResponse({ ok: true, tabId: sender.tab.id }))
      .catch((err) => sendResponse({ ok: false, error: String(err) }));
    return true; // trả lời bất đồng bộ
  }
});

chrome.tabs.onRemoved.addListener((tabId) => {
  chrome.declarativeNetRequest.updateSessionRules({ removeRuleIds: [tabId] }).catch(() => {});
});

// Tab viewer chuyển sang trang khác (không còn là viewer) → gỡ quyền nhúng.
chrome.tabs.onUpdated.addListener((tabId, info) => {
  if (info.url && !info.url.startsWith(chrome.runtime.getURL(VIEWER_PATH))) {
    chrome.declarativeNetRequest.updateSessionRules({ removeRuleIds: [tabId] }).catch(() => {});
  }
});

async function allowFramingInTab(tabId) {
  await chrome.declarativeNetRequest.updateSessionRules({
    removeRuleIds: [tabId],
    addRules: [
      {
        id: tabId,
        priority: 1,
        action: {
          type: "modifyHeaders",
          responseHeaders: FRAME_HEADERS.map((header) => ({ header, operation: "remove" })),
        },
        condition: { tabIds: [tabId], resourceTypes: ["sub_frame"] },
      },
    ],
  });
}
