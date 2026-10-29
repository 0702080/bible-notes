/* 말씀 묵상 노트 — 오프라인에서도 열리게 (2026-10-25 사용자 요청)
   - 화면(HTML)은 인터넷이 되면 늘 새로 받아 오고, 안 되면 마지막으로 받아 둔 것을 보여 줌
   - 아이콘·글꼴 같은 파일은 받아 둔 것을 먼저 쓰고 뒤에서 새로 받아 둠
   - 로그인·동기화(Supabase)와 다른 사이트 요청은 건드리지 않음 */
var CACHE = "bible-notes-v4";
var CORE = ["./", "./index.html", "./manifest.json", "./icon-192.png", "./icon-512.png", "./tongdok/", "./tongdok2/"];

self.addEventListener("install", function (e) {
  e.waitUntil(caches.open(CACHE).then(function (c) {
    return Promise.all(CORE.map(function (u) { return c.add(u).catch(function () {}); }));
  }).then(function () { return self.skipWaiting(); }));
});

self.addEventListener("activate", function (e) {
  e.waitUntil(caches.keys().then(function (ks) {
    return Promise.all(ks.filter(function (k) { return k !== CACHE; }).map(function (k) { return caches.delete(k); }));
  }).then(function () { return self.clients.claim(); }));
});

function isFont(u) { return /fonts\.googleapis\.com|fonts\.gstatic\.com|cdn\.jsdelivr\.net|noonnu|cafe24|quickslide/.test(u.host + u.pathname); }

self.addEventListener("fetch", function (e) {
  var r = e.request; if (r.method !== "GET") return;
  var u = new URL(r.url);
  var same = u.origin === self.location.origin;
  if (!same && !isFont(u)) return;   // Supabase·is.gd 등은 그대로 인터넷으로
  var html = r.mode === "navigate" || (r.headers.get("accept") || "").indexOf("text/html") >= 0;
  if (same && html) {   // 화면: 인터넷 먼저, 안 되면 받아 둔 것
    e.respondWith(fetch(r).then(function (res) {
      if (res && res.ok) { var cp = res.clone(); caches.open(CACHE).then(function (c) { c.put(r, cp); }); }
      return res;
    }).catch(function () {
      return caches.match(r, { ignoreSearch: true }).then(function (m) { return m || caches.match("./index.html"); });
    }));
    return;
  }
  // 그 밖의 파일: 받아 둔 것 먼저, 뒤에서 새로
  e.respondWith(caches.match(r).then(function (m) {
    var net = fetch(r).then(function (res) {
      if (res && (res.ok || res.type === "opaque")) { var cp = res.clone(); caches.open(CACHE).then(function (c) { c.put(r, cp); }); }
      return res;
    }).catch(function () { return m; });
    return m || net;
  }));
});
