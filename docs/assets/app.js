/* ============================================================================
 * 찬양 보관함 — 웹 + 설치형 앱(PWA)
 *
 * 동작 요약
 *  1) 켜면 기기에 캐시된 곡 목록을 즉시 그린다 (인터넷 없어도 바로 뜸)
 *  2) 온라인이면 Supabase에서 최신 목록을 받아 갈아끼운다
 *  3) Realtime 구독 — 다른 사람이 곡을 올리면 새로고침 없이 화면이 갱신된다
 *  4) 곡마다 '오프라인 저장'을 켜면 그 곡의 악보 파일만 기기에 내려받는다
 * ==========================================================================*/
'use strict';

/* ── 상수 ──────────────────────────────────────────────────────────────── */
const KEYS = ['C','C#','D','Eb','E','F','F#','G','Ab','A','Bb','B',
              'Cm','C#m','Dm','Ebm','Em','Fm','F#m','Gm','Abm','Am','Bbm','Bm'];
const PART_TYPES = ['Verse','Pre-Chorus','Chorus','Bridge','Intro','Tag','Ending'];

const CFG   = window.PRAISE_CONFIG || {};
const DEMO  = !CFG.url || !CFG.anonKey;
const BUCKET = CFG.bucket || 'sheets';

const sb = DEMO ? null : window.supabase.createClient(CFG.url, CFG.anonKey, {
  auth: { persistSession: false },
  realtime: { params: { eventsPerSecond: 5 } },
});

/* ── 상태 ──────────────────────────────────────────────────────────────── */
const state = {
  songs: [],
  offlineIds: new Set(),
  query: '',
  tab: 'all',          // all | offline
  online: navigator.onLine,
  live: false,         // Realtime 연결 여부
  syncing: false,
  lastSync: null,
  booted: false,
};

