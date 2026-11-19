// Danh sách thiết bị mặc định. Kích thước là CSS pixel (viewport), không phải độ phân giải vật lý.
export const DEFAULT_DEVICES = [
  { id: "iphone-se", name: "iPhone SE", w: 375, h: 667, type: "mobile" },
  { id: "iphone-15", name: "iPhone 15 Pro", w: 393, h: 852, type: "mobile" },
  { id: "iphone-15-max", name: "iPhone 15 Pro Max", w: 430, h: 932, type: "mobile" },
  { id: "pixel-8", name: "Pixel 8", w: 412, h: 915, type: "mobile" },
  { id: "galaxy-s24", name: "Galaxy S24", w: 360, h: 780, type: "mobile" },
  { id: "ipad-mini", name: "iPad Mini", w: 768, h: 1024, type: "tablet" },
  { id: "ipad-air", name: "iPad Air", w: 820, h: 1180, type: "tablet" },
  { id: "ipad-pro-13", name: "iPad Pro 13", w: 1032, h: 1376, type: "tablet" },
  { id: "laptop", name: "Laptop", w: 1366, h: 768, type: "desktop" },
  { id: "macbook-air", name: "MacBook Air 13", w: 1470, h: 956, type: "desktop" },
  { id: "desktop-fhd", name: "Desktop FHD", w: 1920, h: 1080, type: "desktop" },
];

// Bộ mặc định khi mới cài: mỗi nhóm một máy phổ biến.
export const DEFAULT_ENABLED = ["iphone-15", "ipad-mini", "laptop"];

export const TYPE_LABEL = { mobile: "Mobile", tablet: "Tablet", desktop: "Desktop", custom: "Tùy chỉnh" };
