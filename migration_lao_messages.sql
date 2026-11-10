-- ข้อความ error ทั้งหมดของฐานข้อมูลเป็นภาษาลาว (ตรรกะเหมือนเดิมทุกอย่าง เปลี่ยนเฉพาะข้อความ)
create or replace function _check_pin(p_pin text) returns void
language plpgsql security definer set search_path = public as $$
begin
  if p_pin is distinct from (select value from settings where key = 'admin_pin') then
    raise exception 'ລະຫັດແອດມິນບໍ່ຖືກຕ້ອງ';
  end if;
end $$;

create or replace function _check_student(p_code text, p_pin text) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not exists (select 1 from student_pins where code = p_code and pin = p_pin) then
    raise exception 'PIN ບໍ່ຖືກຕ້ອງ';
  end if;
end $$;

create or replace function join_group(p_activity uuid, p_code text, p_pin text, p_group int)
returns void language plpgsql security definer set search_path = public as $$
declare a activities; cnt int;
begin
  perform _check_student(p_code, p_pin);
  if not exists (select 1 from students where code = p_code and active) then
    raise exception 'ບໍ່ພົບລາຍຊື່';
  end if;
  select * into a from activities where id = p_activity for update;
  if not found then raise exception 'ບໍ່ພົບກິດຈະກຳ'; end if;
  if a.locked then raise exception 'ກິດຈະກຳນີ້ຖືກລ໋ອກແລ້ວ ປ່ຽນກຸ່ມບໍ່ໄດ້'; end if;
  if p_group < 1 or p_group > a.group_count then raise exception 'ກຸ່ມບໍ່ຖືກຕ້ອງ'; end if;
  select count(*) into cnt from memberships
    where activity_id = p_activity and group_no = p_group and student_code <> p_code;
  if cnt >= a.group_size then raise exception 'ກຸ່ມນີ້ເຕັມແລ້ວ'; end if;
  insert into memberships (activity_id, student_code, group_no)
    values (p_activity, p_code, p_group)
    on conflict (activity_id, student_code) do update set group_no = excluded.group_no;
end $$;

create or replace function leave_group(p_activity uuid, p_code text, p_pin text)
returns void language plpgsql security definer set search_path = public as $$
begin
  perform _check_student(p_code, p_pin);
  if exists (select 1 from activities where id = p_activity and locked) then
    raise exception 'ກິດຈະກຳນີ້ຖືກລ໋ອກແລ້ວ ປ່ຽນກຸ່ມບໍ່ໄດ້';
  end if;
  delete from memberships where activity_id = p_activity and student_code = p_code;
end $$;

create or replace function admin_update_activity(p_pin text, p_activity uuid, p_title text, p_count int, p_size int)
returns int language plpgsql security definer set search_path = public as $$
declare removed int := 0; g record;
begin
  perform _check_pin(p_pin);
  perform 1 from activities where id = p_activity for update;
  if not found then raise exception 'ບໍ່ພົບກິດຈະກຳ'; end if;
  if p_count < 1 or p_count > 50 or p_size < 1 or p_size > 100 then
    raise exception 'ຄ່າບໍ່ຖືກຕ້ອງ';
  end if;
  select group_no, count(*) as c into g from memberships
    where activity_id = p_activity and group_no <= p_count
    group by group_no having count(*) > p_size order by group_no limit 1;
  if found then
    raise exception 'ກຸ່ມ % ມີ % ຄົນ ເກີນ % ຄົນ ກະລຸນາຍ້າຍຄົນອອກກ່ອນ', g.group_no, g.c, p_size;
  end if;
  delete from memberships where activity_id = p_activity and group_no > p_count;
  get diagnostics removed = row_count;
  update activities
     set title = coalesce(nullif(trim(p_title), ''), title), group_count = p_count, group_size = p_size
   where id = p_activity;
  return removed;
end $$;
