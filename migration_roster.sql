-- เอานักศึกษาที่ออกเรียนแล้วออกจากรายชื่อ (soft delete: คืนชื่อได้)
alter table students add column if not exists active boolean not null default true;

-- เอาออก (p_active=false): ถอดออกจากทุกกลุ่มด้วย / คืนชื่อ (p_active=true)
create or replace function admin_set_student_active(p_pin text, p_code text, p_active boolean)
returns void language plpgsql security definer set search_path = public as $$
begin
  perform _check_pin(p_pin);
  update students set active = p_active where code = p_code;
  if not found then raise exception 'ບໍ່ພົບນັກສຶກສາ'; end if;
  if not p_active then delete from memberships where student_code = p_code; end if;
end $$;

-- คนที่ถูกเอาออกเข้ากลุ่มไม่ได้
create or replace function join_group(p_activity uuid, p_code text, p_pin text, p_group int)
returns void language plpgsql security definer set search_path = public as $$
declare a activities; cnt int;
begin
  perform _check_student(p_code, p_pin);
  if not exists (select 1 from students where code = p_code and active) then
    raise exception 'ບໍ່ພົບລາຍຊື່';
  end if;
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

-- สุ่มจัดเฉพาะคนที่ยังอยู่ในรายชื่อ
create or replace function admin_random_fill(p_pin text, p_activity uuid)
returns int language plpgsql security definer set search_path = public as $$
declare a activities; s record; g int; placed int := 0;
begin
  perform _check_pin(p_pin);
  select * into a from activities where id = p_activity for update;
  for s in select code from students
           where active and code not in (select student_code from memberships where activity_id = p_activity)
           order by random() loop
    select n into g from generate_series(1, a.group_count) n
      where (select count(*) from memberships where activity_id = p_activity and group_no = n) < a.group_size
      order by (select count(*) from memberships where activity_id = p_activity and group_no = n), random()
      limit 1;
    exit when g is null;
    insert into memberships values (p_activity, s.code, g);
    placed := placed + 1;
  end loop;
  return placed;
end $$;

-- ไฟล์ PIN (CSV) เฉพาะคนที่ยังอยู่
create or replace function admin_get_pins(p_pin text)
returns table (no int, code text, gender text, name text, pin text)
language plpgsql security definer set search_path = public as $$
begin
  perform _check_pin(p_pin);
  return query select s.no, s.code, s.gender, s.name, sp.pin
    from students s join student_pins sp on sp.code = s.code where s.active order by s.no;
end $$;

grant execute on function admin_set_student_active(text, text, boolean) to anon;
