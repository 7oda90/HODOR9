-- HODOR schema for Supabase (run as project owner in SQL Editor)
create extension if not exists pgcrypto;

create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  full_name text not null,
  email text unique,
  role text not null default 'employee' check (role in ('admin','employee')),
  active boolean not null default true,
  shift_start time not null default '09:00',
  shift_end time not null default '17:00',
  created_at timestamptz not null default now()
);

create table if not exists public.app_settings (
  id integer primary key default 1 check (id=1),
  latitude double precision,
  longitude double precision,
  radius_m integer not null default 150 check (radius_m between 20 and 1000),
  grace_minutes integer not null default 10 check (grace_minutes between 0 and 120),
  updated_by uuid references auth.users(id),
  updated_at timestamptz not null default now()
);
insert into public.app_settings(id) values (1) on conflict do nothing;

create table if not exists public.qr_sessions (
  id uuid primary key default gen_random_uuid(),
  token text not null unique default encode(gen_random_bytes(24),'hex'),
  created_by uuid not null references auth.users(id),
  created_at timestamptz not null default now(),
  expires_at timestamptz not null default now()+interval '2 minutes',
  used_at timestamptz
);

create table if not exists public.attendance (
  id uuid primary key default gen_random_uuid(),
  employee_id uuid not null references public.profiles(id),
  work_date date not null default (now() at time zone 'Africa/Cairo')::date,
  check_in timestamptz,
  check_out timestamptz,
  status text not null default 'present' check(status in ('present','late','completed')),
  method text not null default 'button' check(method in ('button','gps','qr')),
  check_in_lat double precision,
  check_in_lng double precision,
  check_out_lat double precision,
  check_out_lng double precision,
  created_at timestamptz not null default now(),
  unique(employee_id,work_date)
);

create or replace function public.is_admin()
returns boolean language sql stable security definer set search_path=public
as $$ select exists(select 1 from public.profiles where id=auth.uid() and role='admin' and active=true); $$;

alter table public.profiles enable row level security;
alter table public.app_settings enable row level security;
alter table public.qr_sessions enable row level security;
alter table public.attendance enable row level security;

drop policy if exists "profile self or admin read" on public.profiles;
create policy "profile self or admin read" on public.profiles for select to authenticated
using (id=auth.uid() or public.is_admin());
drop policy if exists "admin update profiles" on public.profiles;
create policy "admin update profiles" on public.profiles for update to authenticated
using(public.is_admin()) with check(public.is_admin());

drop policy if exists "authenticated read settings" on public.app_settings;
create policy "authenticated read settings" on public.app_settings for select to authenticated using(true);
drop policy if exists "admin manage settings" on public.app_settings;
create policy "admin manage settings" on public.app_settings for all to authenticated using(public.is_admin()) with check(public.is_admin());

drop policy if exists "admin manage qr" on public.qr_sessions;
create policy "admin manage qr" on public.qr_sessions for all to authenticated using(public.is_admin()) with check(public.is_admin());

drop policy if exists "employee own attendance or admin" on public.attendance;
create policy "employee own attendance or admin" on public.attendance for select to authenticated
using(employee_id=auth.uid() or public.is_admin());

create or replace function public.record_check_in(
 p_lat double precision default null, p_lng double precision default null,
 p_method text default 'button', p_qr_token text default null
) returns public.attendance
language plpgsql security definer set search_path=public
as $$
declare v_profile public.profiles; v_settings public.app_settings; v_row public.attendance;
 v_date date := (now() at time zone 'Africa/Cairo')::date; v_shift time; v_status text := 'present';
 v_qr public.qr_sessions; v_dist double precision;
begin
 select * into v_settings from public.app_settings where id=1;
 select * into v_profile from public.profiles where id=auth.uid() and active=true;
 if not found then raise exception 'الحساب غير نشط أو غير مسجل'; end if;
 if p_method not in ('button','gps','qr') then raise exception 'طريقة تسجيل غير صالحة'; end if;
 if p_method in ('gps','qr') then
   if v_settings.latitude is null or v_settings.longitude is null or p_lat is null or p_lng is null then raise exception 'موقع المكتبة أو موقع جهازك غير محدد'; end if;
   v_dist := 6371000*2*asin(sqrt(power(sin(radians(p_lat-v_settings.latitude)/2),2)+cos(radians(v_settings.latitude))*cos(radians(p_lat))*power(sin(radians(p_lng-v_settings.longitude)/2),2)));
   if v_dist > v_settings.radius_m then raise exception 'أنت خارج نطاق موقع العمل'; end if;
 end if;
 if p_method='qr' then
   select * into v_qr from public.qr_sessions where token=p_qr_token and expires_at>now() and used_at is null for update;
   if not found then raise exception 'رمز QR غير صالح أو انتهت صلاحيته'; end if;
   update public.qr_sessions set used_at=now() where id=v_qr.id;
 end if;
 v_shift := v_profile.shift_start;
 if (now() at time zone 'Africa/Cairo')::time > v_shift + make_interval(mins=>coalesce(v_settings.grace_minutes,10)) then v_status:='late'; end if;
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
declare v_settings public.app_settings; v_row public.attendance; v_date date := (now() at time zone 'Africa/Cairo')::date;
 v_qr public.qr_sessions; v_dist double precision;
begin
 if p_method in ('gps','qr') then
   select * into v_settings from public.app_settings where id=1;
   if v_settings.latitude is null or v_settings.longitude is null or p_lat is null or p_lng is null then raise exception 'موقع المكتبة أو موقع جهازك غير محدد'; end if;
   v_dist := 6371000*2*asin(sqrt(power(sin(radians(p_lat-v_settings.latitude)/2),2)+cos(radians(v_settings.latitude))*cos(radians(p_lat))*power(sin(radians(p_lng-v_settings.longitude)/2),2)));
   if v_dist > v_settings.radius_m then raise exception 'أنت خارج نطاق موقع العمل'; end if;
 end if;
 if p_method='qr' then
   select * into v_qr from public.qr_sessions where token=p_qr_token and expires_at>now() and used_at is null for update;
   if not found then raise exception 'رمز QR غير صالح أو انتهت صلاحيته'; end if;
   update public.qr_sessions set used_at=now() where id=v_qr.id;
 end if;
 update public.attendance set check_out=now(),check_out_lat=p_lat,check_out_lng=p_lng,status='completed'
 where employee_id=auth.uid() and work_date=v_date and check_in is not null and check_out is null returning * into v_row;
 if v_row.id is null then raise exception 'لا يوجد حضور مفتوح لتسجيل الانصراف'; end if;
 return v_row;
end $$;

revoke all on function public.record_check_in(double precision,double precision,text,text) from public;
revoke all on function public.record_check_out(double precision,double precision,text,text) from public;
grant execute on function public.record_check_in(double precision,double precision,text,text) to authenticated;
grant execute on function public.record_check_out(double precision,double precision,text,text) to authenticated;

-- Profile creation trigger: new auth user gets an employee profile.
create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path=public
as $$
begin
 insert into public.profiles(id,full_name,email)
 values(new.id,coalesce(new.raw_user_meta_data->>'full_name',split_part(new.email,'@',1)),new.email)
 on conflict(id) do nothing;
 return new;
end $$;
drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created after insert on auth.users
for each row execute procedure public.handle_new_user();

-- IMPORTANT: after creating your own account, promote it to admin manually:
-- update public.profiles set role='admin', full_name='Mahmoud' where email='YOUR_ADMIN_EMAIL';