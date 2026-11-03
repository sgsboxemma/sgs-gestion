const CACHE = "sgs-gestion-v15.4.23";
const ASSETS = ["./", "./index.html", "./cloud.js?v=15.4.23", "./manifest.webmanifest", "./icons/icon-192.png", "./icons/icon-512.png"];
self.addEventListener("install", event => event.waitUntil(Promise.all([self.skipWaiting(),caches.open(CACHE).then(cache => cache.addAll(ASSETS))])));
self.addEventListener("activate", event => event.waitUntil((async()=>{
  const keys=await caches.keys();
  const keep=new Set([CACHE,"sgs-member-photo-blobs-v1"]);
  await Promise.all(keys.filter(k=>!keep.has(k)).map(k=>caches.delete(k)));
  await self.clients.claim();
  const windows=await self.clients.matchAll({type:"window"});
  await Promise.all(windows.map(client=>client.navigate(client.url)));
})()));
self.addEventListener("fetch", event => {
  if (event.request.method !== "GET" || new URL(event.request.url).origin !== location.origin) return;
  event.respondWith(fetch(event.request).then(response => {
    const copy = response.clone();
    caches.open(CACHE).then(cache => cache.put(event.request, copy));
    return response;
  }).catch(() => caches.match(event.request).then(r => r || caches.match("./index.html"))));
});
