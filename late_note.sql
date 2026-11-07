-- HODOR: Late arrival notes migration
-- Run this once in Supabase Dashboard > SQL Editor > New query.

alter table public.attendance
  add column if not exists late_note text;

create or replace function public.save_late_note(p_note text)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_date date := (now() at time zone 'Africa/Cairo')::date;
begin
  if auth.uid() is null then
    raise exception 'يجب تسجيل الدخول أولاً';
  end if;

  if p_note is null or btrim(p_note) = '' then
    raise exception 'اكتب سبب التأخير أولاً';
  end if;

  if char_length(btrim(p_note)) > 500 then
    raise exception 'الملاحظة يجب ألا تتجاوز 500 حرف';
  end if;

  update public.attendance
     set late_note = btrim(p_note)
   where employee_id = auth.uid()
     and work_date = v_date
     and status = 'late'
     and check_in is not null;

  if not found then
    raise exception 'لا يوجد تسجيل حضور متأخر لهذا اليوم';
  end if;
end;
$$;

revoke all on function public.save_late_note(text) from public;
grant execute on function public.save_late_note(text) to authenticated;
