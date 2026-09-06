import path from "path"
import react from "@vitejs/plugin-react"
import { defineConfig } from "vite"
import qbtheme from "../../qbtheme/vite-plugin.mjs"

// FiveM's CEF NUI browser loads this page from a local resource path, not
// from a domain root -- asset URLs must be relative ("./assets/..") or every
// script/style 404s in-game. Do NOT change `base` back to "/". See qblib's
// own web/vite.config.ts, the same convention.
export default defineConfig({
    plugins: [qbtheme(), react()],
    base: "./",
    build: {
        outDir: "build",
    },
    resolve: {
        alias: {
            "@": path.resolve(__dirname, "./src"),
        },
    },
})
