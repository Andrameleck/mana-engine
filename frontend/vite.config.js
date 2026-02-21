import { defineConfig } from "vite";

export default defineConfig({
  base: "/ui/static/",
  build: {
    outDir: "../inst/www",
    emptyOutDir: true,
    cssCodeSplit: false,
    sourcemap: true,
    rollupOptions: {
      output: {
        entryFileNames: "app.js",
        chunkFileNames: "chunk-[name].js",
        inlineDynamicImports: true,
        assetFileNames: (assetInfo) => {
          const name = String(assetInfo.name || "").toLowerCase();
          if (name.endsWith(".css")) {
            return "app.css";
          }
          return "[name][extname]";
        }
      }
    },
    target: "es2020"
  },
  server: {
    host: true,
    port: 5173
  }
});
