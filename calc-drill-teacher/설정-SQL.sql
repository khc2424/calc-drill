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
create table students (
  id uuid default gen_random_uuid() primary key,
  name text not null,
  class_id uuid references classes(id) on delete set null,
  phone text,
  created_at timestamptz default now()
);

-- 실수 유형 태그
create table tags (
  id uuid default gen_random_uuid() primary key,
  name text not null,
  created_at timestamptz default now()
);

-- 학습지
create table worksheets (
  id uuid default gen_random_uuid() primary key,
  title text not null,
  created_at timestamptz default now()
);

-- 문항 (type: 'mc' 5지선다 / 'short' 주관식)
create table questions (
  id uuid default gen_random_uuid() primary key,
  worksheet_id uuid references worksheets(id) on delete cascade,
  question_no int not null,
  type text not null,
  correct_choice int,
  correct_value text,
  tolerance numeric default 0.001,
  tag_id uuid references tags(id) on delete set null
);

-- 학습지 배정 (학습지 하나를 특정 학생들에게 개별 배정)
create table worksheet_students (
  worksheet_id uuid references worksheets(id) on delete cascade,
  student_id uuid references students(id) on delete cascade,
  primary key (worksheet_id, student_id)
);

-- 시도 기록
create table attempts (
  id uuid default gen_random_uuid() primary key,
  student_id uuid references students(id) on delete cascade,
  worksheet_id uuid references worksheets(id) on delete cascade,
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
