/// <reference lib="webworker" />
import { ExpirationPlugin } from "workbox-expiration";
import { createHandlerBoundToURL, precacheAndRoute } from "workbox-precaching";
import { NavigationRoute, registerRoute } from "workbox-routing";
import {
  CacheFirst,
  NetworkOnly,
  StaleWhileRevalidate,
} from "workbox-strategies";

declare const self: ServiceWorkerGlobalScope & { __WB_MANIFEST: unknown[] };

precacheAndRoute(self.__WB_MANIFEST as never);

// Every document route is the application shell; a path with a file
// extension is an asset and must fail honestly when it is missing.
registerRoute(
  new NavigationRoute(createHandlerBoundToURL("/index.html"), {
    denylist: [/^\/corpus\//, /\.[a-z0-9]+$/i],
  }),
);

// What the app fetches only when it is first wanted (search's SQLite) is
// named by the hash of its contents, like everything else under /assets/.
registerRoute(
  ({ url }) =>
    url.origin === self.location.origin && url.pathname.startsWith("/assets/"),
  new CacheFirst({ cacheName: "hours-assets-v1" }),
);

// An edition's library is kept by the search worker in the browser's own
// file system, not here: a second copy would only take room.
registerRoute(
  ({ url }) =>
    url.origin === self.location.origin &&
    /^\/corpus\/[^/]+\/library\//.test(url.pathname),
  new NetworkOnly(),
);

// An office file is named by the hash of its contents and never changes.
registerRoute(
  ({ url }) =>
    url.origin === self.location.origin &&
    url.pathname.startsWith("/corpus/o/"),
  new CacheFirst({
    cacheName: "hours-offices-v1",
    plugins: [
      new ExpirationPlugin({ maxEntries: 4000, purgeOnQuotaError: true }),
    ],
  }),
);

// The pointer to the current corpus and the month indexes it names.
registerRoute(
  ({ url }) =>
    url.origin === self.location.origin && url.pathname.startsWith("/corpus/"),
  new StaleWhileRevalidate({ cacheName: "hours-corpus-index-v1" }),
);

// A recording of the harp lies in a directory named for what it was rendered
// from, and never changes; the manifest beside them says which directory.
registerRoute(
  ({ url }) =>
    url.origin === self.location.origin &&
    /^\/harp\/[0-9a-f]+\//.test(url.pathname),
  new CacheFirst({
    cacheName: "hours-harp-v1",
    plugins: [
      new ExpirationPlugin({ maxEntries: 256, purgeOnQuotaError: true }),
    ],
  }),
);
registerRoute(
  ({ url }) =>
    url.origin === self.location.origin &&
    url.pathname === "/harp/manifest.json",
  new StaleWhileRevalidate({ cacheName: "hours-harp-v1" }),
);

self.addEventListener("message", (event) => {
  if (event.data?.type === "SKIP_WAITING") void self.skipWaiting();
});
