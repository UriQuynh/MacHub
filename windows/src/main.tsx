// SPDX-License-Identifier: GPL-3.0-only
import { StrictMode } from "react";
import { createRoot } from "react-dom/client";
import { getCurrentWindow } from "@tauri-apps/api/window";
import App from "./App";
import ApprovalWindow from "./ApprovalWindow";
import "./styles.css";

// Cùng một bundle cho hai cửa sổ; phân biệt theo nhãn cửa sổ.
const label = getCurrentWindow().label;

createRoot(document.getElementById("root")!).render(
  <StrictMode>{label === "approval" ? <ApprovalWindow /> : <App />}</StrictMode>,
);
