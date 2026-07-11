-- 기존 v2.2 데이터베이스에 v3 수정사항만 적용하는 업데이트 파일
-- 기존 데이터는 삭제하지 않습니다.
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
