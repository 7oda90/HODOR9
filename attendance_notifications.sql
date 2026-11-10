-- HODOR: notify active admins whenever an employee checks in.
-- Run this file once in Supabase SQL Editor.
create table if not exists public.notifications (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  title text not null,
  body text not null,
  kind text not null default 'info',
  read_at timestamptz,
  created_at timestamptz not null default now()
);
alter table public.notifications enable row level security;
drop policy if exists "notification own read" on public.notifications;
create policy "notification own read" on public.notifications
 for select to authenticated using(user_id=auth.uid() or public.is_admin());
drop policy if exists "notification own update" on public.notifications;
create policy "notification own update" on public.notifications
 for update to authenticated using(user_id=auth.uid()) with check(user_id=auth.uid());

create or replace function public.notify_admin_on_employee_checkin()
returns trigger
language plpgsql
security definer
set search_path=public
as $$
declare v_name text;
begin
  select full_name into v_name from public.profiles where id=new.employee_id;
  if new.check_in is not null then
    insert into public.notifications(user_id,title,body,kind)
    select p.id,
      'تسجيل حضور جديد',
      coalesce(v_name,'موظف') || ' سجّل الحضور الساعة ' ||
        to_char(new.check_in at time zone 'Africa/Cairo','HH12:MI AM'),
      'attendance'
    from public.profiles p
    where p.role='admin' and p.active=true and p.id<>new.employee_id;
  end if;
  return new;
end;
$$;

drop trigger if exists attendance_checkin_notify_admin on public.attendance;
create trigger attendance_checkin_notify_admin
after insert on public.attendance
for each row execute function public.notify_admin_on_employee_checkin();

do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname='supabase_realtime'
      and schemaname='public' and tablename='notifications'
  ) then
    alter publication supabase_realtime add table public.notifications;
  end if;
exception when undefined_object then
  raise notice 'supabase_realtime publication is unavailable; enable Realtime for public.notifications in Supabase Dashboard.';
end $$;
