# 찬양 보관함 — 웹 + 설치형 앱(PWA)

제목·가사로 찬양을 찾고, 키별 악보를 바로 꺼내 보는 보관함.
같은 주소 하나가 **홈페이지**이면서 **설치형 앱**이다.

- 온라인이면 다른 사람이 올린 곡이 새로고침 없이 바로 뜬다 (Supabase Realtime)
- 곡마다 `오프라인 저장`을 켜 두면 그 곡의 악보를 기기에 받아 두고,
  비행기 모드에서도 열린다
- 곡 목록과 가사는 전곡이 기기에 캐시되어, 오프라인에서도 검색이 된다

---

## 1. 준비 — Supabase (한 번만)

1. https://supabase.com 에 로그인 → 프로젝트 선택
2. 왼쪽 메뉴 **SQL Editor** → **New query**
3. `sql/schema_v2.sql` 파일 전체를 붙여넣고 오른쪽 아래 **Run**
4. 마지막에 `곡수 / 악보수 / 검색색인_완료곡수` 표가 나오면 성공

**아직 실행하지 않았다면 실시간 갱신이 동작하지 않는다.** 나머지 기능
(목록·검색·악보·가사·오프라인 저장)은 SQL 없이도 지금 그대로 돌아간다.

이 SQL이 하는 일

| 항목 | 내용 |
|---|---|
| 검색 | `search_text` 컬럼 + pg_trgm 인덱스. 한글 가사 부분일치 검색용 |
| 실시간 | `songs`·`sheets` 를 Realtime 방송 대상에 등록 |
| 정합성 | 곡을 지우면 악보 row도 함께 지워지도록 FK에 CASCADE |
| 권한 | RLS 켜고 **읽기·쓰기 전부 공개** 정책 |
| 저장소 | `sheets` 버킷을 public 으로 (웹에서 서명 없이 바로 표시) |

기존 데이터는 지우지 않는다. `DROP TABLE`이 없고, 여러 번 실행해도 결과가 같다.

> **권한 주의**
> 지금 정책은 URL과 anon key를 아는 사람이면 누구나 곡을 등록·수정·삭제할 수 있다.
> 나중에 조이려면 `sql/schema_v2.sql` 의 `[5]` 블록에서
> `using (true)` → `using (auth.role() = 'authenticated')` 로 바꾸고 다시 Run 하면 된다.
> (그 경우 앱에 로그인 화면을 붙이는 작업이 추가로 필요하다)

## 2. 접속 정보

`config.js` 에 이미 채워져 있다 (56곡 · 악보 109장 연결 확인 완료).
프로젝트를 바꿀 때만 Supabase 대시보드 → **Project Settings → API** 의 값으로 교체한다.

```js
window.PRAISE_CONFIG = {
  url: 'https://tdbihbyrnzjodrldclmi.supabase.co',
  anonKey: 'sb_publishable_...',
  bucket: 'sheets',
};
```

두 값이 비어 있으면 앱은 **데모 모드**로 뜬다. 샘플 곡 2개로 화면만 확인할 수 있다.

> anon key는 공개용 키라 저장소에 올라가도 된다. 다만 지금 권한 정책이
> '전부 공개'이므로, 이 주소를 아는 사람은 곡을 지울 수도 있다는 점만 기억해 둔다.

## 3. 로컬에서 확인

```bash
cd praise-archive-web
python3 -m http.server 8787
```
브라우저에서 http://127.0.0.1:8787 열기.

`file://` 로 직접 열면 서비스워커가 동작하지 않는다. 반드시 서버로 띄운다.

## 4. GitHub Pages 배포

```bash
cd praise-archive-web
git init
git add .
git commit -m "찬양 보관함 웹 v1"
git branch -M main
git remote add origin https://github.com/<계정>/praise-archive-web.git
git push -u origin main
```

GitHub 저장소 → **Settings → Pages** → Source 를 `Deploy from a branch`,
Branch 를 `main` / `(root)` 로 두고 저장. 1~2분 뒤
`https://<계정>.github.io/praise-archive-web/` 에서 열린다.

모든 경로가 상대경로라 하위 폴더 배포에서도 그대로 동작한다.

## 5. 앱으로 설치

- **아이폰** — 사파리로 접속 → 아래 공유 버튼 → `홈 화면에 추가`
- **안드로이드** — 크롬 → 오른쪽 위 `⋮` → `앱 설치`

설치하면 주소창 없이 앱처럼 열리고, 저장해 둔 곡은 비행기 모드에서도 보인다.

---

## 파일 고친 뒤에는

`sw.js` 첫 줄의 캐시 이름 숫자를 **반드시 올린다.**

```js
const CACHE = 'praise-archive-v1';   // → v2, v3 ...
```

올리지 않으면 이미 방문한 사람에게 예전 화면이 계속 뜬다.

## 구조

```
index.html                화면 뼈대
config.js                 Supabase 주소·키 (여기만 고치면 연결됨)
assets/app.js             전체 로직 — 동기화·실시간·검색·편집·뷰어
assets/db.js              IndexedDB 래퍼 (곡 캐시 / 악보 파일 / 오프라인 표시)
assets/app.css            스타일 (네이비 + 브라스 팔레트)
sw.js                     서비스워커 — 앱 껍데기 캐시
vendor/supabase.js        Supabase 클라이언트
vendor/pdf.min.js         PDF 렌더러 (PDF 악보를 처음 열 때만 내려받음)
sql/schema_v2.sql         Supabase 마이그레이션
icons/                    앱 아이콘
```

## 데이터 구조

```
songs   id, title, composer, tags[], lyrics(jsonb), search_text, created_at, updated_at
sheets  id, song_id, music_key, file_path, filename, mime, size, ord

lyrics = {
  sections:    [{ id, type, label, text }],   // 파트별 가사
  arrangement: [ sectionId, ... ]             // 부르는 순서. 중복 허용(1절-후렴-1절)
}
```

곡 하나에 키(C·G·E♭…)별로 악보를 여러 장 올린다. `ord` 가 쪽 번호다.

## 기존 Flutter 앱과의 관계

`ukiahptc/praise-archive` (Flutter) 와 **같은 Supabase 테이블을 쓴다.**
이 SQL을 돌려도 Flutter 앱은 그대로 동작한다.
다만 Flutter 쪽에는 아래 문제가 남아 있으니, 계속 쓸 계획이면 손봐야 한다.

- 실시간 구독이 없다 (앱을 껐다 켜야 남의 변경이 보임)
- 악보를 교체해도 다른 기기에서는 예전 파일이 계속 보인다
  (`sync_service.dart` 가 같은 경로 파일을 이미 받았으면 건너뛰기 때문)
- 동기화할 때마다 캐시 안 된 악보를 전부 자동 다운로드한다
