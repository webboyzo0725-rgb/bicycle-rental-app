-- ============================================================
-- 자전거 대여 관리 시스템 - 최종 통합본 v2.2 (정비 기록 테이블 제거)
-- 기존 전체 DB + v2 수정사항 통합 / maintenance_records 미사용
-- 대상: 새 Supabase 프로젝트 또는 전체 초기화가 가능한 프로젝트
-- 주의: 기존 관련 테이블과 데이터가 삭제된 후 다시 생성됩니다.
-- 생성일: 2026-07-11
-- ============================================================

-- ============================================================
-- 자전거 대여 관리 시스템 - Supabase 전체 배포용 SQL
-- 대상: 새 Supabase 프로젝트 / Supabase Auth 미사용
-- 로그인: 학번(또는 관리자 번호) + 이름
-- 생성일: 2026-07-11
-- ============================================================

begin;

create extension if not exists pgcrypto;

-- ------------------------------------------------------------
-- 0. 기존 객체 초기화 (처음부터 다시 구축할 때 사용)
-- ------------------------------------------------------------
drop function if exists public.login_student(text, text) cascade;
drop function if exists public.logout_session(text) cascade;
drop function if exists public.my_profile(text) cascade;
drop function if exists public.list_available_bikes(text) cascade;
drop function if exists public.get_current_rental(text) cascade;
drop function if exists public.rent_bike(text, text, text, integer) cascade;
drop function if exists public.get_current_bike_password(text) cascade;
drop function if exists public.change_destination(text, text) cascade;
drop function if exists public.return_bike_by_station_qr(text, text, boolean, text, text) cascade;
drop function if exists public.report_bike_fault(text, text, text, text) cascade;
drop function if exists public.my_usage_history(text) cascade;
drop function if exists public.my_fault_history(text) cascade;
drop function if exists public.admin_dashboard(text) cascade;
drop function if exists public.admin_usage_history(text) cascade;
drop function if exists public.admin_list_students(text) cascade;
drop function if exists public.admin_list_bikes(text) cascade;
drop function if exists public.admin_set_bike_status(text, text, text, text) cascade;
drop function if exists public.admin_restrict_student(text, text, text) cascade;
drop function if exists public.admin_release_student_restriction(text, text, text) cascade;
drop function if exists public.admin_start_maintenance(text, text, text) cascade;
drop function if exists public.admin_finish_maintenance(text, bigint, text) cascade;
drop function if exists public.refresh_overdue_status() cascade;
drop function if exists public.current_session(text) cascade;
drop function if exists public.require_session(text) cascade;
drop function if exists public.require_admin(text) cascade;
drop function if exists public.set_updated_at() cascade;

drop table if exists public.admin_action_logs cascade;
drop table if exists public.app_sessions cascade;
drop table if exists public.rental_restriction_records cascade;
drop table if exists public.maintenance_records cascade;
drop table if exists public.fault_records cascade;
drop table if exists public.destination_change_records cascade;
drop table if exists public.return_records cascade;
drop table if exists public.rental_records cascade;
drop table if exists public.bikes cascade;
drop table if exists public.stations cascade;
drop table if exists public.students cascade;
drop table if exists public.system_settings cascade;

-- ------------------------------------------------------------
-- 1. 테이블
-- ------------------------------------------------------------
create table public.system_settings (
  setting_key text primary key,
  setting_value text not null,
  description text,
  updated_at timestamptz not null default now()
);

