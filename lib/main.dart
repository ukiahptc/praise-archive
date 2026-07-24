import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'config/supabase_config.dart';
import 'services/song_provider.dart';
import 'theme/app_theme.dart';
import 'screens/home_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 찬양팀 공유 클라우드 DB(Supabase) 연결.
  // 네트워크가 없어도 앱은 정상적으로 뜨며(로컬 캐시로 동작), 이후 온라인이 되면
  // SongProvider가 자동으로 동기화를 시도한다.
  try {
    await Supabase.initialize(
      url: SupabaseConfig.url,
      publishableKey: SupabaseConfig.anonKey,
    );
  } catch (_) {
    // 초기화 실패(네트워크 없음 등)해도 앱 실행은 계속 진행 — 오프라인 캐시로 동작
  }

  runApp(const PraiseArchiveApp());
}

class PraiseArchiveApp extends StatelessWidget {
  const PraiseArchiveApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => SongProvider()..init(),
      child: MaterialApp(
        title: '찬양 보관함',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light(),
        home: const HomeScreen(),
      ),
    );
  }
}
