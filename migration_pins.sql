-- PIN ต่อคน: ตารางแยก anon อ่านไม่ได้
create table if not exists student_pins (
  code text primary key references students(code) on delete cascade,
  pin  text not null
);
alter table student_pins enable row level security;
revoke all on student_pins from anon, authenticated;

insert into student_pins (code, pin)
  select code, lpad(floor(random()*1000000)::int::text, 6, '0') from students
  on conflict (code) do nothing;

create or replace function _check_student(p_code text, p_pin text) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not exists (select 1 from student_pins where code = p_code and pin = p_pin) then
    raise exception 'PIN ไม่ถูกต้อง';
  end if;
end $$;

create or replace function verify_pin(p_code text, p_pin text) returns boolean
language sql security definer set search_path = public as $$
  select exists (select 1 from student_pins where code = p_code and pin = p_pin);
$$;

drop function if exists join_group(uuid, text, int);
drop function if exists leave_group(uuid, text);

create or replace function join_group(p_activity uuid, p_code text, p_pin text, p_group int)
returns void language plpgsql security definer set search_path = public as $$
declare a activities; cnt int;
begin
  perform _check_student(p_code, p_pin);
  select * into a from activities where id = p_activity for update;
  if not found then raise exception 'ไม่พบกิจกรรม'; end if;
  if a.locked then raise exception 'กิจกรรมนี้ถูกล็อกแล้ว'; end if;
  if p_group < 1 or p_group > a.group_count then raise exception 'กลุ่มไม่ถูกต้อง'; end if;
  select count(*) into cnt from memberships
    where activity_id = p_activity and group_no = p_group and student_code <> p_code;
  if cnt >= a.group_size then raise exception 'กลุ่มนี้เต็มแล้ว'; end if;
  insert into memberships (activity_id, student_code, group_no)
    values (p_activity, p_code, p_group)
    on conflict (activity_id, student_code) do update set group_no = excluded.group_no;
end $$;

create or replace function leave_group(p_activity uuid, p_code text, p_pin text)
returns void language plpgsql security definer set search_path = public as $$
begin
  perform _check_student(p_code, p_pin);
  if exists (select 1 from activities where id = p_activity and locked) then
    raise exception 'กิจกรรมนี้ถูกล็อกแล้ว';
  end if;
  delete from memberships where activity_id = p_activity and student_code = p_code;
end $$;

create or replace function admin_get_pins(p_pin text)
returns table (no int, code text, gender text, name text, pin text)
language plpgsql security definer set search_path = public as $$
begin
  perform _check_pin(p_pin);
  return query select s.no, s.code, s.gender, s.name, sp.pin
    from students s join student_pins sp on sp.code = s.code order by s.no;
end $$;

grant execute on function verify_pin(text,text), join_group(uuid,text,text,int),
  leave_group(uuid,text,text), admin_get_pins(text) to anon;
revoke execute on function _check_student(text,text) from anon, public;
