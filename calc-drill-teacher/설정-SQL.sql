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
