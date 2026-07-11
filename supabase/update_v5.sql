-- ============================================================
-- v5 업데이트: 반납 시점이 아니라 연체 전환 순간에 연체 횟수 증가
-- 기존 데이터는 삭제하지 않습니다.
-- ============================================================

begin;

-- 대여가 active -> overdue로 처음 바뀌는 순간에만 연체 횟수를 1회 증가시킵니다.
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
  select setting_value::integer
    into v_threshold
    from public.system_settings
   where setting_key = 'late_count_restriction_threshold';
  v_threshold := coalesce(v_threshold, 3);

  select id into v_admin_id
    from public.students
   where role = 'admin'
   order by created_at
   limit 1;

  -- status가 active인 행만 전환하므로 같은 대여 건은 중복 가산되지 않습니다.
  for v_rental in
    update public.rental_records
       set status = 'overdue',
           is_late = true,
           late_minutes = greatest(
             0,
             floor(extract(epoch from (now() - expected_return_at)) / 60)::integer
           )
     where status = 'active'
       and expected_return_at <= now()
     returning id, student_id
  loop
    v_count := v_count + 1;

    update public.students
       set late_count = late_count + 1
     where id = v_rental.student_id
     returning late_count into v_new_late_count;

    if v_new_late_count >= v_threshold then
      update public.students
         set account_status = 'restricted'
       where id = v_rental.student_id;

      if v_admin_id is not null
         and not exists (
           select 1
             from public.rental_restriction_records
            where student_id = v_rental.student_id
              and status = 'active'
         ) then
        insert into public.rental_restriction_records(
          student_id, restricted_by, reason
        ) values (
          v_rental.student_id,
          v_admin_id,
          format('연체 누적 %s회로 인한 자동 대여 제한', v_new_late_count)
        );
      end if;
    end if;
  end loop;

  -- 이미 연체 상태인 대여 건의 경과 시간만 갱신합니다.
  update public.rental_records
     set late_minutes = greatest(
       0,
       floor(extract(epoch from (now() - expected_return_at)) / 60)::integer
     )
   where status = 'overdue';

  return v_count;
end;
$$;

-- 반납 함수에서는 연체 횟수를 더 이상 증가시키지 않습니다.
-- Cron 실행이 잠시 지연된 경우를 대비해 반납 직전에 refresh를 한 번 호출합니다.
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
  v_late_count integer;
  v_has_unresolved boolean;
begin
  v_student_id := public.require_session(p_session_token);

  -- 연체 시각이 지났다면 여기서도 active -> overdue 전환 및 횟수 증가를 보장합니다.
  perform public.refresh_overdue_status();

  select * into v_station
    from public.stations
   where qr_code_value = trim(p_station_qr)
     and status = 'active';
  if v_station.id is null then
    raise exception '유효하지 않거나 비활성화된 대여소 QR입니다.' using errcode='P0001';
  end if;

  select * into v_rental
    from public.rental_records
   where student_id = v_student_id
     and status in ('active','overdue')
   order by rented_at desc
   limit 1
   for update;
  if v_rental.id is null then
    raise exception '현재 대여 중인 자전거가 없습니다.' using errcode='P0001';
  end if;

  if coalesce(p_has_fault, false)
     and trim(coalesce(p_fault_type, '')) = '' then
    raise exception '고장 유형을 입력해야 합니다.' using errcode='P0001';
  end if;

  v_is_late := v_rental.status = 'overdue' or v_now > v_rental.expected_return_at;
  v_late_minutes := case
    when v_is_late then greatest(
      0,
      floor(extract(epoch from (v_now - v_rental.expected_return_at)) / 60)::integer
    )
    else 0
  end;

  update public.rental_records
     set returned_at = v_now,
         status = 'returned',
         is_late = v_is_late,
         late_minutes = v_late_minutes
   where id = v_rental.id;

  insert into public.return_records(
    rental_id, station_id, returned_at, fault_reported
  ) values (
    v_rental.id, v_station.id, v_now, coalesce(p_has_fault, false)
  );

  if coalesce(p_has_fault, false) then
    insert into public.fault_records(
      bike_id, reporter_student_id, rental_id, fault_type, description
    ) values (
      v_rental.bike_id,
      v_student_id,
      v_rental.id,
      trim(p_fault_type),
      nullif(trim(p_fault_description), '')
    );
  end if;

  select exists(
    select 1
      from public.fault_records
     where bike_id = v_rental.bike_id
       and status in ('reported','checking','repairing')
  ) into v_has_unresolved;

  update public.bikes
     set status = case when v_has_unresolved then 'fault' else 'available' end,
         current_station_id = v_station.id
   where id = v_rental.bike_id;

  select late_count into v_late_count
    from public.students
   where id = v_student_id;

  return jsonb_build_object(
    'success', true,
    'message', '반납이 완료되었습니다.',
    'station_name', v_station.station_name,
    'is_late', v_is_late,
    'late_minutes', v_late_minutes,
    'late_count', v_late_count,
    'fault_reported', coalesce(p_has_fault, false)
  );
end;
$$;

grant execute on function public.return_bike_by_station_qr(text,text,boolean,text,text)
  to anon, authenticated;
revoke execute on function public.refresh_overdue_status() from anon, authenticated;

commit;

-- 연체 전환을 자동 확인하는 Supabase Cron 작업입니다.
-- 10초 시연용 대여도 빠르게 반영되도록 10초마다 실행합니다.
create extension if not exists pg_cron with schema pg_catalog;

-- 같은 이름의 기존 작업이 있다면 중복 생성을 방지합니다.
select cron.unschedule(jobid)
  from cron.job
 where jobname = 'bicycle-overdue-check';

select cron.schedule(
  'bicycle-overdue-check',
  '10 seconds',
  $$select public.refresh_overdue_status();$$
);
