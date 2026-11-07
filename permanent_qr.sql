-- HODOR: Permanent reusable QR code for daily check-in and check-out
-- Run once in Supabase Dashboard > SQL Editor > New query.

alter table public.qr_sessions
  add column if not exists is_permanent boolean not null default false;

create index if not exists qr_sessions_permanent_idx
  on public.qr_sessions (created_at desc)
  where is_permanent = true;

create or replace function public.record_check_in(
 p_lat double precision default null, p_lng double precision default null,
 p_method text default 'button', p_qr_token text default null
) returns public.attendance
language plpgsql security definer set search_path=public
as $$
declare
 v_profile public.profiles;
 v_settings public.app_settings;
 v_row public.attendance;
 v_date date := (now() at time zone 'Africa/Cairo')::date;
 v_shift time;
 v_status text := 'present';
 v_qr public.qr_sessions;
 v_dist double precision;
begin
 select * into v_settings from public.app_settings where id=1;
 select * into v_profile from public.profiles where id=auth.uid() and active=true;
 if not found then raise exception 'الحساب غير نشط أو غير مسجل'; end if;
 if p_method not in ('button','gps','qr') then raise exception 'طريقة تسجيل غير صالحة'; end if;
 if p_method in ('gps','qr') then
   if v_settings.latitude is null or v_settings.longitude is null or p_lat is null or p_lng is null then
     raise exception 'موقع المكتبة أو موقع جهازك غير محدد';
   end if;
   v_dist := 6371000*2*asin(sqrt(power(sin(radians(p_lat-v_settings.latitude)/2),2)+cos(radians(v_settings.latitude))*cos(radians(p_lat))*power(sin(radians(p_lng-v_settings.longitude)/2),2)));
   if v_dist > v_settings.radius_m then raise exception 'أنت خارج نطاق موقع العمل'; end if;
 end if;
 if p_method='qr' then
   select * into v_qr from public.qr_sessions
   where token=p_qr_token
     and (is_permanent=true or (expires_at>now() and used_at is null))
   for update;
   if not found then raise exception 'رمز QR غير صالح أو انتهت صلاحيته'; end if;
   if not v_qr.is_permanent then
     update public.qr_sessions set used_at=now() where id=v_qr.id;
   end if;
 end if;
 v_shift := v_profile.shift_start;
 if (now() at time zone 'Africa/Cairo')::time > v_shift + make_interval(mins=>coalesce(v_settings.grace_minutes,10)) then
   v_status := 'late';
 end if;
 insert into public.attendance(employee_id,work_date,check_in,status,method,check_in_lat,check_in_lng)
 values(auth.uid(),v_date,now(),v_status,p_method,p_lat,p_lng)
 on conflict(employee_id,work_date) do nothing returning * into v_row;
 if v_row.id is null then raise exception 'تم تسجيل الحضور بالفعل اليوم'; end if;
 return v_row;
end $$;

create or replace function public.record_check_out(
 p_lat double precision default null, p_lng double precision default null,
 p_method text default 'button', p_qr_token text default null
) returns public.attendance
language plpgsql security definer set search_path=public
as $$
declare
 v_settings public.app_settings;
 v_row public.attendance;
 v_date date := (now() at time zone 'Africa/Cairo')::date;
 v_qr public.qr_sessions;
 v_dist double precision;
begin
 if p_method in ('gps','qr') then
   select * into v_settings from public.app_settings where id=1;
   if v_settings.latitude is null or v_settings.longitude is null or p_lat is null or p_lng is null then
     raise exception 'موقع المكتبة أو موقع جهازك غير محدد';
   end if;
   v_dist := 6371000*2*asin(sqrt(power(sin(radians(p_lat-v_settings.latitude)/2),2)+cos(radians(v_settings.latitude))*cos(radians(p_lat))*power(sin(radians(p_lng-v_settings.longitude)/2),2)));
   if v_dist > v_settings.radius_m then raise exception 'أنت خارج نطاق موقع العمل'; end if;
 end if;
 if p_method='qr' then
   select * into v_qr from public.qr_sessions
   where token=p_qr_token
     and (is_permanent=true or (expires_at>now() and used_at is null))
   for update;
   if not found then raise exception 'رمز QR غير صالح أو انتهت صلاحيته'; end if;
   if not v_qr.is_permanent then
     update public.qr_sessions set used_at=now() where id=v_qr.id;
   end if;
 end if;
 update public.attendance
 set check_out=now(),check_out_lat=p_lat,check_out_lng=p_lng,status='completed'
 where employee_id=auth.uid() and work_date=v_date
   and check_in is not null and check_out is null
 returning * into v_row;
 if v_row.id is null then raise exception 'لا يوجد حضور مفتوح لتسجيل الانصراف'; end if;
 return v_row;
end $$;

revoke all on function public.record_check_in(double precision,double precision,text,text) from public;
revoke all on function public.record_check_out(double precision,double precision,text,text) from public;
grant execute on function public.record_check_in(double precision,double precision,text,text) to authenticated;
grant execute on function public.record_check_out(double precision,double precision,text,text) to authenticated;
