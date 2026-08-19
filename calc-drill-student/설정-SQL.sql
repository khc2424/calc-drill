-- =========================================
--  계산 반복 학습 시스템 — Supabase 설정 SQL
--  새로 만든 Supabase 프로젝트의 SQL Editor에서 전체 실행하세요.
-- =========================================

create extension if not exists "pgcrypto";

-- 반
create table classes (
  id uuid default gen_random_uuid() primary key,
  name text not null,
  created_at timestamptz default now()
);

-- 학생 (한 학생 = 반 1개)
-- phone: 로그인 아이디로 사용 / password: 로그인 비밀번호(초기값 전화번호 뒤 4자리)
-- must_change_password: 최초 로그인 시 비밀번호 변경을 강제할지 여부
-- (student_no 컬럼은 더 이상 사용하지 않습니다. 남아있어도 무해하니 그대로 두어도 됩니다.)
create table students (
  id uuid default gen_random_uuid() primary key,
  name text not null,
  class_id uuid references classes(id) on delete set null,
  phone text,
  student_no text,
  password text,
  must_change_password boolean not null default true,
  created_at timestamptz default now()
);

-- 실수 유형 태그
create table tags (
  id uuid default gen_random_uuid() primary key,
  name text not null,
  created_at timestamptz default now()
);

-- 학습지
-- chunk_size: 몇 문항씩 끊어서 풀게 할지 (null/0 = 전체 한번에)
create table worksheets (
  id uuid default gen_random_uuid() primary key,
  title text not null,
  chunk_size int,
  created_at timestamptz default now()
);

-- 문항 (type: 'mc' 5지선다 / 'short' 주관식)
-- answer_prefix/answer_suffix: 정답 앞뒤에 고정으로 붙는 텍스트 (예: "제" + [3] + "사분면", [150] + "m")
--   학생은 빈칸에 핵심 값만 입력하면 되고, 채점은 correct_value(핵심 값)만 비교합니다.
create table questions (
  id uuid default gen_random_uuid() primary key,
  worksheet_id uuid references worksheets(id) on delete cascade,
  question_no int not null,
  type text not null,
  correct_choice int,
  correct_value text,
  answer_prefix text,
  answer_suffix text,
  tolerance numeric default 0,
  tag_id uuid references tags(id) on delete set null
);

-- 학습지 배정 (학습지 하나를 특정 학생들에게 개별 배정)
create table worksheet_students (
  worksheet_id uuid references worksheets(id) on delete cascade,
  student_id uuid references students(id) on delete cascade,
  primary key (worksheet_id, student_id)
);

-- 시도 기록
-- chunk_index: 몇 번째 묶음(구간)에 대한 시도인지 (0부터 시작, 묶음 미사용 학습지는 항상 0)
create table attempts (
  id uuid default gen_random_uuid() primary key,
  student_id uuid references students(id) on delete cascade,
  worksheet_id uuid references worksheets(id) on delete cascade,
  chunk_index int not null default 0,
  attempt_no int not null,
  wrong_count int not null default 0,
  passed boolean not null default false,
  created_at timestamptz default now()
);

-- 시도별 문항 채점 결과 (학생에겐 노출 안 함, 선생님 유형 통계용)
create table attempt_answers (
  id uuid default gen_random_uuid() primary key,
  attempt_id uuid references attempts(id) on delete cascade,
  question_id uuid references questions(id) on delete cascade,
  submitted_value text,
  is_correct boolean not null
);

alter table classes enable row level security;
alter table students enable row level security;
alter table tags enable row level security;
alter table worksheets enable row level security;
alter table questions enable row level security;
alter table worksheet_students enable row level security;
alter table attempts enable row level security;
alter table attempt_answers enable row level security;

create policy "allow_all_classes" on classes for all using (true) with check (true);
create policy "allow_all_students" on students for all using (true) with check (true);
create policy "allow_all_tags" on tags for all using (true) with check (true);
create policy "allow_all_worksheets" on worksheets for all using (true) with check (true);
create policy "allow_all_questions" on questions for all using (true) with check (true);
create policy "allow_all_worksheet_students" on worksheet_students for all using (true) with check (true);
create policy "allow_all_attempts" on attempts for all using (true) with check (true);
create policy "allow_all_attempt_answers" on attempt_answers for all using (true) with check (true);

