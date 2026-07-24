/// Supabase 연결 설정 — 찬양팀 공유 클라우드 DB.
/// 이 값들은 anon/publishable key로, 클라이언트에 노출되어도 안전하도록
/// 설계된 값입니다 (RLS 정책으로 접근이 제어됩니다).
class SupabaseConfig {
  static const String url = 'https://tdbihbyrnzjodrldclmi.supabase.co';
  static const String anonKey =
      'sb_publishable_uPW98AJxgCslOhdjbZqWrQ_OYXf8LIB';
  static const String sheetsBucket = 'sheets';
}
