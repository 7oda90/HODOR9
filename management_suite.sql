-- HODOR management suite: salaries, leave requests, payroll adjustments, notifications and audit trail.
-- Run once in Supabase SQL Editor after the existing HODOR migrations.

alter table public.profiles
  add column if not exists monthly_salary numeric(12,2) not null default 0
  check (monthly_salary >= 0);

create table if not exists public.leave_requests (
  id uuid primary key default gen_random_uuid(),
  employee_id uuid not null references public.profiles(id) on delete cascade,
  start_date date not null,
  end_date date not null,
  reason text not null,
  status text not null default 'pending' check(status in ('pending','approved','rejected')),
  reviewed_by uuid references public.profiles(id),
  reviewed_at timestamptz,
  created_at timestamptz not null default now(),
  check(end_date >= start_date),
  check(char_length(btrim(reason)) between 3 and 500)
);

create table if not exists public.payroll_adjustments (
  id uuid primary key default gen_random_uuid(),
  employee_id uuid not null references public.profiles(id) on delete cascade,
  period_month date not null,
  kind text not null check(kind in ('bonus','deduction')),
  amount numeric(12,2) not null check(amount > 0),
  note text not null,
  created_by uuid not null references public.profiles(id),
  created_at timestamptz not null default now(),
  check(date_trunc('month',period_month)::date=period_month)
);

create table if not exists public.notifications (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  title text not null,
  body text not null,
  kind text not null default 'info',
  read_at timestamptz,
  created_at timestamptz not null default now()
);

create table if not exists public.audit_logs (
  id bigint generated always as identity primary key,
  actor_id uuid references public.profiles(id),
  action text not null,
  entity text not null,
  entity_id text,
  details jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

alter table public.leave_requests enable row level security;
alter table public.payroll_adjustments enable row level security;
alter table public.notifications enable row level security;
alter table public.audit_logs enable row level security;

drop policy if exists "leave own or admin read" on public.leave_requests;
create policy "leave own or admin read" on public.leave_requests for select to authenticated
using(employee_id=auth.uid() or public.is_admin());
drop policy if exists "employee create own leave" on public.leave_requests;
create policy "employee create own leave" on public.leave_requests for insert to authenticated
with check(employee_id=auth.uid() and status='pending' and reviewed_by is null);
drop policy if exists "admin review leave" on public.leave_requests;
create policy "admin review leave" on public.leave_requests for update to authenticated
using(public.is_admin()) with check(public.is_admin());

drop policy if exists "payroll admin read" on public.payroll_adjustments;
create policy "payroll admin read" on public.payroll_adjustments for select to authenticated using(public.is_admin());
drop policy if exists "payroll admin insert" on public.payroll_adjustments;
create policy "payroll admin insert" on public.payroll_adjustments for insert to authenticated
with check(public.is_admin() and created_by=auth.uid());

drop policy if exists "notification own read" on public.notifications;
create policy "notification own read" on public.notifications for select to authenticated using(user_id=auth.uid() or public.is_admin());
drop policy if exists "notification own update" on public.notifications;
create policy "notification own update" on public.notifications for update to authenticated using(user_id=auth.uid()) with check(user_id=auth.uid());
drop policy if exists "notification admin insert" on public.notifications;
create policy "notification admin insert" on public.notifications for insert to authenticated with check(public.is_admin());

drop policy if exists "audit admin read" on public.audit_logs;
create policy "audit admin read" on public.audit_logs for select to authenticated using(public.is_admin());

create or replace function public.submit_leave_request(p_start date,p_end date,p_reason text)
returns public.leave_requests
language plpgsql security definer set search_path=public
as $$
declare v_row public.leave_requests; v_admin record;
begin
 if auth.uid() is null then raise exception 'يجب تسجيل الدخول'; end if;
 if p_start is null or p_end is null or p_end<p_start then raise exception 'راجع تاريخ بداية ونهاية الإجازة'; end if;
 if p_reason is null or char_length(btrim(p_reason))<3 or char_length(btrim(p_reason))>500 then raise exception 'اكتب سبب الإجازة (3 إلى 500 حرف)'; end if;
 insert into public.leave_requests(employee_id,start_date,end_date,reason)
 values(auth.uid(),p_start,p_end,btrim(p_reason)) returning * into v_row;
 for v_admin in select id from public.profiles where role='admin' and active=true loop
   insert into public.notifications(user_id,title,body,kind)
   values(v_admin.id,'طلب إجازة جديد','يوجد طلب إجازة جديد يحتاج للمراجعة','leave');
 end loop;
 insert into public.audit_logs(actor_id,action,entity,entity_id,details)
 values(auth.uid(),'submit','leave_requests',v_row.id::text,jsonb_build_object('start_date',p_start,'end_date',p_end));
 return v_row;
end $$;

create or replace function public.review_leave_request(p_id uuid,p_decision text)
returns void language plpgsql security definer set search_path=public
as $$
declare v_row public.leave_requests;
begin
 if not public.is_admin() then raise exception 'غير مصرح'; end if;
 if p_decision not in ('approved','rejected') then raise exception 'قرار غير صالح'; end if;
 update public.leave_requests set status=p_decision,reviewed_by=auth.uid(),reviewed_at=now()
 where id=p_id and status='pending' returning * into v_row;
 if v_row.id is null then raise exception 'الطلب غير موجود أو تمت مراجعته'; end if;
 insert into public.notifications(user_id,title,body,kind)
 values(v_row.employee_id,'تم تحديث طلب الإجازة',case when p_decision='approved' then 'تمت الموافقة على طلب الإجازة' else 'تم رفض طلب الإجازة' end,'leave');
 insert into public.audit_logs(actor_id,action,entity,entity_id,details)
 values(auth.uid(),p_decision,'leave_requests',p_id::text,'{}'::jsonb);
end $$;

create or replace function public.add_payroll_adjustment(p_employee uuid,p_month date,p_kind text,p_amount numeric,p_note text)
returns public.payroll_adjustments
language plpgsql security definer set search_path=public
as $$
declare v_row public.payroll_adjustments;
begin
 if not public.is_admin() then raise exception 'غير مصرح'; end if;
 if p_kind not in ('bonus','deduction') or p_amount<=0 or p_month is null or p_note is null or btrim(p_note)='' then
   raise exception 'راجع نوع وقيمة وبيان التسوية';
 end if;
 insert into public.payroll_adjustments(employee_id,period_month,kind,amount,note,created_by)
 values(p_employee,date_trunc('month',p_month)::date,p_kind,p_amount,btrim(p_note),auth.uid()) returning * into v_row;
 insert into public.audit_logs(actor_id,action,entity,entity_id,details)
 values(auth.uid(),'create','payroll_adjustments',v_row.id::text,jsonb_build_object('employee_id',p_employee,'amount',p_amount,'kind',p_kind));
 return v_row;
end $$;

create or replace function public.mark_notification_read(p_id uuid)
returns void language plpgsql security definer set search_path=public
as $$
begin
 update public.notifications set read_at=now() where id=p_id and user_id=auth.uid();
end $$;

revoke all on function public.submit_leave_request(date,date,text) from public;
revoke all on function public.review_leave_request(uuid,text) from public;
revoke all on function public.add_payroll_adjustment(uuid,date,text,numeric,text) from public;
revoke all on function public.mark_notification_read(uuid) from public;
grant execute on function public.submit_leave_request(date,date,text) to authenticated;
grant execute on function public.review_leave_request(uuid,text) to authenticated;
grant execute on function public.add_payroll_adjustment(uuid,date,text,numeric,text) to authenticated;
grant execute on function public.mark_notification_read(uuid) to authenticated;