-- 기본 실수 유형 태그 (필요하면 선생님 페이지에서 더 추가 가능)
insert into tags (name) values ('연산실수'), ('문제 해석실수'), ('그래프 해석실수');

-- =========================================
--  기존 DB에 이미 설치했다면 이 부분만 실행해도 됩니다
--  (테이블/데이터는 그대로 두고 새 컬럼만 추가)
-- =========================================
alter table questions add column if not exists answer_prefix text;
alter table questions add column if not exists answer_suffix text;
alter table questions alter column tolerance set default 0;

alter table students add column if not exists student_no text;
alter table students add column if not exists password text;
alter table students add column if not exists must_change_password boolean not null default true;

-- 기존 학생들에게 학번(1,2,3...) 자동 부여
with numbered as (
  select id, row_number() over (order by created_at) as rn
  from students where student_no is null
)
update students s set student_no = numbered.rn::text
from numbered where s.id = numbered.id;

-- 기존 학생들 초기 비밀번호를 전화번호 뒤 4자리로 채우기 (전화번호 없으면 0000)
update students
set password = right(regexp_replace(coalesce(phone, ''), '[^0-9]', '', 'g'), 4)
where password is null and length(regexp_replace(coalesce(phone, ''), '[^0-9]', '', 'g')) >= 4;

update students set password = '0000' where password is null or password = '';

-- 학습지 개별 배정용 테이블이 없다면 새로 생성 (예전 worksheet_classes를 대체)
create table if not exists worksheet_students (
  worksheet_id uuid references worksheets(id) on delete cascade,
  student_id uuid references students(id) on delete cascade,
  primary key (worksheet_id, student_id)
);
alter table worksheet_students enable row level security;

do $$
begin
  if not exists (
    select 1 from pg_policies
    where tablename = 'worksheet_students' and policyname = 'allow_all_worksheet_students'
  ) then
    create policy "allow_all_worksheet_students" on worksheet_students for all using (true) with check (true);
  end if;
end $$;

-- (참고) 예전에 쓰던 worksheet_classes 테이블이 남아있다면 이제 사용하지 않으니 지워도 됩니다.
-- drop table if exists worksheet_classes;

-- 학습지를 몇 문항씩 끊어서 풀게 할지 설정하는 기능
alter table worksheets add column if not exists chunk_size int;
alter table attempts add column if not exists chunk_index int not null default 0;

-- =========================================
--  문제은행 (Question Bank)
-- =========================================
create extension if not exists pg_trgm;

-- 단원 체계: 학년 - 과목 - 대단원 - 중단원 (고정 4단계 트리)
create table if not exists curriculum_units (
  id uuid default gen_random_uuid() primary key,
  grade text not null,
  subject text not null,
  major_unit text not null,
  minor_unit text not null,
  created_at timestamptz default now(),
  unique (grade, subject, major_unit, minor_unit)
);

-- 유형 태그: 특정 중단원에 속한 자유 태그 (드롭다운에서 선택, 새로 추가 가능)
create table if not exists problem_types (
  id uuid default gen_random_uuid() primary key,
  curriculum_unit_id uuid references curriculum_units(id) on delete cascade,
  name text not null,
  created_at timestamptz default now()
);

-- 문제은행 문제
-- status: '검토대기' | '승인' | '반려'
-- difficulty: '상' | '중' | '하'
-- origin_problem_id: null이면 원본, 값이 있으면 그 원본의 쌍둥이(변형) 문제
-- deleted_at: 휴지통 보관 시각 (30일 후 자동 영구삭제)
create table if not exists bank_problems (
  id uuid default gen_random_uuid() primary key,
  curriculum_unit_id uuid references curriculum_units(id) on delete set null,
  problem_type_id uuid references problem_types(id) on delete set null,
  content_text text not null,
  image_url text,
  type text not null default 'short',
  correct_choice int,
  correct_value text,
  answer_prefix text,
  answer_suffix text,
  tolerance numeric default 0,
  difficulty text not null default '중',
  status text not null default '검토대기',
  origin_problem_id uuid references bank_problems(id) on delete set null,
  created_at timestamptz default now(),
  deleted_at timestamptz
);
create index if not exists idx_bank_problems_origin on bank_problems(origin_problem_id);
create index if not exists idx_bank_problems_unit on bank_problems(curriculum_unit_id);
create index if not exists idx_bank_problems_content_trgm on bank_problems using gin (content_text gin_trgm_ops);

