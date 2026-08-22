/* ============================================================================
 * 서비스워커 — 앱 껍데기(HTML·CSS·JS·아이콘)를 기기에 캐시해
 * 인터넷이 없어도 앱이 뜨게 한다.
 *
 * 곡 데이터와 악보 파일은 여기서 다루지 않는다. 그쪽은 app.js가
 * IndexedDB에 직접 저장한다(오프라인 저장을 켠 곡만).
 *
 * ※ 파일을 고친 뒤에는 아래 CACHE 뒤 숫자를 반드시 올린다.
 *   올리지 않으면 방문자에게 예전 버전이 계속 뜬다.
 * ==========================================================================*/
const CACHE = 'praise-archive-v8';

const SHELL = [
  './',
  './index.html',
  './manifest.webmanifest',
  './assets/app.css',
  './assets/db.js',
  './assets/app.js',
  './vendor/supabase.js',
  './icons/Icon-192.png',
  './icons/Icon-512.png',
  './icons/Icon-180.png',
  './icons/favicon.png',
];

self.addEventListener('install', e => {
  e.waitUntil(
    caches.open(CACHE)
      // 한 개라도 실패하면 전체가 실패하는 addAll 대신 개별로 담는다
      .then(c => Promise.all(SHELL.map(u => c.add(u).catch(() => null))))
      .then(() => self.skipWaiting())
  );
});

self.addEventListener('activate', e => {
  e.waitUntil(
    caches.keys()
      .then(keys => Promise.all(keys.filter(k => k !== CACHE).map(k => caches.delete(k))))
      .then(() => self.clients.claim())
  );
});

self.addEventListener('fetch', e => {
  const req = e.request;
  if (req.method !== 'GET') return;

  const url = new URL(req.url);
  if (url.origin !== self.location.origin) return;   // Supabase 통신은 손대지 않는다

  const isDoc = req.mode === 'navigate';
  const isConfig = url.pathname.endsWith('/config.js');

  // 문서와 설정 파일은 네트워크 우선 — 배포한 새 버전이 바로 반영되도록
  if (isDoc || isConfig){
    e.respondWith(
      fetch(req)
        .then(res => {
          const copy = res.clone();
          caches.open(CACHE).then(c => c.put(req, copy));
          return res;
        })
        .catch(() => caches.match(req).then(r => r || caches.match('./index.html')))
    );
    return;
  }

  // 나머지 정적 파일은 캐시 우선 (pdf.js처럼 큰 파일도 한 번만 받는다)
  e.respondWith(
    caches.match(req).then(hit => hit || fetch(req).then(res => {
      if (res.ok && res.type === 'basic'){
        const copy = res.clone();
        caches.open(CACHE).then(c => c.put(req, copy));
      }
      return res;
    }))
  );
});
