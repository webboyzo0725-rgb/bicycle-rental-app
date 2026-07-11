-- 기존 v3 데이터베이스에 v4 수정사항만 적용합니다.
-- 기존 데이터는 삭제하지 않습니다.
begin;

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

commit;
