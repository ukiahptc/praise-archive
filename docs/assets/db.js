/* ============================================================================
 * db.js — 기기 안(IndexedDB) 저장소
 *
 * 저장소 4개
 *   songs   : 모든 곡의 메타 + 가사. 텍스트라 가벼워서 전곡을 캐시한다.
 *             → 비행기 모드에서도 목록과 가사 검색이 그대로 된다.
 *   files   : 악보 파일 원본(Blob). "오프라인 저장"을 누른 곡의 것만 담는다.
 *             → 사진·PDF는 무거우므로 사용자가 고른 곡만 받는다.
 *   offline : 오프라인 저장으로 표시한 곡 id 목록.
 *   meta    : 마지막 동기화 시각 등 잡다한 값.
 * ==========================================================================*/
const IDB = (() => {
  const NAME = 'praise-archive';
  const VER = 1;
  let _db = null;

  function open() {
    if (_db) return Promise.resolve(_db);
    return new Promise((res, rej) => {
      const req = indexedDB.open(NAME, VER);
      req.onupgradeneeded = () => {
        const db = req.result;
        if (!db.objectStoreNames.contains('songs'))   db.createObjectStore('songs',   { keyPath: 'id' });
        if (!db.objectStoreNames.contains('files'))   db.createObjectStore('files',   { keyPath: 'path' });
        if (!db.objectStoreNames.contains('offline')) db.createObjectStore('offline', { keyPath: 'songId' });
        if (!db.objectStoreNames.contains('meta'))    db.createObjectStore('meta',    { keyPath: 'k' });
      };
      req.onsuccess = () => { _db = req.result; res(_db); };
      req.onerror = () => rej(req.error);
    });
  }

  function tx(store, mode, fn) {
    return open().then(db => new Promise((res, rej) => {
      const t = db.transaction(store, mode);
      const s = t.objectStore(store);
      let out;
      try { out = fn(s); } catch (e) { rej(e); return; }
      t.oncomplete = () => res(out instanceof IDBRequest ? out.result : out);
      t.onerror = () => rej(t.error);
      t.onabort = () => rej(t.error);
    }));
  }

  return {
    // ── 곡 ──
    allSongs:  ()      => tx('songs', 'readonly',  s => s.getAll()),
    getSong:   id      => tx('songs', 'readonly',  s => s.get(id)),
    putSong:   song    => tx('songs', 'readwrite', s => s.put(song)),
    delSong:   id      => tx('songs', 'readwrite', s => s.delete(id)),

    /** 서버 목록으로 통째 교체. 서버에서 사라진 곡은 기기에서도 지운다. */
    replaceSongs: list => tx('songs', 'readwrite', s => {
      const keep = new Set(list.map(x => x.id));
      const cur = s.getAllKeys();
      cur.onsuccess = () => {
        for (const k of cur.result) if (!keep.has(k)) s.delete(k);
        for (const song of list) s.put(song);
      };
    }),

    // ── 악보 파일 ──
    /** stamp = 서버의 updated_at. 이 값이 달라지면 파일을 다시 받는다. */
    putFile: (path, blob, mime, stamp) =>
      tx('files', 'readwrite', s => s.put({ path, blob, mime, stamp, size: blob.size, at: Date.now() })),
    getFile:  path => tx('files', 'readonly',  s => s.get(path)),
    delFile:  path => tx('files', 'readwrite', s => s.delete(path)),
    allFiles: ()   => tx('files', 'readonly',  s => s.getAll()),

    // ── 오프라인 저장 표시 ──
    markOffline:   songId => tx('offline', 'readwrite', s => s.put({ songId, at: Date.now() })),
    unmarkOffline: songId => tx('offline', 'readwrite', s => s.delete(songId)),
    offlineIds: () => tx('offline', 'readonly', s => s.getAll())
                        .then(rows => new Set(rows.map(r => r.songId))),

    // ── 잡다한 값 ──
    setMeta: (k, v) => tx('meta', 'readwrite', s => s.put({ k, v })),
    getMeta: k      => tx('meta', 'readonly',  s => s.get(k)).then(r => r && r.v),

    /** 저장된 악보 파일 용량 합계(바이트) */
    usedBytes: () => tx('files', 'readonly', s => s.getAll())
                       .then(rows => rows.reduce((a, r) => a + (r.size || 0), 0)),

    clearFiles: () => Promise.all([
      tx('files',   'readwrite', s => s.clear()),
      tx('offline', 'readwrite', s => s.clear()),
    ]),

    clearAll: () => Promise.all(['songs', 'files', 'offline', 'meta']
      .map(n => tx(n, 'readwrite', s => s.clear()))),
  };
})();