create table public.students (
  id uuid primary key default gen_random_uuid(),
  student_no text not null unique,
  name text not null,
  affiliation text,
  role text not null default 'user' check (role in ('user', 'admin')),
  account_status text not null default 'available'
    check (account_status in ('available', 'restricted', 'inactive', 'admin')),
  late_count integer not null default 0 check (late_count >= 0),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.stations (
  id uuid primary key default gen_random_uuid(),
  station_code text not null unique,
  station_name text not null,
  location_text text,
  qr_code_value text not null unique,
  status text not null default 'active' check (status in ('active', 'inactive')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.bikes (
  id uuid primary key default gen_random_uuid(),
  bike_no text not null unique,
  bike_password text not null,
  status text not null default 'available'
    check (status in ('available', 'rented', 'fault')),
  current_station_id uuid references public.stations(id),
  model_name text,
  purchase_date date,
  note text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.rental_records (
  id bigint generated always as identity primary key,
  student_id uuid not null references public.students(id),
  bike_id uuid not null references public.bikes(id),
  destination text not null,
  rented_at timestamptz not null default now(),
  expected_return_at timestamptz not null,
  returned_at timestamptz,
  status text not null default 'active'
    check (status in ('active', 'overdue', 'returned')),
  is_late boolean not null default false,
  late_minutes integer not null default 0 check (late_minutes >= 0),
  created_at timestamptz not null default now()
);

create unique index rental_one_active_per_student
  on public.rental_records(student_id)
  where status in ('active', 'overdue');

create unique index rental_one_active_per_bike
  on public.rental_records(bike_id)
  where status in ('active', 'overdue');

create table public.return_records (
  id bigint generated always as identity primary key,
  rental_id bigint not null unique references public.rental_records(id),
  station_id uuid not null references public.stations(id),
  returned_at timestamptz not null default now(),
  fault_reported boolean not null default false,
  created_at timestamptz not null default now()
);

create table public.destination_change_records (
  id bigint generated always as identity primary key,
  rental_id bigint not null references public.rental_records(id),
  old_destination text not null,
  new_destination text not null,
  changed_at timestamptz not null default now()
);

create table public.fault_records (
  id bigint generated always as identity primary key,
  bike_id uuid not null references public.bikes(id),
  reporter_student_id uuid references public.students(id),
  rental_id bigint references public.rental_records(id),
  fault_type text not null,
  description text,
  status text not null default 'reported'
    check (status in ('reported', 'checking', 'repairing', 'resolved', 'rejected')),
  reported_at timestamptz not null default now(),
  resolved_at timestamptz,
  resolved_by uuid references public.students(id)
);


-- 정비 이력은 별도 테이블로 관리하지 않습니다.
-- 고장 누적 기록은 fault_records에 보관하고, 수리 완료 시 관리자가 자전거 상태를 available로 변경합니다.

create table public.rental_restriction_records (
  id bigint generated always as identity primary key,
  student_id uuid not null references public.students(id),
  restricted_by uuid not null references public.students(id),
  released_by uuid references public.students(id),
  reason text not null,
  restricted_at timestamptz not null default now(),
  released_at timestamptz,
  release_reason text,
  status text not null default 'active' check (status in ('active', 'released'))
);

create unique index one_active_restriction_per_student
  on public.rental_restriction_records(student_id)
  where status = 'active';

create table public.app_sessions (
  id uuid primary key default gen_random_uuid(),
  session_token text not null unique default encode(gen_random_bytes(32), 'hex'),
  student_id uuid not null references public.students(id) on delete cascade,
  created_at timestamptz not null default now(),
  expires_at timestamptz not null default (now() + interval '24 hours'),
  last_used_at timestamptz not null default now(),
  revoked_at timestamptz
);

create index app_sessions_token_idx on public.app_sessions(session_token);

create table public.admin_action_logs (
  id bigint generated always as identity primary key,
  admin_id uuid not null references public.students(id),
  action_type text not null,
  target_type text,
  target_id text,
  description text,
  created_at timestamptz not null default now()
);

-- ------------------------------------------------------------
-- 2. 공통 트리거
-- ------------------------------------------------------------
create or replace function public.set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

create trigger students_set_updated_at before update on public.students
for each row execute function public.set_updated_at();
create trigger stations_set_updated_at before update on public.stations
for each row execute function public.set_updated_at();
create trigger bikes_set_updated_at before update on public.bikes
for each row execute function public.set_updated_at();
create trigger system_settings_set_updated_at before update on public.system_settings
for each row execute function public.set_updated_at();

-- ------------------------------------------------------------
-- 3. 세션 및 권한 확인 함수
-- ------------------------------------------------------------
create or replace function public.current_session(p_session_token text)
returns table (
  session_id uuid,
  student_id uuid,
  student_no text,
  name text,
  affiliation text,
  role text,
  account_status text,
  late_count integer,
  expires_at timestamptz
)
language sql
security definer
set search_path = public
as $$
  select s.id, st.id, st.student_no, st.name, st.affiliation,
         st.role, st.account_status, st.late_count, s.expires_at
    from public.app_sessions s
    join public.students st on st.id = s.student_id
   where s.session_token = p_session_token
     and s.revoked_at is null
     and s.expires_at > now()
   limit 1;
$$;

create or replace function public.require_session(p_session_token text)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_student_id uuid;
begin
  select student_id into v_student_id
    from public.current_session(p_session_token);

  if v_student_id is null then
    raise exception '유효하지 않거나 만료된 세션입니다.' using errcode = 'P0001';
  end if;

  update public.app_sessions
     set last_used_at = now()
   where session_token = p_session_token;

  return v_student_id;
end;
$$;

create or replace function public.require_admin(p_session_token text)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_admin_id uuid;
  v_role text;
begin
  select student_id, role into v_admin_id, v_role
    from public.current_session(p_session_token);

  if v_admin_id is null then
    raise exception '유효하지 않거나 만료된 세션입니다.' using errcode = 'P0001';
  end if;
  if v_role <> 'admin' then
    raise exception '관리자 권한이 필요합니다.' using errcode = 'P0001';
  end if;

  update public.app_sessions set last_used_at = now()
   where session_token = p_session_token;
  return v_admin_id;
end;
$$;

-- ------------------------------------------------------------
-- 4. 로그인 / 로그아웃 / 내 정보
-- ------------------------------------------------------------
create or replace function public.login_student(p_student_no text, p_name text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_student public.students%rowtype;
  v_token text;
  v_expires timestamptz;
begin
  select * into v_student
    from public.students
   where student_no = trim(p_student_no)
     and name = trim(p_name)
   limit 1;

  if v_student.id is null then
    raise exception '학번(관리자 번호) 또는 이름이 일치하지 않습니다.' using errcode = 'P0001';
  end if;
  if v_student.account_status = 'inactive' then
    raise exception '비활성화된 계정입니다.' using errcode = 'P0001';
  end if;

  update public.app_sessions
     set revoked_at = now()
   where student_id = v_student.id and revoked_at is null;

  insert into public.app_sessions(student_id)
  values (v_student.id)
  returning session_token, expires_at into v_token, v_expires;

  return jsonb_build_object(
    'success', true,
    'session_token', v_token,
    'expires_at', v_expires,
    'student_id', v_student.id,
    'student_no', v_student.student_no,
    'name', v_student.name,
    'affiliation', v_student.affiliation,
    'role', v_student.role,
    'account_status', v_student.account_status,
    'late_count', v_student.late_count
  );
end;
$$;

create or replace function public.logout_session(p_session_token text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
begin
  update public.app_sessions set revoked_at = now()
   where session_token = p_session_token and revoked_at is null;
  return jsonb_build_object('success', true, 'message', '로그아웃되었습니다.');
end;
$$;

create or replace function public.my_profile(p_session_token text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_id uuid;
  v_result jsonb;
begin
  v_id := public.require_session(p_session_token);
  select jsonb_build_object(
    'student_id', id, 'student_no', student_no, 'name', name,
    'affiliation', affiliation, 'role', role,
    'account_status', account_status, 'late_count', late_count
  ) into v_result from public.students where id = v_id;
  return v_result;
end;
$$;

-- ------------------------------------------------------------
-- 5. 사용자 기능
-- ------------------------------------------------------------
create or replace function public.refresh_overdue_status()
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_count integer;
begin
  update public.rental_records
     set status = 'overdue', is_late = true,
         late_minutes = greatest(0, floor(extract(epoch from (now() - expected_return_at)) / 60)::integer)
   where status = 'active' and expected_return_at < now();
  get diagnostics v_count = row_count;

  update public.rental_records
     set late_minutes = greatest(0, floor(extract(epoch from (now() - expected_return_at)) / 60)::integer)
   where status = 'overdue';
  return v_count;
end;
$$;

create or replace function public.list_available_bikes(p_session_token text)
returns table (
  bike_no text,
  status text,
  station_name text,
  location_text text,
  model_name text
)
language plpgsql
security definer
set search_path = public
as $$
begin
  perform public.require_session(p_session_token);
  return query
  select b.bike_no, b.status, s.station_name, s.location_text, b.model_name
    from public.bikes b
    left join public.stations s on s.id = b.current_station_id
   where b.status = 'available'
   order by b.bike_no;
end;
$$;

create or replace function public.get_current_rental(p_session_token text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_student_id uuid;
  v_result jsonb;
begin
  v_student_id := public.require_session(p_session_token);
  perform public.refresh_overdue_status();

  select jsonb_build_object(
    'rental_id', r.id,
    'bike_no', b.bike_no,
    'destination', r.destination,
    'rented_at', r.rented_at,
    'expected_return_at', r.expected_return_at,
    'status', r.status,
    'is_late', r.is_late,
    'late_minutes', r.late_minutes
  ) into v_result
  from public.rental_records r
  join public.bikes b on b.id = r.bike_id
  where r.student_id = v_student_id and r.status in ('active','overdue')
  order by r.rented_at desc limit 1;

  return coalesce(v_result, jsonb_build_object('active_rental', false));
end;
$$;

create or replace function public.rent_bike(
  p_session_token text,
  p_bike_no text,
  p_destination text,
  p_expected_minutes integer default 120
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_student_id uuid;
  v_student public.students%rowtype;
  v_bike public.bikes%rowtype;
  v_rental_id bigint;
begin
  v_student_id := public.require_session(p_session_token);
  perform public.refresh_overdue_status();

  if trim(coalesce(p_destination,'')) = '' then
    raise exception '목적지를 입력해야 합니다.' using errcode = 'P0001';
  end if;
  if p_expected_minutes is null or p_expected_minutes < 10 or p_expected_minutes > 1440 then
    raise exception '반납 예정 시간은 10분 이상 1440분 이하로 입력해야 합니다.' using errcode = 'P0001';
  end if;

  select * into v_student from public.students where id = v_student_id for update;
  if v_student.role <> 'user' then
    raise exception '일반 사용자 계정만 대여할 수 있습니다.' using errcode = 'P0001';
  end if;
  if v_student.account_status <> 'available' then
    raise exception '현재 계정은 자전거를 대여할 수 없습니다.' using errcode = 'P0001';
  end if;
  if exists(select 1 from public.rental_records where student_id=v_student_id and status in ('active','overdue')) then
    raise exception '이미 대여 중인 자전거가 있습니다.' using errcode = 'P0001';
  end if;

  select * into v_bike from public.bikes where bike_no = trim(p_bike_no) for update;
  if v_bike.id is null then
    raise exception '존재하지 않는 자전거 번호입니다.' using errcode = 'P0001';
  end if;
  if v_bike.status <> 'available' then
    raise exception '현재 대여할 수 없는 자전거입니다.' using errcode = 'P0001';
  end if;

  insert into public.rental_records(student_id,bike_id,destination,expected_return_at)
  values(v_student_id,v_bike.id,trim(p_destination),now() + make_interval(mins => p_expected_minutes))
  returning id into v_rental_id;

  update public.bikes set status='rented', current_station_id=null where id=v_bike.id;

  return jsonb_build_object(
    'success', true, 'message', '대여가 완료되었습니다.',
    'rental_id', v_rental_id, 'bike_no', v_bike.bike_no,
    'destination', trim(p_destination),
    'expected_return_at', now() + make_interval(mins => p_expected_minutes)
  );
end;
$$;

create or replace function public.get_current_bike_password(p_session_token text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_student_id uuid;
  v_result jsonb;
begin
  v_student_id := public.require_session(p_session_token);
  select jsonb_build_object('bike_no',b.bike_no,'bike_password',b.bike_password)
    into v_result
    from public.rental_records r join public.bikes b on b.id=r.bike_id
   where r.student_id=v_student_id and r.status in ('active','overdue')
   order by r.rented_at desc limit 1;
  if v_result is null then
    raise exception '현재 대여 중인 자전거가 없습니다.' using errcode = 'P0001';
  end if;
  return v_result;
end;
$$;

create or replace function public.change_destination(p_session_token text, p_new_destination text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_student_id uuid;
  v_rental public.rental_records%rowtype;
begin
  v_student_id := public.require_session(p_session_token);
  if trim(coalesce(p_new_destination,''))='' then
    raise exception '새 목적지를 입력해야 합니다.' using errcode='P0001';
  end if;

  select * into v_rental from public.rental_records
   where student_id=v_student_id and status in ('active','overdue')
   order by rented_at desc limit 1 for update;
  if v_rental.id is null then
    raise exception '현재 대여 중인 자전거가 없습니다.' using errcode='P0001';
  end if;

  insert into public.destination_change_records(rental_id,old_destination,new_destination)
  values(v_rental.id,v_rental.destination,trim(p_new_destination));
  update public.rental_records set destination=trim(p_new_destination) where id=v_rental.id;

  return jsonb_build_object('success',true,'message','목적지가 변경되었습니다.',
    'old_destination',v_rental.destination,'new_destination',trim(p_new_destination));
end;
$$;

create or replace function public.return_bike_by_station_qr(
  p_session_token text,
  p_station_qr text,
  p_has_fault boolean default false,
  p_fault_type text default null,
  p_fault_description text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_student_id uuid;
  v_rental public.rental_records%rowtype;
  v_station public.stations%rowtype;
  v_now timestamptz := now();
  v_is_late boolean;
  v_late_minutes integer;
  v_threshold integer;
  v_new_late_count integer;
begin
  v_student_id := public.require_session(p_session_token);

  select * into v_station from public.stations
   where qr_code_value=trim(p_station_qr) and status='active';
  if v_station.id is null then
    raise exception '유효하지 않거나 비활성화된 대여소 QR입니다.' using errcode='P0001';
  end if;

  select * into v_rental from public.rental_records
   where student_id=v_student_id and status in ('active','overdue')
   order by rented_at desc limit 1 for update;
  if v_rental.id is null then
    raise exception '현재 대여 중인 자전거가 없습니다.' using errcode='P0001';
  end if;

  v_is_late := v_now > v_rental.expected_return_at;
  v_late_minutes := case when v_is_late then
    greatest(1,floor(extract(epoch from(v_now-v_rental.expected_return_at))/60)::integer)
    else 0 end;

  update public.rental_records set returned_at=v_now,status='returned',
    is_late=v_is_late,late_minutes=v_late_minutes where id=v_rental.id;
  insert into public.return_records(rental_id,station_id,returned_at,fault_reported)
  values(v_rental.id,v_station.id,v_now,coalesce(p_has_fault,false));

  if coalesce(p_has_fault,false) then
    if trim(coalesce(p_fault_type,''))='' then
      raise exception '고장 신고 시 고장 유형을 입력해야 합니다.' using errcode='P0001';
    end if;
    insert into public.fault_records(bike_id,reporter_student_id,rental_id,fault_type,description)
    values(v_rental.bike_id,v_student_id,v_rental.id,trim(p_fault_type),nullif(trim(p_fault_description),''));
    update public.bikes set status='fault',current_station_id=v_station.id where id=v_rental.bike_id;
  else
    update public.bikes set status='available',current_station_id=v_station.id where id=v_rental.bike_id;
  end if;

  if v_is_late then
    update public.students set late_count=late_count+1 where id=v_student_id
    returning late_count into v_new_late_count;

    select setting_value::integer into v_threshold from public.system_settings
     where setting_key='late_count_restriction_threshold';
    v_threshold := coalesce(v_threshold,3);

    if v_new_late_count >= v_threshold then
      update public.students set account_status='restricted' where id=v_student_id;
      if not exists(select 1 from public.rental_restriction_records where student_id=v_student_id and status='active') then
        insert into public.rental_restriction_records(student_id,restricted_by,reason)
        values(v_student_id,
          (select id from public.students where role='admin' order by created_at limit 1),
          format('연체 누적 %s회로 인한 자동 대여 제한',v_new_late_count));
      end if;
    end if;
  else
    select late_count into v_new_late_count from public.students where id=v_student_id;
  end if;

  return jsonb_build_object(
    'success',true,'message','반납이 완료되었습니다.',
    'station_name',v_station.station_name,
    'is_late',v_is_late,'late_minutes',v_late_minutes,
    'late_count',v_new_late_count,'fault_reported',coalesce(p_has_fault,false)
  );
end;
$$;

create or replace function public.report_bike_fault(
  p_session_token text,
  p_bike_no text,
  p_fault_type text,
  p_description text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_student_id uuid;
  v_bike_id uuid;
  v_rental_id bigint;
  v_fault_id bigint;
begin
  v_student_id := public.require_session(p_session_token);
  select id into v_bike_id from public.bikes where bike_no=trim(p_bike_no);
  if v_bike_id is null then raise exception '존재하지 않는 자전거입니다.' using errcode='P0001'; end if;
  if trim(coalesce(p_fault_type,''))='' then raise exception '고장 유형을 입력해야 합니다.' using errcode='P0001'; end if;

  select id into v_rental_id from public.rental_records
   where student_id=v_student_id and bike_id=v_bike_id and status in ('active','overdue')
   order by rented_at desc limit 1;

  insert into public.fault_records(bike_id,reporter_student_id,rental_id,fault_type,description)
  values(v_bike_id,v_student_id,v_rental_id,trim(p_fault_type),nullif(trim(p_description),''))
  returning id into v_fault_id;

  if v_rental_id is null then update public.bikes set status='fault' where id=v_bike_id and status='available'; end if;
  return jsonb_build_object('success',true,'message','고장 신고가 접수되었습니다.','fault_id',v_fault_id);
end;
$$;

create or replace function public.my_usage_history(p_session_token text)
returns table(
  rental_id bigint,bike_no text,destination text,rented_at timestamptz,
  expected_return_at timestamptz,returned_at timestamptz,status text,
  is_late boolean,late_minutes integer,return_station text
)
language plpgsql
security definer
set search_path = public
as $$
declare v_student_id uuid;
begin
  v_student_id:=public.require_session(p_session_token);
  return query select r.id,b.bike_no,r.destination,r.rented_at,r.expected_return_at,
    r.returned_at,r.status,r.is_late,r.late_minutes,s.station_name
  from public.rental_records r join public.bikes b on b.id=r.bike_id
  left join public.return_records rr on rr.rental_id=r.id
  left join public.stations s on s.id=rr.station_id
  where r.student_id=v_student_id order by r.rented_at desc;
end;
$$;

create or replace function public.my_fault_history(p_session_token text)
returns table(fault_id bigint,bike_no text,fault_type text,description text,status text,reported_at timestamptz,resolved_at timestamptz)
language plpgsql security definer set search_path=public
as $$
declare v_student_id uuid;
begin
  v_student_id:=public.require_session(p_session_token);
  return query select f.id,b.bike_no,f.fault_type,f.description,f.status,f.reported_at,f.resolved_at
  from public.fault_records f join public.bikes b on b.id=f.bike_id
  where f.reporter_student_id=v_student_id order by f.reported_at desc;
end;$$;

-- ------------------------------------------------------------
-- 6. 관리자 기능
-- ------------------------------------------------------------
create or replace function public.admin_dashboard(p_session_token text)
returns jsonb language plpgsql security definer set search_path=public
as $$
declare v_admin uuid; v_result jsonb;
begin
  v_admin:=public.require_admin(p_session_token); perform public.refresh_overdue_status();
  select jsonb_build_object(
    'total_students',(select count(*) from public.students where role='user'),
    'available_bikes',(select count(*) from public.bikes where status='available'),
    'rented_bikes',(select count(*) from public.bikes where status='rented'),
    'fault_bikes',(select count(*) from public.bikes where status='fault'),
    'active_rentals',(select count(*) from public.rental_records where status='active'),
    'overdue_rentals',(select count(*) from public.rental_records where status='overdue'),
    'restricted_students',(select count(*) from public.students where account_status='restricted'),
    'unresolved_faults',(select count(*) from public.fault_records where status in ('reported','checking','repairing'))
  ) into v_result; return v_result;
end;$$;

create or replace function public.admin_usage_history(p_session_token text)
returns table(rental_id bigint,student_no text,student_name text,affiliation text,bike_no text,destination text,rented_at timestamptz,expected_return_at timestamptz,returned_at timestamptz,status text,is_late boolean,late_minutes integer,return_station text)
language plpgsql security definer set search_path=public
as $$
begin
  perform public.require_admin(p_session_token); perform public.refresh_overdue_status();
  return query select r.id,st.student_no,st.name,st.affiliation,b.bike_no,r.destination,r.rented_at,
  r.expected_return_at,r.returned_at,r.status,r.is_late,r.late_minutes,rs.station_name
  from public.rental_records r join public.students st on st.id=r.student_id join public.bikes b on b.id=r.bike_id
  left join public.return_records rr on rr.rental_id=r.id left join public.stations rs on rs.id=rr.station_id
  order by r.rented_at desc;
end;$$;

create or replace function public.admin_list_students(p_session_token text)
returns table(student_no text,name text,affiliation text,role text,account_status text,late_count integer,created_at timestamptz)
language plpgsql security definer set search_path=public
as $$ begin perform public.require_admin(p_session_token);
return query select s.student_no,s.name,s.affiliation,s.role,s.account_status,s.late_count,s.created_at from public.students s order by s.student_no; end; $$;

create or replace function public.admin_list_bikes(p_session_token text)
returns table(bike_no text,status text,bike_password text,station_name text,model_name text,note text)
language plpgsql security definer set search_path=public
as $$ begin perform public.require_admin(p_session_token);
return query select b.bike_no,b.status,b.bike_password,s.station_name,b.model_name,b.note from public.bikes b left join public.stations s on s.id=b.current_station_id order by b.bike_no; end; $$;

create or replace function public.admin_set_bike_status(p_session_token text,p_bike_no text,p_status text,p_note text default null)
returns jsonb language plpgsql security definer set search_path=public
as $$ declare v_admin uuid; v_bike uuid;
begin
  v_admin:=public.require_admin(p_session_token);
  if p_status not in ('available','rented','fault') then raise exception '올바르지 않은 자전거 상태입니다.' using errcode='P0001'; end if;
  select id into v_bike from public.bikes where bike_no=trim(p_bike_no);
  if v_bike is null then raise exception '존재하지 않는 자전거입니다.' using errcode='P0001'; end if;
  if exists(select 1 from public.rental_records where bike_id=v_bike and status in ('active','overdue')) and p_status <> 'rented' then
    raise exception '대여 중인 자전거 상태는 직접 변경할 수 없습니다.' using errcode='P0001';
  end if;
  update public.bikes set status=p_status,note=coalesce(p_note,note) where id=v_bike;
  insert into public.admin_action_logs(admin_id,action_type,target_type,target_id,description)
  values(v_admin,'SET_BIKE_STATUS','bike',p_bike_no,format('상태를 %s로 변경: %s',p_status,coalesce(p_note,'')));
  return jsonb_build_object('success',true,'message','자전거 상태가 변경되었습니다.');
end;$$;

create or replace function public.admin_restrict_student(p_session_token text,p_student_no text,p_reason text)
returns jsonb language plpgsql security definer set search_path=public
as $$ declare v_admin uuid; v_student uuid;
begin
  v_admin:=public.require_admin(p_session_token);
  select id into v_student from public.students where student_no=trim(p_student_no) and role='user';
  if v_student is null then raise exception '존재하지 않는 일반 사용자입니다.' using errcode='P0001'; end if;
  if trim(coalesce(p_reason,''))='' then raise exception '제한 사유를 입력해야 합니다.' using errcode='P0001'; end if;
  if exists(select 1 from public.rental_records where student_id=v_student and status in ('active','overdue')) then raise exception '현재 대여 중인 사용자는 제한할 수 없습니다.' using errcode='P0001'; end if;
  update public.students set account_status='restricted' where id=v_student;
  if not exists(select 1 from public.rental_restriction_records where student_id=v_student and status='active') then
    insert into public.rental_restriction_records(student_id,restricted_by,reason) values(v_student,v_admin,trim(p_reason));
  end if;
  insert into public.admin_action_logs(admin_id,action_type,target_type,target_id,description) values(v_admin,'RESTRICT_STUDENT','student',p_student_no,p_reason);
  return jsonb_build_object('success',true,'message','대여 제한이 적용되었습니다.');
end;$$;

create or replace function public.admin_release_student_restriction(p_session_token text,p_student_no text,p_release_reason text)
returns jsonb language plpgsql security definer set search_path=public
as $$ declare v_admin uuid; v_student uuid;
begin
  v_admin:=public.require_admin(p_session_token);
  select id into v_student from public.students where student_no=trim(p_student_no) and role='user';
  if v_student is null then raise exception '존재하지 않는 일반 사용자입니다.' using errcode='P0001'; end if;
  update public.rental_restriction_records set status='released',released_by=v_admin,released_at=now(),release_reason=nullif(trim(p_release_reason),'')
  where student_id=v_student and status='active';
  update public.students set account_status='available',late_count=0 where id=v_student;
  insert into public.admin_action_logs(admin_id,action_type,target_type,target_id,description) values(v_admin,'RELEASE_RESTRICTION','student',p_student_no,p_release_reason);
  return jsonb_build_object('success',true,'message','대여 제한이 해제되었고 연체 횟수가 0으로 초기화되었습니다.');
end;$$;



-- ------------------------------------------------------------
-- 7. RLS 및 실행 권한
-- 직접 테이블 접근은 차단하고 RPC 함수만 사용
-- ------------------------------------------------------------
alter table public.system_settings enable row level security;
alter table public.students enable row level security;
alter table public.stations enable row level security;
alter table public.bikes enable row level security;
alter table public.rental_records enable row level security;
alter table public.return_records enable row level security;
alter table public.destination_change_records enable row level security;
alter table public.fault_records enable row level security;
alter table public.rental_restriction_records enable row level security;
alter table public.app_sessions enable row level security;
alter table public.admin_action_logs enable row level security;

revoke all on all tables in schema public from anon, authenticated;
revoke all on all sequences in schema public from anon, authenticated;
revoke execute on all functions in schema public from public, anon, authenticated;
grant usage on schema public to anon, authenticated;

-- 앱에서 호출할 RPC 함수만 공개
grant execute on function public.login_student(text,text) to anon, authenticated;
grant execute on function public.logout_session(text) to anon, authenticated;
grant execute on function public.my_profile(text) to anon, authenticated;
grant execute on function public.list_available_bikes(text) to anon, authenticated;
grant execute on function public.get_current_rental(text) to anon, authenticated;
grant execute on function public.rent_bike(text,text,text,integer) to anon, authenticated;
grant execute on function public.get_current_bike_password(text) to anon, authenticated;
grant execute on function public.change_destination(text,text) to anon, authenticated;
grant execute on function public.return_bike_by_station_qr(text,text,boolean,text,text) to anon, authenticated;
grant execute on function public.report_bike_fault(text,text,text,text) to anon, authenticated;
grant execute on function public.my_usage_history(text) to anon, authenticated;
grant execute on function public.my_fault_history(text) to anon, authenticated;
grant execute on function public.admin_dashboard(text) to anon, authenticated;
grant execute on function public.admin_usage_history(text) to anon, authenticated;
grant execute on function public.admin_list_students(text) to anon, authenticated;
grant execute on function public.admin_list_bikes(text) to anon, authenticated;
grant execute on function public.admin_set_bike_status(text,text,text,text) to anon, authenticated;
grant execute on function public.admin_restrict_student(text,text,text) to anon, authenticated;
grant execute on function public.admin_release_student_restriction(text,text,text) to anon, authenticated;

-- 내부 보조 함수는 외부 실행 차단
revoke execute on function public.current_session(text) from anon, authenticated;
revoke execute on function public.require_session(text) from anon, authenticated;
revoke execute on function public.require_admin(text) from anon, authenticated;
revoke execute on function public.refresh_overdue_status() from anon, authenticated;

-- ------------------------------------------------------------
-- 8. 기본 설정 및 테스트 데이터
-- 실제 운영 전 테스트 데이터는 수정 또는 삭제 가능
-- ------------------------------------------------------------
insert into public.system_settings(setting_key,setting_value,description) values
('late_count_restriction_threshold','3','연체가 이 횟수 이상 누적되면 자동 대여 제한');

insert into public.students(student_no,name,affiliation,role,account_status) values
('20240001','홍길동','1중대','user','available'),
('20240002','김철수','2중대','user','available'),
('admin001','관리자','관리부','admin','admin');

insert into public.stations(station_code,station_name,location_text,qr_code_value,status) values
('MAIN','본관 앞 대여소','본관 앞','STATION_MAIN_001','active'),
('DORM','생활관 앞 대여소','생활관 앞','STATION_DORM_001','active');

insert into public.bikes(bike_no,bike_password,status,current_station_id,model_name) values
('B001','1234','available',(select id from public.stations where station_code='MAIN'),'기본형 자전거'),
('B002','5678','available',(select id from public.stations where station_code='MAIN'),'기본형 자전거'),
('B003','9012','available',(select id from public.stations where station_code='DORM'),'기본형 자전거');

commit;

-- ============================================================
-- 실행 후 간단 테스트
-- ============================================================
-- 1) 로그인
-- select public.login_student('20240001','홍길동');
--
-- 2) 위 결과의 session_token을 복사하여 대여
-- select public.rent_bike('세션토큰','B001','도서관',120);
--
-- 3) 현재 대여 정보
-- select public.get_current_rental('세션토큰');
--
-- 4) 비밀번호 확인
-- select public.get_current_bike_password('세션토큰');
--
-- 5) 목적지 변경
-- select public.change_destination('세션토큰','생활관');
--
-- 6) QR 반납
-- select public.return_bike_by_station_qr('세션토큰','STATION_MAIN_001',false,null,null);
--
-- 7) 관리자 로그인
-- select public.login_student('admin001','관리자');
-- ============================================================


-- ============================================================
-- v2 최종 기능 반영
-- 대여시간 1~8시간 제한, 고장 상태 처리, 관리자 자전거 관리,
-- 전체 고장내역, 비밀번호/반납 관련 함수 수정
-- ============================================================

begin;
-- 자전거 대여 시스템 v2 업데이트
-- 기존 database.sql을 이미 실행한 프로젝트에서는 이 파일만 SQL Editor에서 실행하세요.

create or replace function public.rent_bike(
  p_session_token text,
  p_bike_no text,
  p_destination text,
  p_expected_minutes integer default 120
)
returns jsonb language plpgsql security definer set search_path=public
as $$
declare v_student_id uuid; v_student public.students%rowtype; v_bike public.bikes%rowtype; v_rental_id bigint;
begin
  v_student_id:=public.require_session(p_session_token); perform public.refresh_overdue_status();
  if trim(coalesce(p_destination,''))='' then raise exception '목적지를 입력해야 합니다.' using errcode='P0001'; end if;
  if p_expected_minutes is null or p_expected_minutes < 60 or p_expected_minutes > 480 or mod(p_expected_minutes,60)<>0 then
    raise exception '이용 예정 시간은 1시간부터 8시간까지 1시간 단위로 선택해야 합니다.' using errcode='P0001';
  end if;
  select * into v_student from public.students where id=v_student_id for update;
  if v_student.role<>'user' then raise exception '일반 사용자 계정만 대여할 수 있습니다.' using errcode='P0001'; end if;
  if v_student.account_status<>'available' then raise exception '현재 계정은 자전거를 대여할 수 없습니다.' using errcode='P0001'; end if;
  if exists(select 1 from public.rental_records where student_id=v_student_id and status in ('active','overdue')) then raise exception '이미 대여 중인 자전거가 있습니다.' using errcode='P0001'; end if;
  select * into v_bike from public.bikes where bike_no=trim(p_bike_no) for update;
  if v_bike.id is null then raise exception '존재하지 않는 자전거 번호입니다.' using errcode='P0001'; end if;
  if v_bike.status<>'available' then raise exception '현재 대여할 수 없는 자전거입니다.' using errcode='P0001'; end if;
  insert into public.rental_records(student_id,bike_id,destination,expected_return_at)
  values(v_student_id,v_bike.id,trim(p_destination),now()+make_interval(mins=>p_expected_minutes)) returning id into v_rental_id;
  update public.bikes set status='rented',current_station_id=null where id=v_bike.id;
  return jsonb_build_object('success',true,'message','대여가 완료되었습니다.','rental_id',v_rental_id,'bike_no',v_bike.bike_no,'bike_password',v_bike.bike_password,'expected_return_at',now()+make_interval(mins=>p_expected_minutes));
end;$$;

create or replace function public.report_bike_fault(
  p_session_token text,p_bike_no text,p_fault_type text,p_description text default null
)
returns jsonb language plpgsql security definer set search_path=public
as $$
declare v_student_id uuid; v_bike_id uuid; v_rental_id bigint; v_fault_id bigint;
begin
  v_student_id:=public.require_session(p_session_token);
  if trim(coalesce(p_fault_type,''))='' then raise exception '고장 유형을 입력해야 합니다.' using errcode='P0001'; end if;
  select id into v_bike_id from public.bikes where bike_no=trim(p_bike_no);
  if v_bike_id is null then raise exception '존재하지 않는 자전거입니다.' using errcode='P0001'; end if;
  select id into v_rental_id from public.rental_records where student_id=v_student_id and bike_id=v_bike_id and status in ('active','overdue') order by rented_at desc limit 1;
  insert into public.fault_records(bike_id,reporter_student_id,rental_id,fault_type,description)
  values(v_bike_id,v_student_id,v_rental_id,trim(p_fault_type),nullif(trim(p_description),'')) returning id into v_fault_id;
  update public.bikes set status='fault' where id=v_bike_id;
  return jsonb_build_object('success',true,'message','고장 신고가 접수되었고 자전거 상태가 고장으로 변경되었습니다.','fault_id',v_fault_id);
end;$$;

create or replace function public.return_bike_by_station_qr(
  p_session_token text,p_station_qr text,p_has_fault boolean default false,p_fault_type text default null,p_fault_description text default null
)
returns jsonb language plpgsql security definer set search_path=public
as $$
declare v_student_id uuid;v_rental public.rental_records%rowtype;v_station public.stations%rowtype;v_now timestamptz:=now();v_is_late boolean;v_late_minutes integer;v_threshold integer;v_new_late_count integer;v_has_unresolved boolean;
begin
  v_student_id:=public.require_session(p_session_token);
  select * into v_station from public.stations where qr_code_value=trim(p_station_qr) and status='active';
  if v_station.id is null then raise exception '유효하지 않거나 비활성화된 대여소 QR입니다.' using errcode='P0001'; end if;
  select * into v_rental from public.rental_records where student_id=v_student_id and status in ('active','overdue') order by rented_at desc limit 1 for update;
  if v_rental.id is null then raise exception '현재 대여 중인 자전거가 없습니다.' using errcode='P0001'; end if;
  if coalesce(p_has_fault,false) and trim(coalesce(p_fault_type,''))='' then raise exception '고장 유형을 입력해야 합니다.' using errcode='P0001'; end if;
  v_is_late:=v_now>v_rental.expected_return_at;
  v_late_minutes:=case when v_is_late then greatest(1,floor(extract(epoch from(v_now-v_rental.expected_return_at))/60)::integer) else 0 end;
  update public.rental_records set returned_at=v_now,status='returned',is_late=v_is_late,late_minutes=v_late_minutes where id=v_rental.id;
  insert into public.return_records(rental_id,station_id,returned_at,fault_reported) values(v_rental.id,v_station.id,v_now,coalesce(p_has_fault,false));
  if coalesce(p_has_fault,false) then
    insert into public.fault_records(bike_id,reporter_student_id,rental_id,fault_type,description) values(v_rental.bike_id,v_student_id,v_rental.id,trim(p_fault_type),nullif(trim(p_fault_description),''));
  end if;
  select exists(select 1 from public.fault_records where bike_id=v_rental.bike_id and status in ('reported','checking','repairing')) into v_has_unresolved;
  update public.bikes set status=case when v_has_unresolved then 'fault' else 'available' end,current_station_id=v_station.id where id=v_rental.bike_id;
  if v_is_late then
    update public.students set late_count=late_count+1 where id=v_student_id returning late_count into v_new_late_count;
    select setting_value::integer into v_threshold from public.system_settings where setting_key='late_count_restriction_threshold';v_threshold:=coalesce(v_threshold,3);
    if v_new_late_count>=v_threshold then update public.students set account_status='restricted' where id=v_student_id; end if;
  else select late_count into v_new_late_count from public.students where id=v_student_id; end if;
  return jsonb_build_object('success',true,'message','반납이 완료되었습니다.','station_name',v_station.station_name,'is_late',v_is_late,'late_minutes',v_late_minutes,'late_count',v_new_late_count,'fault_reported',coalesce(p_has_fault,false));
end;$$;

drop function if exists public.admin_set_bike_status(text,text,text,text);
create or replace function public.admin_set_bike_status(
  p_session_token text,p_bike_no text,p_status text,p_note text default null,p_fault_type text default null,p_fault_description text default null
)
returns jsonb language plpgsql security definer set search_path=public
as $$
declare v_admin uuid;v_bike uuid;v_fault_id bigint;
begin
  v_admin:=public.require_admin(p_session_token);
  if p_status not in ('available','fault') then raise exception '관리자는 대여 가능 또는 고장 상태만 선택할 수 있습니다.' using errcode='P0001'; end if;
  select id into v_bike from public.bikes where bike_no=trim(p_bike_no);
  if v_bike is null then raise exception '존재하지 않는 자전거입니다.' using errcode='P0001'; end if;
  if exists(select 1 from public.rental_records where bike_id=v_bike and status in ('active','overdue')) then raise exception '대여 중인 자전거는 상태를 수정할 수 없습니다.' using errcode='P0001'; end if;
  if p_status='fault' then
    if trim(coalesce(p_fault_type,''))='' or trim(coalesce(p_fault_description,''))='' then raise exception '고장 유형과 상세 설명을 입력해야 합니다.' using errcode='P0001'; end if;
    insert into public.fault_records(bike_id,reporter_student_id,fault_type,description) values(v_bike,v_admin,trim(p_fault_type),trim(p_fault_description)) returning id into v_fault_id;
  else
    update public.fault_records set status='resolved',resolved_at=now(),resolved_by=v_admin where bike_id=v_bike and status in ('reported','checking','repairing');
  end if;
  update public.bikes set status=p_status,note=nullif(trim(p_note),'') where id=v_bike;
  insert into public.admin_action_logs(admin_id,action_type,target_type,target_id,description) values(v_admin,'SET_BIKE_STATUS','bike',p_bike_no,format('상태를 %s로 변경',p_status));
  return jsonb_build_object('success',true,'message','자전거 상태가 변경되었습니다.','fault_id',v_fault_id);
end;$$;

drop function if exists public.admin_list_bikes(text);

create or replace function public.admin_list_bikes(p_session_token text)
returns table(bike_no text,status text,bike_password text,station_name text,model_name text,note text,active_rental boolean,fault_type text,fault_description text,fault_reported_at timestamptz)
language plpgsql security definer set search_path=public
as $$
begin
  perform public.require_admin(p_session_token);
  return query
  select b.bike_no,b.status,b.bike_password,s.station_name,b.model_name,b.note,
    exists(select 1 from public.rental_records r where r.bike_id=b.id and r.status in ('active','overdue')),
    lf.fault_type,lf.description,lf.reported_at
  from public.bikes b left join public.stations s on s.id=b.current_station_id
  left join lateral(select f.fault_type,f.description,f.reported_at from public.fault_records f where f.bike_id=b.id and f.status in ('reported','checking','repairing') order by f.reported_at desc limit 1) lf on true
  order by case when b.status='fault' then 0 else 1 end,b.bike_no;
end;$$;

create or replace function public.admin_fault_history(p_session_token text)
returns table(fault_id bigint,bike_no text,reporter_student_no text,reporter_name text,fault_type text,description text,status text,reported_at timestamptz,resolved_at timestamptz)
language plpgsql security definer set search_path=public
as $$
begin
  perform public.require_admin(p_session_token);
  return query select f.id,b.bike_no,s.student_no,s.name,f.fault_type,f.description,f.status,f.reported_at,f.resolved_at
  from public.fault_records f join public.bikes b on b.id=f.bike_id left join public.students s on s.id=f.reporter_student_id order by f.reported_at desc;
end;$$;

grant execute on function public.rent_bike(text,text,text,integer) to anon,authenticated;
grant execute on function public.report_bike_fault(text,text,text,text) to anon,authenticated;
grant execute on function public.return_bike_by_station_qr(text,text,boolean,text,text) to anon,authenticated;
grant execute on function public.admin_set_bike_status(text,text,text,text,text,text) to anon,authenticated;
grant execute on function public.admin_list_bikes(text) to anon,authenticated;
grant execute on function public.admin_fault_history(text) to anon,authenticated;

commit;

-- ============================================================
-- 최종 통합본 v2.2 실행 완료 (maintenance_records 제거)
-- ============================================================

-- ============================================================
-- v3 최종 기능 반영
-- 고장 신고는 QR 반납 시에만 허용, 관리자 현황 통계 조정
-- ============================================================
begin;

create or replace function public.admin_dashboard(p_session_token text)
returns jsonb language plpgsql security definer set search_path=public
as $$
declare v_admin uuid; v_result jsonb;
begin
  v_admin:=public.require_admin(p_session_token);
  perform public.refresh_overdue_status();
  select jsonb_build_object(
    'total_students',(select count(*) from public.students where role='user'),
    'total_bikes',(select count(*) from public.bikes),
    'available_bikes',(select count(*) from public.bikes where status='available'),
    'rented_bikes',(select count(*) from public.bikes where status='rented'),
    'fault_bikes',(select count(*) from public.bikes where status='fault'),
    'active_rentals',(select count(*) from public.rental_records where status='active'),
    'overdue_rentals',(select count(*) from public.rental_records where status='overdue'),
    'restricted_students',(select count(*) from public.students where account_status='restricted')
  ) into v_result;
  return v_result;
end;$$;

create or replace function public.report_bike_fault(
  p_session_token text,p_bike_no text,p_fault_type text,p_description text default null
)
returns jsonb language plpgsql security definer set search_path=public
as $$
begin
  perform public.require_session(p_session_token);
  raise exception '고장 신고는 자전거 반납 과정에서만 할 수 있습니다.' using errcode='P0001';
end;$$;

commit;


-- ============================================================
-- v4: 비밀번호 조회 안정화 및 10초 시연 대여 옵션
-- ============================================================

create or replace function public.get_current_bike_password_v2(p_session_token text)
returns text
language plpgsql
security definer
set search_path=public
as $$
declare
  v_student_id uuid;
  v_password text;
begin
  v_student_id:=public.require_session(p_session_token);
  select b.bike_password into v_password
  from public.rental_records r
  join public.bikes b on b.id=r.bike_id
  where r.student_id=v_student_id and r.status in ('active','overdue')
  order by r.rented_at desc limit 1;
  if v_password is null then
    raise exception '현재 대여 중인 자전거가 없습니다.' using errcode='P0001';
  end if;
  return v_password;
end;$$;

create or replace function public.rent_bike(
  p_session_token text,
  p_bike_no text,
  p_destination text,
  p_expected_minutes integer default 120
)
returns jsonb language plpgsql security definer set search_path=public
as $$
declare
  v_student_id uuid; v_student public.students%rowtype; v_bike public.bikes%rowtype; v_rental_id bigint; v_expected_at timestamptz;
begin
  v_student_id:=public.require_session(p_session_token); perform public.refresh_overdue_status();
  if trim(coalesce(p_destination,''))='' then raise exception '목적지를 입력해야 합니다.' using errcode='P0001'; end if;
  if p_expected_minutes is null or not (p_expected_minutes=0 or (p_expected_minutes between 60 and 480 and mod(p_expected_minutes,60)=0)) then
    raise exception '이용 예정 시간은 시연용 10초 또는 1시간부터 8시간까지 1시간 단위로 선택해야 합니다.' using errcode='P0001';
  end if;
  select * into v_student from public.students where id=v_student_id for update;
  if v_student.role<>'user' then raise exception '일반 사용자 계정만 대여할 수 있습니다.' using errcode='P0001'; end if;
  if v_student.account_status<>'available' then raise exception '현재 계정은 자전거를 대여할 수 없습니다.' using errcode='P0001'; end if;
  if exists(select 1 from public.rental_records where student_id=v_student_id and status in ('active','overdue')) then raise exception '이미 대여 중인 자전거가 있습니다.' using errcode='P0001'; end if;
  select * into v_bike from public.bikes where bike_no=trim(p_bike_no) for update;
  if v_bike.id is null then raise exception '존재하지 않는 자전거 번호입니다.' using errcode='P0001'; end if;
  if v_bike.status<>'available' then raise exception '현재 대여할 수 없는 자전거입니다.' using errcode='P0001'; end if;
  v_expected_at:=case when p_expected_minutes=0 then now()+interval '10 seconds' else now()+make_interval(mins=>p_expected_minutes) end;
  insert into public.rental_records(student_id,bike_id,destination,expected_return_at)
  values(v_student_id,v_bike.id,trim(p_destination),v_expected_at) returning id into v_rental_id;
  update public.bikes set status='rented',current_station_id=null where id=v_bike.id;
  return jsonb_build_object('success',true,'message','대여가 완료되었습니다.','rental_id',v_rental_id,'bike_no',v_bike.bike_no,'bike_password',v_bike.bike_password,'expected_return_at',v_expected_at);
end;$$;

grant execute on function public.get_current_bike_password_v2(text) to anon,authenticated;
grant execute on function public.rent_bike(text,text,text,integer) to anon,authenticated;

-- ============================================================
-- v5: 연체 전환 순간 연체 횟수 증가 + 10초 Cron 자동 확인
-- ============================================================

create or replace function public.refresh_overdue_status()
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_rental record;
  v_count integer := 0;
  v_new_late_count integer;
  v_threshold integer;
  v_admin_id uuid;
begin
  select setting_value::integer into v_threshold
    from public.system_settings
   where setting_key='late_count_restriction_threshold';
  v_threshold := coalesce(v_threshold,3);

  select id into v_admin_id from public.students
   where role='admin' order by created_at limit 1;

  for v_rental in
    update public.rental_records
       set status='overdue', is_late=true,
           late_minutes=greatest(0,floor(extract(epoch from(now()-expected_return_at))/60)::integer)
     where status='active' and expected_return_at<=now()
     returning id,student_id
  loop
    v_count:=v_count+1;
    update public.students set late_count=late_count+1
     where id=v_rental.student_id returning late_count into v_new_late_count;

    if v_new_late_count>=v_threshold then
      update public.students set account_status='restricted' where id=v_rental.student_id;
      if v_admin_id is not null and not exists(
        select 1 from public.rental_restriction_records
         where student_id=v_rental.student_id and status='active'
      ) then
        insert into public.rental_restriction_records(student_id,restricted_by,reason)
        values(v_rental.student_id,v_admin_id,format('연체 누적 %s회로 인한 자동 대여 제한',v_new_late_count));
      end if;
    end if;
  end loop;

  update public.rental_records
     set late_minutes=greatest(0,floor(extract(epoch from(now()-expected_return_at))/60)::integer)
   where status='overdue';
  return v_count;
end;$$;

create or replace function public.return_bike_by_station_qr(
  p_session_token text,p_station_qr text,p_has_fault boolean default false,
  p_fault_type text default null,p_fault_description text default null
)
returns jsonb language plpgsql security definer set search_path=public
as $$
declare
  v_student_id uuid;v_rental public.rental_records%rowtype;v_station public.stations%rowtype;
  v_now timestamptz:=now();v_is_late boolean;v_late_minutes integer;v_late_count integer;v_has_unresolved boolean;
begin
  v_student_id:=public.require_session(p_session_token);
  perform public.refresh_overdue_status();
  select * into v_station from public.stations where qr_code_value=trim(p_station_qr) and status='active';
  if v_station.id is null then raise exception '유효하지 않거나 비활성화된 대여소 QR입니다.' using errcode='P0001'; end if;
  select * into v_rental from public.rental_records where student_id=v_student_id and status in('active','overdue') order by rented_at desc limit 1 for update;
  if v_rental.id is null then raise exception '현재 대여 중인 자전거가 없습니다.' using errcode='P0001'; end if;
  if coalesce(p_has_fault,false) and trim(coalesce(p_fault_type,''))='' then raise exception '고장 유형을 입력해야 합니다.' using errcode='P0001'; end if;
  v_is_late:=v_rental.status='overdue' or v_now>v_rental.expected_return_at;
  v_late_minutes:=case when v_is_late then greatest(0,floor(extract(epoch from(v_now-v_rental.expected_return_at))/60)::integer) else 0 end;
  update public.rental_records set returned_at=v_now,status='returned',is_late=v_is_late,late_minutes=v_late_minutes where id=v_rental.id;
  insert into public.return_records(rental_id,station_id,returned_at,fault_reported) values(v_rental.id,v_station.id,v_now,coalesce(p_has_fault,false));
  if coalesce(p_has_fault,false) then
    insert into public.fault_records(bike_id,reporter_student_id,rental_id,fault_type,description)
    values(v_rental.bike_id,v_student_id,v_rental.id,trim(p_fault_type),nullif(trim(p_fault_description),''));
  end if;
  select exists(select 1 from public.fault_records where bike_id=v_rental.bike_id and status in('reported','checking','repairing')) into v_has_unresolved;
  update public.bikes set status=case when v_has_unresolved then 'fault' else 'available' end,current_station_id=v_station.id where id=v_rental.bike_id;
  select late_count into v_late_count from public.students where id=v_student_id;
  return jsonb_build_object('success',true,'message','반납이 완료되었습니다.','station_name',v_station.station_name,'is_late',v_is_late,'late_minutes',v_late_minutes,'late_count',v_late_count,'fault_reported',coalesce(p_has_fault,false));
end;$$;

grant execute on function public.return_bike_by_station_qr(text,text,boolean,text,text) to anon,authenticated;
revoke execute on function public.refresh_overdue_status() from anon,authenticated;

create extension if not exists pg_cron with schema pg_catalog;
select cron.unschedule(jobid) from cron.job where jobname='bicycle-overdue-check';
select cron.schedule('bicycle-overdue-check','10 seconds',$$select public.refresh_overdue_status();$$);
-- v5.1: 연체 자동 처리 보강
-- 기존 데이터는 삭제하지 않습니다.

begin;

-- 앱이 현재 대여 상태를 조회할 때도 반드시 연체 전환을 확인합니다.
create or replace function public.get_current_rental(p_session_token text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_student_id uuid;
  v_result jsonb;
begin
  v_student_id := public.require_session(p_session_token);
  perform public.refresh_overdue_status();

  select jsonb_build_object(
    'rental_id', r.id,
    'bike_no', b.bike_no,
    'destination', r.destination,
    'rented_at', r.rented_at,
    'expected_return_at', r.expected_return_at,
    'status', r.status,
    'is_late', r.is_late,
    'late_minutes', r.late_minutes
  ) into v_result
  from public.rental_records r
  join public.bikes b on b.id = r.bike_id
  where r.student_id = v_student_id
    and r.status in ('active','overdue')
  order by r.rented_at desc
  limit 1;

  return coalesce(v_result, jsonb_build_object('active_rental', false));
end;
$$;

grant execute on function public.get_current_rental(text) to anon, authenticated;

commit;

-- Cron 작업을 다시 확실히 등록합니다.
create extension if not exists pg_cron with schema pg_catalog;
select cron.unschedule(jobid) from cron.job where jobname = 'bicycle-overdue-check';
select cron.schedule(
  'bicycle-overdue-check',
  '10 seconds',
  $$select public.refresh_overdue_status();$$
);

-- 확인용 결과
select jobid, jobname, schedule, active
from cron.job
where jobname = 'bicycle-overdue-check';
