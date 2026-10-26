import tailwindcss from "@tailwindcss/vite";
import react from "@vitejs/plugin-react";
import { createReadStream, stat } from "node:fs";
import type { IncomingMessage, ServerResponse } from "node:http";
import { join, normalize, sep } from "node:path";
import { fileURLToPath } from "node:url";
import { createBrotliDecompress } from "node:zlib";
import { build, defineConfig, type Plugin, type Rollup } from "vite";
import { VitePWA } from "vite-plugin-pwa";

/**
 * Serves the exported Office from `corpus/` at `/corpus/` while developing
 * and previewing. In production it is published beside the app, not inside
 * it, so it is kept out of `public/` and the build.
 */
function corpus(): Plugin {
  // The end-to-end tests point this at a fixed month so they do not depend
  // on today's date.
  const directory = process.env.HOURS_CORPUS_DIR
    ? normalize(join(process.cwd(), process.env.HOURS_CORPUS_DIR))
    : fileURLToPath(new URL("./corpus", import.meta.url));
  const serve = (
    request: IncomingMessage,
    response: ServerResponse,
    next: () => void,
  ) => {
    const url = request.url ?? "";
    if (!url.startsWith("/corpus/")) return next();
    const path = normalize(
      join(
        directory,
        decodeURIComponent(url.slice("/corpus/".length).split("?")[0]),
      ),
    );
    if (!path.startsWith(directory + sep)) {
      response.statusCode = 403;
      response.end();
      return;
    }
    stat(path, (error, found) => {
      if (error || !found.isFile()) {
        response.statusCode = 404;
        response.end("Not found");
        return;
      }
      if (path.endsWith(".sqlite.br")) {
        // An edition's library is published compressed, with the encoding
        // named, and a browser decodes it as it arrives. One that does not
        // accept the encoding (some do not over plain HTTP) is sent the
        // database itself.
        response.setHeader("Content-Type", "application/vnd.sqlite3");
        response.setHeader(
          "Cache-Control",
          "public,max-age=31536000,immutable",
        );
        const accepted = String(request.headers["accept-encoding"] ?? "");
        if (/\bbr\b/.test(accepted)) {
          response.setHeader("Content-Encoding", "br");
          response.setHeader("Content-Length", found.size);
          createReadStream(path).pipe(response);
        } else {
          createReadStream(path).pipe(createBrotliDecompress()).pipe(response);
        }
        return;
      }
      response.setHeader("Content-Type", "application/json");
      response.setHeader(
        "Cache-Control",
        path.includes(`${sep}o${sep}`)
          ? "public,max-age=31536000,immutable"
          : "no-cache",
      );
      createReadStream(path).pipe(response);
    });
  };
  return {
    name: "hours-corpus",
    configureServer(server) {
      server.middlewares.use(serve);
    },
    configurePreviewServer(server) {
      server.middlewares.use(serve);
    },
  };
}

const alias = {
  "@": fileURLToPath(new URL("./src", import.meta.url)),
  // The timeline parser and the corpus contract are shared with the
  // content compiler rather than copied.
  "@compiler": fileURLToPath(
    new URL("../Tools/ContentCompiler/Sources", import.meta.url),
  ),
  // The hour wheel's drawing and physics, shared with the public site.
  "@site": fileURLToPath(new URL("../web/local-site", import.meta.url)),
};

/**
 * Builds `src/firstPaint.ts`, which gives the page the appearance of its
 * hour, and names it at the head of the document.
 *
 * The app is a module, and a browser paints the page without waiting for
 * one; this is an ordinary script, which it runs first. It is bundled by
 * itself because such a script can import nothing, and it is a file of its
 * own, named like the app's by the hash of its contents, because the
 * content security policy admits no script written into the page.
 */
function firstPaint(): Plugin {
  const served = "/@first-paint.js";
  let published = "";
  const bundle = async (): Promise<string> => {
    const result = (await build({
      configFile: false,
      logLevel: "warn",
      publicDir: false,
      resolve: { alias },
      build: {
        write: false,
        lib: {
          entry: fileURLToPath(new URL("./src/firstPaint.ts", import.meta.url)),
          formats: ["iife"],
          name: "firstPaint",
        },
      },
    })) as Rollup.RollupOutput[];
    return result[0].output[0].code;
  };
  return {
    name: "hours-first-paint",
    configureServer(server) {
      // Built afresh at each request, so that it follows its sources.
      server.middlewares.use(served, (_request, response, next) => {
        bundle().then((script) => {
          response.setHeader("Content-Type", "text/javascript");
          response.setHeader("Cache-Control", "no-cache");
          response.end(script);
        }, next);
      });
    },
    async generateBundle() {
      const file = this.emitFile({
        type: "asset",
        name: "firstPaint.js",
        source: await bundle(),
      });
      published = `/${this.getFileName(file)}`;
    },
    transformIndexHtml(_html, context) {
      // The app's document only; the notation verifier has one of its own.
      if (context.path !== "/index.html") return;
      return [
        {
          tag: "script",
          attrs: { src: context.server ? served : published },
          // After the document's own tags, which it reads.
          injectTo: "head",
        },
      ];
    },
  };
}

export default defineConfig({
  resolve: { alias },
  plugins: [
    corpus(),
    firstPaint(),
    tailwindcss(),
    react(),
    VitePWA({
      strategies: "injectManifest",
      srcDir: "src",
      filename: "sw.ts",
      registerType: "prompt",
      injectRegister: false,
      injectManifest: {
        globPatterns: [
          "**/*.{js,css,html,png,svg,webp,woff2,webmanifest}",
          // The Rubrics say of themselves that they are available offline.
          "guides/*.json",
        ],
        // SQLite is fetched when search is first opened, and kept from then.
        globIgnores: ["**/libraryWorker-*.js", "**/sqlite3-*.js"],
        maximumFileSizeToCacheInBytes: 4_000_000,
      },
      manifest: {
        id: "/",
        name: "Hours",
        short_name: "Hours",
        description:
          "The traditional Roman Divine Office under the 1960 rubrics, in Latin with optional English and Gregorian chant.",
        start_url: "/",
        scope: "/",
        display: "standalone",
        theme_color: "#ffffff",
        background_color: "#f7f1e4",
        icons: [
          { src: "/icons/icon-192.png", sizes: "192x192", type: "image/png" },
          {
            src: "/icons/icon-512.png",
            sizes: "512x512",
            type: "image/png",
            purpose: "any",
          },
          {
            src: "/icons/maskable-512.png",
            sizes: "512x512",
            type: "image/png",
            purpose: "maskable",
          },
        ],
      },
    }),
  ],
  server: { fs: { allow: [".."] } },
  build: { sourcemap: false },
  // SQLite finds its WebAssembly beside its own module, which pre-bundling
  // would move; and it runs in a worker written as a module.
  optimizeDeps: { exclude: ["@sqlite.org/sqlite-wasm"] },
  worker: { format: "es" },
});
