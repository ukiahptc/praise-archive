/* ============================================================================
 * 예전 Flutter 웹 앱 정리용 (킬 스위치)
 *
 * 이 주소에는 원래 Flutter 웹 빌드가 올라가 있었다. 그때 한 번이라도
 * 방문했던 브라우저에는 Flutter의 서비스워커가 아직 등록돼 있어서,
 * 사이트를 새 앱으로 바꿔도 캐시된 옛 화면이 계속 뜬다.
 *
 * 브라우저는 등록된 서비스워커 스크립트를 주기적으로 다시 받아 내용이
 * 바뀌었는지 본다. 같은 파일 이름에 이 내용을 올려 두면, 그 검사 때
 * 이 스크립트가 새 워커로 설치되고 곧바로 스스로를 지운다.
 *
 * 지우고 나면 페이지가 새로고침되어 새 앱(sw.js)이 정상으로 뜬다.
 * 새로 방문하는 사람에게는 아무 영향이 없다.
 *
 * ※ 옛 사용자가 모두 넘어온 뒤(수개월 후)에는 이 파일을 지워도 된다.
 * ==========================================================================*/
self.addEventListener('install', () => self.skipWaiting());

self.addEventListener('activate', event => {
  event.waitUntil((async () => {
    for (const key of await caches.keys()) await caches.delete(key);
    await self.registration.unregister();
    for (const client of await self.clients.matchAll({ type: 'window' })){
      try { client.navigate(client.url); } catch (_) {}
    }
  })());
});

// 등록이 남아 있는 동안에는 아무것도 가로채지 않고 네트워크로 넘긴다.
self.addEventListener('fetch', () => {});
