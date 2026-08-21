-- ============================================================================
-- 찬양 보관함 — 스키마 마이그레이션 V2
--
-- 사용법: Supabase 대시보드 → 왼쪽 메뉴 SQL Editor → New query →
--         이 파일 전체를 붙여넣고 오른쪽 아래 Run.
--
-- 안전장치
--  - DROP TABLE 없음. 기존 곡·악보 데이터를 지우지 않는다.
--  - 전부 IF NOT EXISTS / CREATE OR REPLACE. 여러 번 실행해도 결과가 같다(멱등).
--
-- ※ 이 스크립트는 "읽기·쓰기 전부 공개" 정책을 적용한다.
--   URL과 anon key를 아는 사람은 누구나 곡을 등록·수정·삭제할 수 있다.
--   나중에 팀원만 쓰기로 조이려면 아래 [5] 블록의 정책만 바꾸면 된다.
-- ============================================================================


-- [0] 확장 ---------------------------------------------------------------
-- pg_trgm: 한국어 부분일치 검색(LIKE '%가사%')을 인덱스로 가속한다.
-- 한국어는 Postgres 기본 형태소 사전이 없어 to_tsvector 방식이 잘 안 맞는다.
create extension if not exists pg_trgm;


-- [1] 테이블 (없을 때만 생성) ---------------------------------------------
create table if not exists public.songs (
  id         uuid primary key default gen_random_uuid(),
  title      text        not null default '',
  composer   text        not null default '',
  tags       text[]      not null default '{}',
  lyrics     jsonb       not null default '{"sections":[],"arrangement":[]}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.sheets (
  id         uuid primary key default gen_random_uuid(),
  song_id    uuid        not null references public.songs(id) on delete cascade,
  music_key  text        not null default 'C',
  file_path  text        not null default '',
  filename   text        not null default '',
  mime       text        not null default 'application/octet-stream',
  size       int         not null default 0,
  ord        int         not null default 1,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- 이미 테이블이 있던 경우 빠진 컬럼만 채운다.
alter table public.songs  add column if not exists composer   text        not null default '';
alter table public.songs  add column if not exists tags       text[]      not null default '{}';
alter table public.songs  add column if not exists lyrics     jsonb       not null default '{"sections":[],"arrangement":[]}'::jsonb;
alter table public.songs  add column if not exists created_at timestamptz not null default now();
alter table public.songs  add column if not exists updated_at timestamptz not null default now();
alter table public.sheets add column if not exists created_at timestamptz not null default now();
alter table public.sheets add column if not exists updated_at timestamptz not null default now();


-- [2] 곡 삭제 시 악보 row 자동 삭제 (ON DELETE CASCADE 보장) ----------------
-- 기존 앱 코드는 sheets를 손으로 지우고 있었다. FK에 CASCADE가 걸리면
-- 곡 하나만 지워도 악보 row가 따라 지워져 고아 데이터가 남지 않는다.
do $mig$
declare
  cname   text;
  deltype "char";
begin
  select conname, confdeltype into cname, deltype
    from pg_constraint
   where conrelid  = 'public.sheets'::regclass
     and contype   = 'f'
     and confrelid = 'public.songs'::regclass
   limit 1;

  if cname is null then
    alter table public.sheets
      add constraint sheets_song_id_fkey
      foreign key (song_id) references public.songs(id) on delete cascade;
  elsif deltype <> 'c' then                       -- 'c' = CASCADE
    execute format('alter table public.sheets drop constraint %I', cname);
    alter table public.sheets
      add constraint sheets_song_id_fkey
      foreign key (song_id) references public.songs(id) on delete cascade;
  end if;
end
$mig$;


-- [3] 검색용 컬럼 search_text --------------------------------------------
-- 제목 + 작곡가 + 태그 + 가사 전문을 소문자로 합쳐 한 컬럼에 넣어 둔다.
-- 클라이언트가 매번 가사를 이어붙일 필요가 없어지고, 서버 검색도 가능해진다.
alter table public.songs add column if not exists search_text text not null default '';

create or replace function public.songs_build_search_text(
  p_title text, p_composer text, p_tags text[], p_lyrics jsonb
) returns text
language sql immutable as $fn$
  select lower(
    coalesce(p_title, '')    || ' ' ||
    coalesce(p_composer, '') || ' ' ||
    coalesce(array_to_string(p_tags, ' '), '') || ' ' ||
    coalesce((
      select string_agg(sec->>'text', ' ')
        from jsonb_array_elements(coalesce(p_lyrics->'sections', '[]'::jsonb)) as sec
    ), '')
  );
$fn$;

-- search_text 자동 갱신 + updated_at 자동 갱신.
-- updated_at은 "사람이 실제로 바꾼 내용"이 있을 때만 올린다.
-- (아래 백필 UPDATE가 전 곡의 updated_at을 건드리지 않게 하려는 목적)
create or replace function public.songs_before_write() returns trigger
language plpgsql as $fn$
begin
  new.search_text := public.songs_build_search_text(
    new.title, new.composer, new.tags, new.lyrics
  );
  if tg_op = 'UPDATE'
     and (new.title, new.composer, new.tags, new.lyrics)
         is distinct from
         (old.title, old.composer, old.tags, old.lyrics)
  then
    new.updated_at := now();
  end if;
  return new;
end
$fn$;

drop trigger if exists trg_songs_before_write on public.songs;
create trigger trg_songs_before_write
  before insert or update on public.songs
  for each row execute function public.songs_before_write();

-- 기존 곡 백필 (updated_at은 그대로 보존됨)
update public.songs
   set search_text = public.songs_build_search_text(title, composer, tags, lyrics)
 where search_text = ''
    or search_text is distinct from public.songs_build_search_text(title, composer, tags, lyrics);

-- 트라이그램 인덱스. pg_trgm이 어느 스키마에 깔렸느냐에 따라 연산자 클래스 이름이
-- 달라질 수 있어 두 가지를 차례로 시도한다. 둘 다 안 되면 인덱스만 건너뛴다
-- (검색은 인덱스 없이도 동작한다. 곡이 아주 많아졌을 때만 느려진다).
do $mig$
begin
  begin
    execute 'create index if not exists idx_songs_search_trgm
               on public.songs using gin (search_text gin_trgm_ops)';
  exception when others then
    begin
      execute 'create index if not exists idx_songs_search_trgm
                 on public.songs using gin (search_text extensions.gin_trgm_ops)';
    exception when others then
      raise notice '트라이그램 인덱스를 건너뛰었습니다: %', sqlerrm;
    end;
  end;
end
$mig$;
create index if not exists idx_songs_title       on public.songs (title);
create index if not exists idx_songs_updated     on public.songs (updated_at desc);
create index if not exists idx_sheets_song       on public.sheets (song_id);
create index if not exists idx_sheets_key        on public.sheets (song_id, music_key, ord);


-- [4] sheets.updated_at 자동 갱신 -----------------------------------------
create or replace function public.sheets_before_write() returns trigger
language plpgsql as $fn$
begin
  new.updated_at := now();
  return new;
end
$fn$;

drop trigger if exists trg_sheets_before_write on public.sheets;
create trigger trg_sheets_before_write
  before insert or update on public.sheets
  for each row execute function public.sheets_before_write();


-- [5] 접근 권한 (RLS) — 읽기·쓰기 전부 공개 ---------------------------------
-- RLS를 끄는 것보다 "명시적으로 전부 허용"이 낫다. 나중에 조일 때
-- 이 블록의 using/with check 조건만 바꾸면 되기 때문이다.
--
--  예) 로그인한 사람만 쓰기로 바꾸려면:
--      using (auth.role() = 'authenticated') with check (auth.role() = 'authenticated')
alter table public.songs  enable row level security;
alter table public.sheets enable row level security;

