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
