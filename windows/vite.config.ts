import { defineConfig } from "vite";
import react from "@vitejs/plugin-react";

// Tauri chạy dev server cố định cổng 1420.
export default defineConfig({
  plugins: [react()],
  clearScreen: false,
  server: { port: 1420, strictPort: true },
  build: { target: "es2022", outDir: "dist", emptyOutDir: true },
});