drop policy if exists songs_public_read  on public.songs;
drop policy if exists songs_public_write on public.songs;
create policy songs_public_read  on public.songs for select using (true);
create policy songs_public_write on public.songs for all    using (true) with check (true);

drop policy if exists sheets_public_read  on public.sheets;
drop policy if exists sheets_public_write on public.sheets;
create policy sheets_public_read  on public.sheets for select using (true);
create policy sheets_public_write on public.sheets for all    using (true) with check (true);


-- [6] 실시간(Realtime) 방송 대상에 테이블 등록 -----------------------------
-- 이게 있어야 A가 곡을 올린 순간 B의 화면이 새로고침 없이 갱신된다.
do $mig$
begin
  if not exists (
    select 1 from pg_publication_tables
     where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'songs'
  ) then
    alter publication supabase_realtime add table public.songs;
  end if;

  if not exists (
    select 1 from pg_publication_tables
     where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'sheets'
  ) then
    alter publication supabase_realtime add table public.sheets;
  end if;
end
$mig$;


-- [7] 악보 파일 버킷 (Storage) --------------------------------------------
-- public = true 로 두면 서명 없이 바로 <img src>로 띄울 수 있어 웹이 훨씬 빠르다.
insert into storage.buckets (id, name, public)
values ('sheets', 'sheets', true)
on conflict (id) do update set public = true;

-- storage.objects 정책은 프로젝트 권한 설정에 따라 SQL로 못 바꾸는 경우가 있다.
-- 실패해도 나머지 마이그레이션이 통째로 되돌려지지 않도록 감싼다.
-- (실패하면 대시보드 Storage → sheets → Policies 에서 손으로 추가하면 된다)
do $mig$
begin
  drop policy if exists sheets_bucket_read  on storage.objects;
  drop policy if exists sheets_bucket_write on storage.objects;
  create policy sheets_bucket_read  on storage.objects
    for select using (bucket_id = 'sheets');
  create policy sheets_bucket_write on storage.objects
    for all    using (bucket_id = 'sheets') with check (bucket_id = 'sheets');
exception when others then
  raise notice 'Storage 정책은 대시보드에서 직접 설정해 주세요: %', sqlerrm;
end
$mig$;


-- [8] 확인용 조회 ----------------------------------------------------------
select
  (select count(*) from public.songs)  as 곡수,
  (select count(*) from public.sheets) as 악보수,
  (select count(*) from public.songs where search_text <> '') as 검색색인_완료곡수;
