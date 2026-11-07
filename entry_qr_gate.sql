-- HODOR: Require the permanent library QR and GPS proximity before employee dashboard access.
-- Run once in Supabase Dashboard > SQL Editor.

create or replace function public.verify_entry_qr(
  p_qr_token text,
  p_lat double precision,
  p_lng double precision
) returns boolean
language plpgsql
security definer
set search_path=public
as $$
declare
  v_profile public.profiles;
  v_settings public.app_settings;
  v_qr public.qr_sessions;
  v_dist double precision;
begin
  if auth.uid() is null then
    raise exception 'يجب تسجيل الدخول أولاً';
  end if;

  select * into v_profile
  from public.profiles
  where id=auth.uid() and active=true;

  if not found then
    raise exception 'الحساب غير نشط أو غير مسجل';
  end if;

  if v_profile.role='admin' then
    return true;
  end if;

  select * into v_qr
  from public.qr_sessions
  where token=p_qr_token
    and is_permanent=true
  limit 1;

  if not found then
    raise exception 'رمز QR غير صحيح أو ليس رمز المكتبة الثابت';
  end if;

  select * into v_settings
  from public.app_settings
  where id=1;

  if v_settings.latitude is null or v_settings.longitude is null
     or p_lat is null or p_lng is null then
    raise exception 'إعدادات موقع المكتبة أو موقع جهازك غير مكتملة';
  end if;

  v_dist := 6371000*2*asin(sqrt(
    power(sin(radians(p_lat-v_settings.latitude)/2),2)
    + cos(radians(v_settings.latitude))*cos(radians(p_lat))
    * power(sin(radians(p_lng-v_settings.longitude)/2),2)
  ));

  if v_dist > v_settings.radius_m then
    raise exception 'أنت خارج نطاق المكتبة. اقترب من مقر العمل وحاول مرة أخرى';
  end if;

  return true;
end;
$$;

revoke all on function public.verify_entry_qr(text,double precision,double precision) from public;
grant execute on function public.verify_entry_qr(text,double precision,double precision) to authenticated;