/* ── 잡유틸 ────────────────────────────────────────────────────────────── */
const $  = s => document.querySelector(s);
const esc = s => String(s == null ? '' : s)
  .replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;')
  .replace(/"/g,'&quot;').replace(/'/g,'&#39;');
const uid = () => (crypto.randomUUID ? crypto.randomUUID()
  : 'x' + Date.now().toString(36) + Math.random().toString(36).slice(2, 8));
const prettyKey = k => String(k).replace(/b/g,'♭').replace(/#/g,'♯');
const sortKeys = ks => [...ks].sort((a,b) => KEYS.indexOf(a) - KEYS.indexOf(b));
const byTitle  = list => [...list].sort((a,b) => a.title.localeCompare(b.title,'ko'));

function fmtSize(b){
  if (!b) return '';
  if (b < 1024) return b + 'B';
  if (b < 1048576) return Math.round(b / 1024) + 'KB';
  if (b < 1073741824) return (b / 1048576).toFixed(1) + 'MB';
  return (b / 1073741824).toFixed(1) + 'GB';
}
function fmtTime(ts){
  if (!ts) return '없음';
  const d = new Date(ts), p = n => String(n).padStart(2,'0');
  return `${d.getFullYear()}.${p(d.getMonth()+1)}.${p(d.getDate())} ${p(d.getHours())}:${p(d.getMinutes())}`;
}
/** 저장 경로에 쓸 짧은 무작위 토큰 */
function rid(){ return Math.random().toString(36).slice(2, 6); }

/** 파일명에서 확장자만 뽑는다. 없으면 mime으로 추정한다. */
function extOf(name, mime){
  const m = String(name).match(/\.[A-Za-z0-9]{1,5}$/);
  if (m) return m[0].toLowerCase();
  if (mime === 'application/pdf') return '.pdf';
  if (mime === 'image/png') return '.png';
  if (mime === 'image/jpeg') return '.jpg';
  return '';
}
function debounce(fn, ms){
  let t; return (...a) => { clearTimeout(t); t = setTimeout(() => fn(...a), ms); };
}

let toastTimer;
function toast(msg){
  const t = $('#toast');
  t.textContent = msg; t.classList.add('on');
  clearTimeout(toastTimer);
  toastTimer = setTimeout(() => t.classList.remove('on'), 2400);
}
function prog(pct){
  const p = $('#prog');
  if (pct >= 100){ p.style.width = '100%'; setTimeout(() => { p.style.width = '0'; }, 320); }
  else p.style.width = pct + '%';
}
async function copyText(text){
  try { await navigator.clipboard.writeText(text); toast('복사했습니다'); }
  catch (_) {
    const ta = document.createElement('textarea');
    ta.value = text; ta.style.position = 'fixed'; ta.style.opacity = '0';
    document.body.appendChild(ta); ta.select();
    try { document.execCommand('copy'); toast('복사했습니다'); }
    catch (e) { toast('복사에 실패했습니다'); }
    ta.remove();
  }
}

/* ── 기기에 저장된 악보를 <img>에 붙인다 ───────────────────────────────
 * blob URL은 화면을 다시 그릴 때 한꺼번에 회수하면 안 된다.
 * 동기화나 실시간 갱신이 이미지 로딩 도중에 끼어들면 URL이 먼저 사라져
 * 악보가 빈칸으로 뜬다. 그래서 이미지가 실제로 다 읽힌 뒤에만 회수한다.
 * ------------------------------------------------------------------ */
function makeImg(src, alt){
  const img = document.createElement('img');
  img.alt = alt;
  if (src.local){
    const release = () => URL.revokeObjectURL(src.url);
    img.addEventListener('load',  release, { once: true });
    img.addEventListener('error', release, { once: true });
  }
  img.src = src.url;
  return img;
}

/* ── 서버 row → 앱 내부 형태 ───────────────────────────────────────────── */
function normLyrics(raw){
  const o = (raw && typeof raw === 'object') ? raw : {};
  const sections = Array.isArray(o.sections) ? o.sections.map(s => ({
    id: String(s.id || uid()),
    type: String(s.type || 'Verse'),
    label: String(s.label || s.type || 'Verse'),
    text: String(s.text || ''),
  })) : [];
  const ids = new Set(sections.map(s => s.id));
  const arrangement = Array.isArray(o.arrangement)
    ? o.arrangement.map(String).filter(id => ids.has(id)) : [];
  return { sections, arrangement };
}

function normSheet(r){
  return {
    id: String(r.id || ''),
    songId: String(r.song_id || ''),
    musicKey: String(r.music_key || 'C'),
    path: String(r.file_path || ''),
    filename: String(r.filename || ''),
    mime: String(r.mime || 'application/octet-stream'),
    size: Number(r.size || 0),
    ord: Number(r.ord || 1),
    updatedAt: String(r.updated_at || ''),
  };
}

function buildSearchText(title, composer, tags, lyrics){
  return [title, composer, (tags||[]).join(' '),
          (lyrics.sections||[]).map(s => s.text).join(' ')].join(' ').toLowerCase();
}

function normSong(row){
  const lyrics = normLyrics(row.lyrics);
  const tags = Array.isArray(row.tags) ? row.tags.map(String) : [];
  const sheets = (Array.isArray(row.sheets) ? row.sheets : []).map(normSheet)
    .sort((a,b) => (KEYS.indexOf(a.musicKey) - KEYS.indexOf(b.musicKey)) || (a.ord - b.ord));
  return {
    id: String(row.id),
    title: String(row.title || ''),
    composer: String(row.composer || ''),
    tags, lyrics, sheets,
    keys: sortKeys([...new Set(sheets.map(s => s.musicKey))]),
    createdAt: row.created_at || null,
    updatedAt: row.updated_at || null,
    // 검색 인덱스. 서버가 만들어 준 값을 쓰고, 없으면 여기서 만든다.
    // (매 키 입력마다 가사를 다시 이어붙이지 않으려는 목적)
    s: String(row.search_text || buildSearchText(row.title, row.composer, tags, lyrics)),
  };
}

/* 곡의 특정 키에 속한 악보 페이지들 */
const pagesFor = (song, key) =>
  song.sheets.filter(s => s.musicKey === key).sort((a,b) => a.ord - b.ord);

/* 가사를 붙여넣기용 텍스트로 */
function lyricsToText(lyrics, withLabels){
  const map = new Map(lyrics.sections.map(s => [s.id, s]));
  const seq = lyrics.arrangement.length ? lyrics.arrangement : lyrics.sections.map(s => s.id);
  return seq.map(id => map.get(id)).filter(Boolean)
    .map(s => withLabels ? `[${s.label}]\n${s.text.trim()}` : s.text.trim())
    .join('\n\n');
}

/* ============================================================================
 * 서버 동기화 + 실시간
 * ==========================================================================*/
async function pull({ quiet = false } = {}){
  if (!sb || !navigator.onLine) return false;
  if (state.syncing) return false;
  state.syncing = true; renderHeader();
  if (!quiet) prog(35);
  try {
    const { data, error } = await sb
      .from('songs').select('*, sheets(*)').order('title', { ascending: true });
    if (error) throw error;

    state.songs = data.map(normSong);
    await IDB.replaceSongs(state.songs);
    state.lastSync = Date.now();
    await IDB.setMeta('lastSync', state.lastSync);

    renderAfterSync();              // 목록·가사는 여기서 이미 최신
    const changed = await syncOfflineFiles();   // 악보 파일은 뒤이어 정리 (저장한 곡만)
    if (changed) renderAfterSync();
    return true;
  } catch (e) {
    if (!quiet) toast('동기화 실패 — ' + (e.message || e));
    return false;
  } finally {
    state.syncing = false; renderHeader();
    if (!quiet) prog(100);
  }
}

/**
 * '오프라인 저장'을 켠 곡의 악보 파일을 기기 상태와 맞춘다.
 *  - 서버 updated_at(stamp)이 달라졌으면 다시 받는다
 *    → 누가 악보를 교체했을 때 예전 파일이 계속 보이는 문제를 막는다
 *  - 저장 대상이 아닌 파일은 지워 용량을 돌려준다
 */
async function syncOfflineFiles(){
  if (!sb || !navigator.onLine) return false;
  let changed = false;
  const wanted = new Map();          // path -> sheet
  for (const song of state.songs){
    if (!state.offlineIds.has(song.id)) continue;
    for (const sh of song.sheets) if (sh.path) wanted.set(sh.path, sh);
  }

  for (const f of await IDB.allFiles()){
    if (!wanted.has(f.path)){ await IDB.delFile(f.path); changed = true; }
  }
  for (const [path, sh] of wanted){
    const cached = await IDB.getFile(path);
    if (cached && cached.stamp === sh.updatedAt) continue;
    try {
      const blob = await downloadSheet(sh);
      await IDB.putFile(path, blob, sh.mime, sh.updatedAt);
      changed = true;
    } catch (_) { /* 개별 실패는 넘어간다. 다음 동기화에서 다시 시도된다 */ }
  }
  return changed;
}

async function downloadSheet(sheet){
  const { data, error } = await sb.storage.from(BUCKET).download(sheet.path);
  if (error) throw error;
  return data;                       // Blob
}

/**
 * 편집 화면에서는 화면을 다시 그리지 않는다.
 * 다른 사람의 변경으로 입력칸이 통째로 새로 그려지면
 * 타이핑 중이던 내용과 커서가 끊긴다.
 */
function renderAfterSync(){
  if (route().name === 'edit'){ renderHeader(); return; }
  render();
}

const onRemoteChange = debounce(() => pull({ quiet: true }), 600);

function subscribeRealtime(){
  if (!sb) return;
  sb.channel('praise-archive')
    .on('postgres_changes', { event: '*', schema: 'public', table: 'songs'  }, onRemoteChange)
    .on('postgres_changes', { event: '*', schema: 'public', table: 'sheets' }, onRemoteChange)
    .subscribe(status => {
      state.live = (status === 'SUBSCRIBED');
      renderHeader();
    });
}

/* ============================================================================
 * 오프라인 저장 토글
 * ==========================================================================*/
async function toggleOffline(songId){
  const song = state.songs.find(s => s.id === songId);
  if (!song) return;

  if (state.offlineIds.has(songId)){
    state.offlineIds.delete(songId);
    await IDB.unmarkOffline(songId);
    for (const sh of song.sheets) await IDB.delFile(sh.path);
    toast('오프라인 저장을 해제했습니다');
    render();
    return;
  }

  if (!navigator.onLine || !sb){
    toast('온라인일 때만 새로 저장할 수 있습니다');
    return;
  }

  const sheets = song.sheets.filter(s => s.path);
  let done = 0, failed = 0;
  prog(5);
  for (const sh of sheets){
    try {
      const blob = await downloadSheet(sh);
      await IDB.putFile(sh.path, blob, sh.mime, sh.updatedAt);
    } catch (_) { failed++; }
    done++;
    prog(Math.round(5 + (done / Math.max(1, sheets.length)) * 90));
  }
  prog(100);

  // PDF가 섞여 있으면 PDF 뷰어 코드(pdf.js)도 지금 받아 둔다.
  // 이걸 안 하면 나중에 오프라인에서 PDF 악보만 안 열린다.
  if (sheets.some(s => s.mime === 'application/pdf')){
    try { await pdfjs(); } catch (_) {}
  }

  // 브라우저가 공간이 부족할 때 저장해 둔 악보를 임의로 지우지 않도록 요청한다.
  // 홈 화면에 추가해 쓰는 경우 대체로 승인된다.
  if (navigator.storage && navigator.storage.persist){
    try { await navigator.storage.persist(); } catch (_) {}
  }

  state.offlineIds.add(songId);
  await IDB.markOffline(songId);
  toast(failed
    ? `${sheets.length - failed}장 저장 · ${failed}장 실패`
    : (sheets.length ? `악보 ${sheets.length}장을 기기에 저장했습니다` : '가사를 기기에 저장했습니다'));
  render();
}

/* ============================================================================
 * 악보 파일 위치 찾기 — 기기에 있으면 그것을, 없으면 서버 공개 URL을
 * ==========================================================================*/
function publicUrl(path){
  const enc = String(path).split('/').map(encodeURIComponent).join('/');
  return `${CFG.url}/storage/v1/object/public/${BUCKET}/${enc}`;
}

async function sheetSource(sheet){
  const f = await IDB.getFile(sheet.path);
  if (f && f.blob) return { url: URL.createObjectURL(f.blob), blob: f.blob, local: true };
  if (DEMO || !navigator.onLine) return null;
  return { url: publicUrl(sheet.path), blob: null, local: false };
}

/* ── PDF 렌더링 (필요할 때만 pdf.js를 불러온다) ────────────────────────── */
let _pdfjs = null;
async function pdfjs(){
  if (_pdfjs) return _pdfjs;
  // 파일 내용은 ES 모듈이지만 확장자는 .js 로 둔다.
  // .mjs 를 text/javascript 로 안 내려주는 정적 호스팅이 있어서,
  // 어디에 올려도 동작하도록 확장자만 안전한 쪽으로 맞춘 것이다.
  const lib = await import(new URL('vendor/pdf.min.js', document.baseURI).href);
  lib.GlobalWorkerOptions.workerSrc = new URL('vendor/pdf.worker.min.js', document.baseURI).href;
  _pdfjs = lib;
  return lib;
}

async function renderPdf(container, src, { allPages = false } = {}){
  const lib = await pdfjs();
  const task = src.blob
    ? lib.getDocument({ data: await src.blob.arrayBuffer() })
    : lib.getDocument(src.url);
  const doc = await task.promise;
  const last = allPages ? doc.numPages : 1;
  const cssW = Math.max(280, container.clientWidth || 320);
  const dpr = Math.min(2, window.devicePixelRatio || 1);

  container.innerHTML = '';
  for (let i = 1; i <= last; i++){
    const page = await doc.getPage(i);
    const base = page.getViewport({ scale: 1 });
    const vp = page.getViewport({ scale: (cssW / base.width) * dpr });
    const canvas = document.createElement('canvas');
    canvas.width = Math.floor(vp.width);
    canvas.height = Math.floor(vp.height);
    canvas.style.width = '100%';
    container.appendChild(canvas);
    await page.render({ canvasContext: canvas.getContext('2d'), viewport: vp }).promise;
  }
  if (!allPages && doc.numPages > 1){
    const more = document.createElement('div');
    more.className = 'ph';
    more.textContent = `PDF ${doc.numPages}쪽 — 눌러서 전체 보기`;
    container.appendChild(more);
  }
}

/* ============================================================================
 * 라우팅 — #/ 목록 · #/song/:id 상세 · #/edit/:id 편집 · #/new 새 곡 · #/settings
 * ==========================================================================*/
function route(){
  const h = (location.hash || '#/').slice(1);
  const [, a, b] = h.split('/');
  if (a === 'song'     && b) return { name: 'detail',   id: decodeURIComponent(b) };
  if (a === 'edit'     && b) return { name: 'edit',     id: decodeURIComponent(b) };
  if (a === 'new')           return { name: 'edit',     id: null };
  if (a === 'settings')      return { name: 'settings' };
  return { name: 'list' };
}
/**
 * 화면 이동.
 * replace=true 면 방문 기록을 새로 쌓지 않고 현재 기록을 갈아끼운다.
 * 편집 화면이 기록에 남아 있으면 뒤로가기가 편집 화면으로 되돌아가기 때문에,
 * 편집 화면을 드나들 때는 항상 replace 를 쓴다.
 */
function go(hash, replace){
  if (replace){
    history.replaceState(null, '', hash);
    window.scrollTo(0, 0);
    render();
    return;
  }
  if (location.hash === hash) { window.scrollTo(0, 0); render(); return; }
  location.hash = hash;
}

let renderToken = 0;   // 화면이 바뀌면 앞서 돌던 비동기 그리기를 버리기 위한 표식

function render(){
  renderToken++;
  renderHeader();
  const r = route();
  if (r.name === 'detail')        viewDetail(r.id);
  else if (r.name === 'edit')     viewEditor(r.id);
  else if (r.name === 'settings') viewSettings();
  else                            viewList();
}

/* ── 헤더 ──────────────────────────────────────────────────────────────── */
function renderHeader(){
  const r = route();
  const onList = r.name === 'list';

  let badge = '';
  if (state.syncing)      badge = '<span class="badge"><span class="spin"></span>동기화</span>';
  else if (!state.online) badge = '<span class="badge">오프라인</span>';
  else if (DEMO)          badge = '<span class="badge">데모</span>';
  else if (state.live)    badge = '<span class="badge live"><span class="dot"></span>실시간</span>';

  $('#hd').innerHTML = `
    <div class="hd-row">
      ${onList
        ? '<span class="hd-note">♪</span>'
        : '<button class="hd-btn" data-act="back" aria-label="뒤로">‹</button>'}
      <div class="hd-grow">
        <div class="hd-t">${onList ? '찬양 보관함' : (r.name === 'edit' ? '곡 편집'
                          : r.name === 'settings' ? '설정' : '찬양 보관함')}</div>
        ${onList ? '<div class="hd-s">제목·가사로 찾고, 키별 악보를 바로</div>' : ''}
      </div>
      ${badge}
      ${onList ? '<button class="hd-btn" data-act="settings" aria-label="설정">⚙</button>' : ''}
    </div>
    ${onList ? `
    <div class="search">
      <span class="ico">⌕</span>
      <input id="q" type="search" inputmode="search" autocomplete="off"
             placeholder="제목 · 가사 · 키로 검색 (예: G, Eb, Am)"
             value="${esc(state.query)}">
      <button class="clr" data-act="clearq" aria-label="지우기" ${state.query ? '' : 'hidden'}>×</button>
    </div>` : ''}
  `;

  if (onList){
    const input = $('#q');
    input.addEventListener('input', onSearchInput);
    if (state.focusSearch){ input.focus(); state.focusSearch = false; }
  }

  $('#fab').innerHTML = onList
    ? '<button class="fab" data-act="new">＋ 곡 추가</button>' : '';
}

// 헤더를 다시 그리면 입력 중이던 한글 조합과 커서가 끊긴다.
// 그래서 검색 중에는 목록 영역만 다시 그린다.
const onSearchInput = debounce(() => {
  const input = $('#q');
  if (!input) return;
  state.query = input.value;
  const clr = document.querySelector('.search .clr');
  if (clr) clr.hidden = !state.query;
  viewList();
}, 180);

/* ── 목록 ──────────────────────────────────────────────────────────────── */
function filtered(){
  let list = state.songs;
  if (state.tab === 'offline') list = list.filter(s => state.offlineIds.has(s.id));

  const q = state.query.trim().toLowerCase().replace(/♭/g,'b').replace(/♯/g,'#');
  if (!q) return byTitle(list);

  const keyQ = KEYS.find(k => k.toLowerCase() === q);
  if (keyQ) return byTitle(list.filter(s => s.keys.includes(keyQ)));
  return byTitle(list.filter(s => s.s.includes(q)));
}

/** 가사에서 검색어가 걸린 부분을 한 줄 뽑아 보여준다 */
function lyricHit(song, q){
  if (!q || song.title.toLowerCase().includes(q)) return '';
  for (const sec of song.lyrics.sections){
    const i = sec.text.toLowerCase().indexOf(q);
    if (i < 0) continue;
    const from = Math.max(0, i - 18);
    const cut = sec.text.slice(from, i + q.length + 42).replace(/\n/g, ' ');
    const head = esc((from ? '…' : '') + cut.slice(0, i - from));
    const hit  = esc(cut.slice(i - from, i - from + q.length));
    const tail = esc(cut.slice(i - from + q.length) + '…');
    return `<div class="hit"><b>${esc(sec.label)}</b> · ${head}<mark>${hit}</mark>${tail}</div>`;
  }
  return '';
}

function viewList(){
  const q = state.query.trim().toLowerCase();
  const items = filtered();
  const keyQ = KEYS.find(k => k.toLowerCase() === q.replace(/♭/g,'b').replace(/♯/g,'#'));
  const offCount = state.offlineIds.size;

  const head = `
    <div class="chips">
      <button class="chip" data-tab="all"     aria-pressed="${state.tab === 'all'}">전체 ${state.songs.length}</button>
      <button class="chip" data-tab="offline" aria-pressed="${state.tab === 'offline'}">오프라인 저장 ${offCount}</button>
    </div>
    <div class="bar">
      <h2>곡 목록</h2>
      <span class="cnt">${keyQ ? `${prettyKey(keyQ)} 키 · ${items.length}곡`
                               : `${items.length}곡${q && items.length !== state.songs.length ? ' 검색됨' : ''}`}</span>
    </div>`;

  if (!state.booted){
    $('#app').innerHTML = head + '<div class="sk"></div><div class="sk"></div><div class="sk"></div>';
    return;
  }

  if (!items.length){
    let msg;
    if (!state.songs.length)          msg = DEMO
      ? '데모 모드입니다.\nconfig.js에 Supabase 주소와 키를 넣으면\n실제 곡이 연결됩니다.'
      : !state.online
      ? '오프라인입니다.\n한 번이라도 온라인으로 접속하면\n곡 목록이 기기에 저장됩니다.'
      : '아직 곡이 없습니다.\n오른쪽 아래 + 버튼으로 첫 곡을 등록해 보세요.';
    else if (state.tab === 'offline') msg = '오프라인 저장한 곡이 없습니다.\n곡을 열어 "오프라인 저장"을 켜 두면\n인터넷 없이도 악보가 열립니다.';
    else if (keyQ)                    msg = `${prettyKey(keyQ)} 키로 등록된 곡이 없습니다.`;
    else                              msg = '검색 결과가 없습니다.';
    $('#app').innerHTML = head +
      `<div class="empty"><div class="big">♫</div><p>${esc(msg)}</p></div>`;
    return;
  }

  $('#app').innerHTML = head + '<div class="list">' + items.map(s => `
    <button class="item" data-song="${esc(s.id)}">
      <span class="hd-grow">
        <span class="ttl">${esc(s.title || '(제목 없음)')}</span>
        <span class="sub">
          ${s.composer ? `<span class="cmp">${esc(s.composer)}</span>` : ''}
          ${s.keys.map(k => `<span class="k${k === keyQ ? ' on' : ''}">${prettyKey(k)}</span>`).join('')}
          ${state.offlineIds.has(s.id) ? '<span class="save-dot">✓ 저장됨</span>' : ''}
        </span>
        ${keyQ ? '' : lyricHit(s, q)}
      </span>
      <span class="arrow">›</span>
    </button>`).join('') + '</div>';
}

/* ── 상세 ──────────────────────────────────────────────────────────────── */
const detailUI = { key: null, songId: null };

function viewDetail(id){
  const song = state.songs.find(s => s.id === id);
  if (!song){
    $('#app').innerHTML = `<div class="empty"><div class="big">♪</div>
      <p>곡을 찾을 수 없습니다.\n삭제되었거나 아직 동기화되지 않았습니다.</p></div>`;
    return;
  }
  if (detailUI.songId !== id){ detailUI.songId = id; detailUI.key = null; }
  if (!detailUI.key || !song.keys.includes(detailUI.key)) detailUI.key = song.keys[0] || null;

  const saved = state.offlineIds.has(song.id);
  const key = detailUI.key;
  const pages = key ? pagesFor(song, key) : [];
  const lyr = song.lyrics;
  const seq = lyr.arrangement.length ? lyr.arrangement : lyr.sections.map(s => s.id);
  const secMap = new Map(lyr.sections.map(s => [s.id, s]));

  $('#app').innerHTML = `
    <section class="card sec">
      <h1 class="title-xl">${esc(song.title || '(제목 없음)')}</h1>
      <div class="meta-row">${esc(song.composer || '작곡가 미상')}${
        song.keys.length ? ` · 키 ${song.keys.map(prettyKey).join(', ')}` : ''}</div>
      ${song.tags.length ? `<div class="tags">${song.tags.map(t => `<span class="tag">#${esc(t)}</span>`).join('')}</div>` : ''}
      <div class="btnrow" style="margin-top:14px">
        <button class="btn sm" data-act="edit" data-id="${esc(song.id)}">곡 수정</button>
        <button class="btn sm dgr" data-act="delsong" data-id="${esc(song.id)}">곡 삭제</button>
      </div>
    </section>

    <section class="card sec">
      <button class="toggle${saved ? ' on' : ''}" data-act="offline" data-id="${esc(song.id)}">
        <span class="ic">${saved ? '✓' : '⤓'}</span>
        <span class="hd-grow">
          <span class="t1">${saved ? '이 기기에 저장됨' : '오프라인 저장'}</span>
          <span class="t2">${saved
            ? '인터넷이 없어도 악보와 가사가 열립니다. 눌러서 해제'
            : `악보 ${song.sheets.length}장을 기기에 받아 둡니다`}</span>
        </span>
      </button>
    </section>

    <section class="card sec">
      <div class="sec-h"><h3>🎼 악보 — 키 선택</h3>
        ${pages.length > 1 ? `<button class="btn sm" data-act="viewall" data-key="${esc(key)}">전체 보기</button>` : ''}
      </div>
      ${song.keys.length ? `
        <div class="keybar">${song.keys.map(k => `
          <button class="keybtn" data-key="${esc(k)}" aria-pressed="${k === key}">
            <b>${prettyKey(k)}</b><span>${k === key ? '선택됨' : pagesFor(song, k).length + '장'}</span>
          </button>`).join('')}</div>
        <div id="sheets"></div>`
      : '<div class="note">등록된 악보가 없습니다. ‘곡 수정’에서 키별 악보를 올려 주세요.</div>'}
    </section>

    <section class="card sec">
      <div class="sec-h"><h3>가사</h3>
        <div class="btnrow">
          <button class="btn sm" data-act="copy" data-labels="1">라벨 포함 복사</button>
          <button class="btn sm" data-act="copy" data-labels="0">가사만 복사</button>
        </div>
      </div>
      ${lyr.sections.length ? seq.map(sid => {
          const s = secMap.get(sid); if (!s) return '';
          return `<div class="lyr-part">
            <div class="lyr-lab">${esc(s.label)}</div>
            <div class="lyr-txt">${esc(s.text)}</div></div>`;
        }).join('')
      : '<div class="note">등록된 가사가 없습니다.</div>'}
      ${lyr.arrangement.length ? `
        <div class="sec-h" style="margin:16px 0 8px"><h3>배치 순서</h3></div>
        <div class="arr">${lyr.arrangement.map((sid, i) => {
          const s = secMap.get(sid); if (!s) return '';
          return `<span class="step"><i>${i + 1}</i>${esc(s.label)}</span>`;
        }).join('')}</div>` : ''}
    </section>`;

  if (key) paintSheets(song, key);
}

/** 선택한 키의 악보 페이지를 그린다 */
async function paintSheets(song, key){
  const myToken = renderToken;
  const box = $('#sheets');
  if (!box) return;
  const pages = pagesFor(song, key);
  if (!pages.length){
    box.innerHTML = '<div class="sheet"><div class="ph">이 키의 악보가 없습니다.</div></div>';
    return;
  }

  box.innerHTML = pages.map((sh, i) => `
    <div class="pg">
      ${pages.length > 1 ? `<div class="pg-lab">${i + 1} / ${pages.length} 쪽</div>` : ''}
      <div class="sheet" id="sh-${esc(sh.id)}" data-act="open" data-sheet="${esc(sh.id)}">
        <div class="ph">불러오는 중…</div>
      </div>
    </div>`).join('');

  for (const sh of pages){
    if (myToken !== renderToken) return;      // 그 사이 다른 화면으로 넘어갔다
    const host = document.getElementById('sh-' + sh.id);
    if (!host) continue;
    const src = await sheetSource(sh);
    if (myToken !== renderToken) { if (src && src.local) URL.revokeObjectURL(src.url); return; }
    if (!src){
      host.innerHTML = `<div class="ph">${state.online
        ? '악보를 불러오지 못했습니다.'
        : '오프라인입니다.\n이 곡을 저장해 두면 인터넷 없이도 볼 수 있습니다.'}</div>`;
      continue;
    }
    if (sh.mime === 'application/pdf'){
      try { await renderPdf(host, src); }
      catch (_) { host.innerHTML = '<div class="ph">PDF를 여는 데 실패했습니다.</div>'; }
      if (src.local) URL.revokeObjectURL(src.url);   // pdf.js는 바이트를 직접 받으므로 바로 회수 가능
    } else {
      host.innerHTML = '';
      host.appendChild(makeImg(src, `${song.title} ${prettyKey(key)} 악보`));
    }
  }
}

/* ── 전체화면 뷰어 ─────────────────────────────────────────────────────── */
async function openViewer(song, sheets, startTitle){
  const v = $('#viewer');
  v.innerHTML = `
    <div class="viewer">
      <div class="viewer-hd">
        <button class="hd-btn" data-act="closeviewer" aria-label="닫기">✕</button>
        <div class="vt">${esc(startTitle)}</div>
        <button class="hd-btn" data-act="zoom" aria-label="확대">＋</button>
      </div>
      <div class="viewer-bd" id="vbody"><div class="ph" style="color:#999">불러오는 중…</div></div>
    </div>`;
  document.body.style.overflow = 'hidden';

  const body = $('#vbody');
  body.innerHTML = '';
  for (const sh of sheets){
    const src = await sheetSource(sh);
    if (!src){
      const p = document.createElement('div');
      p.className = 'ph'; p.style.color = '#999';
      p.textContent = '이 악보는 오프라인에서 볼 수 없습니다.';
      body.appendChild(p);
      continue;
    }
    const holder = document.createElement('div');
    body.appendChild(holder);
    if (sh.mime === 'application/pdf'){
      try { await renderPdf(holder, src, { allPages: true }); }
      catch (_) { holder.textContent = 'PDF를 여는 데 실패했습니다.'; }
      if (src.local) URL.revokeObjectURL(src.url);
    } else {
      holder.appendChild(makeImg(src, sh.filename));
    }
  }
}

function closeViewer(){
  $('#viewer').innerHTML = '';
  document.body.style.overflow = '';
}

let viewerZoom = 1;
function zoomViewer(){
  viewerZoom = viewerZoom >= 3 ? 1 : viewerZoom + 0.5;
  $('#vbody').querySelectorAll('img,canvas').forEach(n => {
    n.style.width = (100 * viewerZoom) + '%';
    n.style.maxWidth = 'none';
  });
  toast(`${Math.round(viewerZoom * 100)}%`);
}

/* ============================================================================
 * 편집 화면
 * ==========================================================================*/
let ed = null;   // { id, title, composer, tagsText, sections[], arrangement[] }

function viewEditor(id){
  const song = id ? state.songs.find(s => s.id === id) : null;
  if (id && !song){ $('#app').innerHTML = '<div class="empty"><p>곡을 찾을 수 없습니다.</p></div>'; return; }

  if (!ed || ed.id !== (id || null)){
    ed = song ? {
      id: song.id, title: song.title, composer: song.composer,
      tagsText: song.tags.join(', '),
      sections: song.lyrics.sections.map(s => ({ ...s })),
      arrangement: [...song.lyrics.arrangement],
    } : { id: null, title: '', composer: '', tagsText: '', sections: [], arrangement: [] };
  }

  const secMap = new Map(ed.sections.map(s => [s.id, s]));
  const blocked = DEMO ? '데모 모드입니다. 저장은 되지 않습니다.'
                 : !state.online ? '오프라인입니다. 온라인이 되면 저장할 수 있습니다.' : '';

  $('#app').innerHTML = `
    ${blocked ? `<div class="note warn" style="margin-bottom:14px">${esc(blocked)}</div>` : ''}

    <section class="card sec">
      <label class="f" for="e-title">곡 제목</label>
      <input class="in" id="e-title" data-ed="title" value="${esc(ed.title)}" placeholder="예) 주 은혜임을">
      <label class="f" for="e-comp">작곡가 · 원곡</label>
      <input class="in" id="e-comp" data-ed="composer" value="${esc(ed.composer)}" placeholder="예) 마커스워십">
      <label class="f" for="e-tags">태그 (쉼표로 구분)</label>
      <input class="in" id="e-tags" data-ed="tagsText" value="${esc(ed.tagsText)}" placeholder="예) 경배, 느린곡, 성탄">
    </section>

    <section class="card sec">
      <div class="sec-h"><h3>가사 파트</h3></div>
      <div class="chips">${PART_TYPES.map(t =>
        `<button class="chip" data-act="addpart" data-type="${esc(t)}">＋ ${esc(t)}</button>`).join('')}</div>
      ${ed.sections.length ? ed.sections.map((s, i) => `
        <div class="part">
          <div class="part-h">
            <input class="in" data-sec="${esc(s.id)}" data-field="label" value="${esc(s.label)}">
            <button class="btn sm" data-act="toarr" data-sec="${esc(s.id)}">배치에 추가</button>
            <button class="btn sm dgr" data-act="delpart" data-sec="${esc(s.id)}">삭제</button>
          </div>
          <textarea class="in" data-sec="${esc(s.id)}" data-field="text"
            placeholder="가사를 입력하세요">${esc(s.text)}</textarea>
        </div>`).join('')
      : '<div class="note">위에서 파트를 눌러 가사를 추가하세요. Verse·Chorus 단위로 나눠 두면 배치 순서를 자유롭게 짤 수 있습니다.</div>'}
    </section>

    <section class="card sec">
      <div class="sec-h"><h3>배치 순서</h3>
        ${ed.arrangement.length ? '<button class="btn sm" data-act="clararr">전체 지우기</button>' : ''}
      </div>
      ${ed.arrangement.length ? `<div class="arr">${ed.arrangement.map((sid, i) => {
        const s = secMap.get(sid); if (!s) return '';
        return `<span class="step"><i>${i + 1}</i>${esc(s.label)}
          <button data-act="delarr" data-idx="${i}" aria-label="빼기" style="color:var(--ink-faint)">✕</button></span>`;
      }).join('')}</div>`
      : '<div class="note">비워 두면 위에 적은 파트 순서대로 표시됩니다. 1절-후렴-1절처럼 반복이 필요할 때만 채우면 됩니다.</div>'}
    </section>

    <section class="card sec">
      <div class="sec-h"><h3>🎼 키별 악보</h3></div>
      ${!ed.id
        ? '<div class="note">곡을 먼저 저장하면 악보를 올릴 수 있습니다.</div>'
        : renderSheetEditor(state.songs.find(s => s.id === ed.id))}
    </section>

    <div class="btnrow" style="margin-top:4px">
      <button class="btn pri" data-act="save" ${blocked ? 'disabled' : ''}>저장</button>
      <button class="btn" data-act="back">취소</button>
    </div>`;

  $('#app').querySelectorAll('[data-ed]').forEach(inp => {
    inp.addEventListener('input', e => { ed[e.target.dataset.ed] = e.target.value; });
  });
  $('#app').querySelectorAll('[data-sec][data-field]').forEach(inp => {
    inp.addEventListener('input', e => {
      const s = ed.sections.find(x => x.id === e.target.dataset.sec);
      if (s) s[e.target.dataset.field] = e.target.value;
    });
  });
  const picker = $('#e-file');
  if (picker) picker.addEventListener('change', onPickFiles);
}

function renderSheetEditor(song){
  if (!song) return '<div class="note">저장 후 다시 열어 주세요.</div>';
  const rows = song.keys.map(k => `
    <div style="margin-bottom:12px">
      <div class="lyr-lab">${prettyKey(k)} — ${pagesFor(song, k).length}장</div>
      ${pagesFor(song, k).map(sh => `
        <div class="upl">
          <span>${sh.mime === 'application/pdf' ? '📄' : '🖼'}</span>
          <span class="nm">${esc(sh.filename || sh.path)}</span>
          <span class="sz">${fmtSize(sh.size)}</span>
          <button class="btn sm dgr" data-act="delsheet" data-sheet="${esc(sh.id)}">삭제</button>
        </div>`).join('')}
    </div>`).join('');

  return rows + `
    <label class="f" for="e-key">악보를 추가할 키</label>
    <select class="in" id="e-key">
      ${KEYS.map(k => `<option value="${k}">${prettyKey(k)}</option>`).join('')}
    </select>
    <label class="f" for="e-file">악보 파일 (이미지 · PDF, 여러 장 선택 가능)</label>
    <input class="in" id="e-file" type="file" accept="image/*,application/pdf" multiple>
    <div class="note" style="margin-top:10px">고른 순서대로 1쪽, 2쪽으로 등록됩니다.</div>`;
}

async function onPickFiles(e){
  const files = [...e.target.files];
  e.target.value = '';
  if (!files.length) return;
  if (DEMO || !state.online){ toast('온라인일 때만 올릴 수 있습니다'); return; }

  const key = $('#e-key').value;
  const song = state.songs.find(s => s.id === ed.id);
  let ord = pagesFor(song, key).reduce((m, s) => Math.max(m, s.ord), 0);
  let ok = 0;

  prog(5);
  for (let i = 0; i < files.length; i++){
    const file = files[i];
    ord++;
    const mime = file.type || 'application/octet-stream';
    // 저장 경로에는 원본 파일명을 넣지 않는다.
    // Supabase Storage 키는 ASCII만 허용해서 한글 파일명이면 'Invalid key'로 실패한다.
    // 원본 이름은 sheets.filename 컬럼에 그대로 남긴다.
    //
    // 교체할 때도 항상 새 경로를 쓴다. 같은 경로를 재사용하면 다른 사람 기기에
    // 이미 받아 둔 예전 파일이 계속 보이게 된다.
    const path = `${ed.id}/${key}_p${ord}_${Date.now()}_${rid()}${extOf(file.name, mime)}`;
    try {
      const up = await sb.storage.from(BUCKET)
        .upload(path, file, { contentType: mime, upsert: false });
      if (up.error) throw up.error;
      const ins = await sb.from('sheets').insert({
        song_id: ed.id, music_key: key, file_path: path,
        filename: file.name, mime, size: file.size, ord,
      });
      if (ins.error) throw ins.error;
      ok++;
    } catch (err) { toast('업로드 실패 — ' + (err.message || err)); }
    prog(Math.round(5 + ((i + 1) / files.length) * 90));
  }
  prog(100);
  if (ok) { toast(`${ok}장을 올렸습니다`); await pull({ quiet: true }); render(); }
}

async function saveSong(){
  if (DEMO){ toast('데모 모드에서는 저장할 수 없습니다'); return; }
  if (!state.online){ toast('오프라인에서는 저장할 수 없습니다'); return; }
  if (!ed.title.trim()){ toast('곡 제목을 입력해 주세요'); return; }

  const tags = ed.tagsText.split(',').map(t => t.trim()).filter(Boolean);
  const ids = new Set(ed.sections.map(s => s.id));
  const payload = {
    title: ed.title.trim(),
    composer: ed.composer.trim(),
    tags,
    lyrics: {
      sections: ed.sections.map(s => ({ id: s.id, type: s.type, label: s.label, text: s.text })),
      arrangement: ed.arrangement.filter(id => ids.has(id)),
    },
  };

  prog(40);
  try {
    if (ed.id){
      const { error } = await sb.from('songs').update(payload).eq('id', ed.id);
      if (error) throw error;
      await pull({ quiet: true });
      toast('저장했습니다');
      const id = ed.id;
      ed = null;
      go('#/song/' + id, true);
    } else {
      const { data, error } = await sb.from('songs').insert(payload).select().single();
      if (error) throw error;
      await pull({ quiet: true });
      toast('곡을 등록했습니다. 이어서 악보를 올릴 수 있습니다.');
      ed = null;
      go('#/edit/' + data.id, true);
    }
  } catch (e) {
    toast('저장 실패 — ' + (e.message || e));
  } finally { prog(100); }
}

async function deleteSong(id){
  if (DEMO || !state.online){ toast('온라인일 때만 삭제할 수 있습니다'); return; }
  const song = state.songs.find(s => s.id === id);
  if (!song) return;
  if (!confirm(`"${song.title}" 곡과 악보·가사를 모두 삭제합니다.\n되돌릴 수 없습니다. 진행할까요?`)) return;

  prog(30);
  try {
    const paths = song.sheets.map(s => s.path).filter(Boolean);
    if (paths.length) await sb.storage.from(BUCKET).remove(paths);
    const { error } = await sb.from('songs').delete().eq('id', id);   // sheets는 FK CASCADE로 함께 삭제
    if (error) throw error;
    for (const p of paths) await IDB.delFile(p);
    state.offlineIds.delete(id); await IDB.unmarkOffline(id);
    await pull({ quiet: true });
    toast('삭제했습니다');
    go('#/', true);
  } catch (e) { toast('삭제 실패 — ' + (e.message || e)); }
  finally { prog(100); }
}

async function deleteSheet(sheetId){
  if (DEMO || !state.online){ toast('온라인일 때만 삭제할 수 있습니다'); return; }
  const song = state.songs.find(s => s.id === ed?.id) || state.songs.find(s => s.sheets.some(x => x.id === sheetId));
  const sh = song && song.sheets.find(x => x.id === sheetId);
  if (!sh) return;
  if (!confirm(`악보 "${sh.filename}" 을(를) 삭제할까요?`)) return;
  try {
    if (sh.path) await sb.storage.from(BUCKET).remove([sh.path]);
    const { error } = await sb.from('sheets').delete().eq('id', sheetId);
    if (error) throw error;
    await IDB.delFile(sh.path);
    await pull({ quiet: true });
    toast('악보를 삭제했습니다');
    render();
  } catch (e) { toast('삭제 실패 — ' + (e.message || e)); }
}

/* ============================================================================
 * 설정
 * ==========================================================================*/
async function viewSettings(){
  const used = await IDB.usedBytes();
  const files = await IDB.allFiles();
  const quota = navigator.storage && navigator.storage.estimate
    ? await navigator.storage.estimate().catch(() => null) : null;

  $('#app').innerHTML = `
    <section class="card sec">
      <div class="sec-h"><h3>연결</h3></div>
      ${DEMO ? `<div class="note warn">데모 모드입니다. <code>config.js</code>의
        <b>url</b>과 <b>anonKey</b>를 채우면 실제 서버에 연결됩니다.</div>`
        : `<div class="lyr-txt" style="font-size:13px">
             ${state.online ? (state.live ? '실시간 연결됨 — 다른 사람이 올린 곡이 바로 반영됩니다.'
                                          : '온라인 (실시간 연결 대기 중)')
                            : '오프라인 — 저장해 둔 곡만 열립니다.'}
           </div>`}
      <div class="meta-row" style="margin-top:8px">마지막 동기화 · ${esc(fmtTime(state.lastSync))}</div>
      <div class="btnrow" style="margin-top:12px">
        <button class="btn" data-act="sync" ${DEMO || !state.online ? 'disabled' : ''}>지금 동기화</button>
      </div>
    </section>

    <section class="card sec">
      <div class="sec-h"><h3>기기 저장 용량</h3></div>
      <div class="lyr-txt" style="font-size:13px">
        곡 ${state.songs.length}개 · 오프라인 저장 ${state.offlineIds.size}곡 · 악보 파일 ${files.length}장<br>
        사용 중 ${esc(fmtSize(used) || '0B')}${quota && quota.quota
          ? ` / 브라우저 허용 약 ${esc(fmtSize(quota.quota))}` : ''}
      </div>
      <div class="btnrow" style="margin-top:12px">
        <button class="btn dgr" data-act="clearfiles">저장한 악보 비우기</button>
        <button class="btn dgr" data-act="clearall">전체 초기화</button>
      </div>
      <div class="note" style="margin-top:10px">비워도 서버의 원본은 지워지지 않습니다.
        다음에 다시 저장하면 그대로 돌아옵니다.</div>
    </section>

    <section class="card sec">
      <div class="sec-h"><h3>홈 화면에 설치</h3></div>
      <div class="lyr-txt" style="font-size:13px">
        아이폰 — 사파리에서 열고 아래 <b>공유</b> 버튼 → <b>홈 화면에 추가</b><br>
        안드로이드 — 크롬 오른쪽 위 <b>⋮</b> → <b>앱 설치</b><br>
        설치하면 주소창 없이 앱처럼 열리고, 저장해 둔 곡은 비행기 모드에서도 보입니다.
      </div>
    </section>`;
}

/* ============================================================================
 * 이벤트 (클릭은 한 군데서 위임 처리)
 * ==========================================================================*/
document.addEventListener('click', async e => {
  const t = e.target.closest('[data-act],[data-song],[data-key],[data-tab]');
  if (!t) return;
  const act = t.dataset.act;

  if (t.dataset.tab){ state.tab = t.dataset.tab; render(); return; }
  if (t.dataset.song){ go('#/song/' + encodeURIComponent(t.dataset.song)); return; }

  if (t.dataset.key && !act){                       // 상세 화면의 키 선택
    detailUI.key = t.dataset.key;
    const song = state.songs.find(s => s.id === detailUI.songId);
    if (song) viewDetail(song.id);
    return;
  }

  switch (act){
    case 'back': {
      const r = route();
      // 편집 화면에서는 그 곡의 상세로, 그 외에는 목록으로.
      if (r.name === 'edit' && r.id) go('#/song/' + encodeURIComponent(r.id), true);
      else go('#/', true);
      break;
    }
    case 'settings':  go('#/settings'); break;
    case 'new':       ed = null; go('#/new'); break;
    case 'edit':      ed = null; go('#/edit/' + encodeURIComponent(t.dataset.id), true); break;
    case 'clearq': {
      state.query = '';
      const input = $('#q');
      if (input){ input.value = ''; input.focus(); }
      t.hidden = true;
      viewList();
      break;
    }
    case 'sync':      await pull(); toast('동기화했습니다'); break;

    case 'offline':   await toggleOffline(t.dataset.id); break;
    case 'delsong':   await deleteSong(t.dataset.id); break;
    case 'delsheet':  await deleteSheet(t.dataset.sheet); break;
    case 'save':      await saveSong(); break;

    case 'copy': {
      const song = state.songs.find(s => s.id === detailUI.songId);
      if (song) copyText(lyricsToText(song.lyrics, t.dataset.labels === '1'));
      break;
    }

    case 'open': {                                   // 악보 한 장 크게 보기
      const song = state.songs.find(s => s.id === detailUI.songId);
      const sh = song && song.sheets.find(x => x.id === t.dataset.sheet);
      if (sh) openViewer(song, [sh], `${song.title} · ${prettyKey(sh.musicKey)}`);
      break;
    }
    case 'viewall': {                                // 선택한 키 전체 보기
      const song = state.songs.find(s => s.id === detailUI.songId);
      if (song) openViewer(song, pagesFor(song, t.dataset.key),
        `${song.title} · ${prettyKey(t.dataset.key)} 전체`);
      break;
    }
    case 'closeviewer': closeViewer(); break;
    case 'zoom':        zoomViewer(); break;

    case 'addpart': {
      const type = t.dataset.type;
      const n = ed.sections.filter(s => s.type === type).length + 1;
      ed.sections.push({
        id: uid(), type,
        label: (type === 'Verse' || n > 1) ? `${type} ${n}` : type,
        text: '',
      });
      viewEditor(ed.id);
      break;
    }
    case 'delpart': {
      const id = t.dataset.sec;
      ed.sections = ed.sections.filter(s => s.id !== id);
      ed.arrangement = ed.arrangement.filter(x => x !== id);
      viewEditor(ed.id);
      break;
    }
    case 'toarr':   ed.arrangement.push(t.dataset.sec); viewEditor(ed.id); break;
    case 'delarr':  ed.arrangement.splice(Number(t.dataset.idx), 1); viewEditor(ed.id); break;
    case 'clararr': ed.arrangement = []; viewEditor(ed.id); break;

    case 'clearfiles':
      if (!confirm('기기에 저장한 악보 파일을 모두 지웁니다. 진행할까요?')) break;
      await IDB.clearFiles();
      state.offlineIds = new Set();
      toast('저장한 악보를 비웠습니다');
      viewSettings();
      break;

    case 'clearall':
      if (!confirm('기기에 저장된 모든 데이터를 지웁니다.\n서버 원본은 그대로입니다. 진행할까요?')) break;
      await IDB.clearAll();
      state.songs = []; state.offlineIds = new Set(); state.lastSync = null;
      toast('초기화했습니다');
      await pull();
      go('#/');
      break;
  }
});

window.addEventListener('hashchange', () => { window.scrollTo(0, 0); render(); });
window.addEventListener('online',  () => { state.online = true;  renderHeader(); pull({ quiet: true }); });
window.addEventListener('offline', () => { state.online = false; renderHeader(); });
document.addEventListener('keydown', e => { if (e.key === 'Escape') closeViewer(); });

/* ============================================================================
 * 데모 데이터 (config.js가 비었을 때만 쓰인다)
 * ==========================================================================*/
function demoSongs(){
  const mk = (title, composer, tags, parts) => {
    const sections = parts.map(([type, label, text]) => ({ id: uid(), type, label, text }));
    const lyrics = { sections, arrangement: [] };
    return normSong({
      id: 'demo-' + title, title, composer, tags,
      lyrics, sheets: [], created_at: null, updated_at: null,
    });
  };
  return [
    mk('주 은혜임을', '데모', ['경배', '느린곡'], [
      ['Verse', 'Verse 1', '내 삶의 작은 일에도\n주 은혜 넘치네'],
      ['Chorus', 'Chorus', '주 은혜임을\n주 은혜임을'],
    ]),
    mk('선한 능력으로', '데모', ['찬양'], [
      ['Verse', 'Verse 1', '선한 능력으로 우리를 감싸시니'],
      ['Bridge', 'Bridge', '두렵지 않네 두렵지 않네'],
    ]),
  ];
}

/* ============================================================================
 * 시작
 * ==========================================================================*/
async function boot(){
  try {
    state.offlineIds = await IDB.offlineIds();
    state.songs = byTitle(await IDB.allSongs());
    state.lastSync = await IDB.getMeta('lastSync');
  } catch (e) {
    console.warn('로컬 저장소를 열지 못했습니다', e);
  }

  if (DEMO && !state.songs.length) state.songs = demoSongs();
  state.booted = true;
  render();

  if (!DEMO){
    await pull();
    subscribeRealtime();
  }

  if ('serviceWorker' in navigator && location.protocol !== 'file:'){
    navigator.serviceWorker.register(new URL('sw.js', document.baseURI).href)
      .catch(err => console.warn('서비스워커 등록 실패', err));
  }
}

boot();
