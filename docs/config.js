// ── 찬양 보관함 접속 설정 ────────────────────────────────────────────────
// Supabase 대시보드 → Project Settings → API 에서 두 값을 복사해 넣는다.
//   url     : Project URL              (예: https://abcdefgh.supabase.co)
//   anonKey : anon public / publishable key
//
// 두 값이 비어 있으면 앱은 '데모 모드'로 뜬다. 서버 없이 샘플 곡으로
// 화면과 조작을 확인할 수 있고, 저장은 되지 않는다.
window.PRAISE_CONFIG = {
  url: 'https://tdbihbyrnzjodrldclmi.supabase.co',
  anonKey: 'sb_publishable_uPW98AJxgCslOhdjbZqWrQ_OYXf8LIB',
  bucket: 'sheets',
};