-- 학습지 문항이 문제은행 어느 문제에서 왔는지 (노출 이력 추적용)
alter table questions add column if not exists bank_problem_id uuid references bank_problems(id) on delete set null;

alter table curriculum_units enable row level security;
alter table problem_types enable row level security;
alter table bank_problems enable row level security;

do $$
begin
  if not exists (select 1 from pg_policies where tablename = 'curriculum_units' and policyname = 'allow_all_curriculum_units') then
    create policy "allow_all_curriculum_units" on curriculum_units for all using (true) with check (true);
  end if;
  if not exists (select 1 from pg_policies where tablename = 'problem_types' and policyname = 'allow_all_problem_types') then
    create policy "allow_all_problem_types" on problem_types for all using (true) with check (true);
  end if;
  if not exists (select 1 from pg_policies where tablename = 'bank_problems' and policyname = 'allow_all_bank_problems') then
    create policy "allow_all_bank_problems" on bank_problems for all using (true) with check (true);
  end if;
end $$;

-- 그래프/그림 이미지를 저장할 Storage 버킷 (공개 읽기, 단순화 우선)
insert into storage.buckets (id, name, public)
values ('bank_images', 'bank_images', true)
on conflict (id) do nothing;

do $$
begin
  if not exists (select 1 from pg_policies where tablename = 'objects' and policyname = 'bank_images_public_read') then
    create policy "bank_images_public_read" on storage.objects for select using (bucket_id = 'bank_images');
  end if;
  if not exists (select 1 from pg_policies where tablename = 'objects' and policyname = 'bank_images_public_insert') then
    create policy "bank_images_public_insert" on storage.objects for insert with check (bucket_id = 'bank_images');
  end if;
  if not exists (select 1 from pg_policies where tablename = 'objects' and policyname = 'bank_images_public_delete') then
    create policy "bank_images_public_delete" on storage.objects for delete using (bucket_id = 'bank_images');
  end if;
end $$;

-- 중복 문제 자동 감지: 새 문제를 저장하기 전에 비슷한 문제가 이미 있는지 찾아줍니다 (pg_trgm 유사도 기반)
create or replace function find_similar_bank_problems(target_text text, unit_id uuid default null, threshold real default 0.4)
returns table(id uuid, content_text text, similarity real)
language sql stable
as $$
  select id, content_text, similarity(content_text, target_text) as similarity
  from bank_problems
  where deleted_at is null
    and (unit_id is null or curriculum_unit_id = unit_id)
    and similarity(content_text, target_text) > threshold
  order by similarity desc
  limit 5;
$$;
grant execute on function find_similar_bank_problems(text, uuid, real) to anon, authenticated;

-- 정답률 기반 난이도 재조정 제안: 학습지에 쓰인 문제은행 문항들의 실제 오답률을 보고
-- 현재 표시된 난이도와 크게 어긋나는 문제를 찾아줍니다. (제안만 하고, 실제 반영은 선생님이 문제은행에서 직접)
create or replace function bank_difficulty_suggestions()
returns table(bank_problem_id uuid, content_text text, difficulty text, wrong_rate numeric, attempt_count bigint)
language sql stable
as $$
  select bp.id, bp.content_text, bp.difficulty,
    round(100.0 * sum(case when not aa.is_correct then 1 else 0 end) / count(*), 1) as wrong_rate,
    count(*) as attempt_count
  from bank_problems bp
  join questions q on q.bank_problem_id = bp.id
  join attempt_answers aa on aa.question_id = q.id
  where bp.deleted_at is null
  group by bp.id, bp.content_text, bp.difficulty
  having count(*) >= 5
    and (
      (bp.difficulty = '하' and (100.0 * sum(case when not aa.is_correct then 1 else 0 end) / count(*)) >= 60)
      or (bp.difficulty = '상' and (100.0 * sum(case when not aa.is_correct then 1 else 0 end) / count(*)) <= 15)
      or (bp.difficulty = '중' and (
        (100.0 * sum(case when not aa.is_correct then 1 else 0 end) / count(*)) >= 70
        or (100.0 * sum(case when not aa.is_correct then 1 else 0 end) / count(*)) <= 10
      ))
    )
  order by wrong_rate desc;
$$;
grant execute on function bank_difficulty_suggestions() to anon, authenticated;
