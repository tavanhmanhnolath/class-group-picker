-- ขนาดกลุ่มรายกลุ่ม: group_sizes = {"3": 5} หมายถึงกลุ่ม 3 เต็มที่ 5 คน (กลุ่มที่ไม่ระบุใช้ group_size ของกิจกรรม)
alter table activities add column if not exists group_sizes jsonb not null default '{}';

create or replace function _cap(a activities, g int) returns int
language sql immutable as $$
  select coalesce((a.group_sizes ->> g::text)::int, a.group_size)
$$;

-- p_size ว่าง = กลับไปใช้ค่ากลางของกิจกรรม
create or replace function admin_set_group_size(p_pin text, p_activity uuid, p_group int, p_size int)
returns void language plpgsql security definer set search_path = public as $$
declare a activities; c int;
begin
  perform _check_pin(p_pin);
  select * into a from activities where id = p_activity for update;
  if not found then raise exception 'ບໍ່ພົບກິດຈະກຳ'; end if;
  if p_group < 1 or p_group > a.group_count then raise exception 'ກຸ່ມບໍ່ຖືກຕ້ອງ'; end if;
  if p_size is null then
    update activities set group_sizes = group_sizes - p_group::text where id = p_activity;
    return;
  end if;
  if p_size < 1 or p_size > 100 then raise exception 'ຄ່າບໍ່ຖືກຕ້ອງ'; end if;
  select count(*) into c from memberships where activity_id = p_activity and group_no = p_group;
  if c > p_size then
    raise exception 'ກຸ່ມ % ມີ % ຄົນ ເກີນ % ຄົນ ກະລຸນາຍ້າຍຄົນອອກກ່ອນ', p_group, c, p_size;
  end if;
  update activities set group_sizes = group_sizes || jsonb_build_object(p_group::text, p_size) where id = p_activity;
end $$;
grant execute on function admin_set_group_size(text, uuid, int, int) to anon;

create or replace function join_group(p_activity uuid, p_code text, p_pin text, p_group int)
returns void language plpgsql security definer set search_path = public as $$
declare a activities; cnt int; cur int;
begin
  perform _check_student(p_code, p_pin);
  if not exists (select 1 from students where code = p_code and active) then
    raise exception 'ບໍ່ພົບລາຍຊື່';
  end if;
  select * into a from activities where id = p_activity for update;
  if not found then raise exception 'ບໍ່ພົບກິດຈະກຳ'; end if;
  if a.locked then raise exception 'ກິດຈະກຳນີ້ຖືກລ໋ອກແລ້ວ ປ່ຽນກຸ່ມບໍ່ໄດ້'; end if;
  if p_group < 1 or p_group > a.group_count then raise exception 'ກຸ່ມບໍ່ຖືກຕ້ອງ'; end if;
  select group_no into cur from memberships where activity_id = p_activity and student_code = p_code;
  if cur = p_group then return; end if;
  if p_group = any(a.locked_groups) then raise exception 'ກຸ່ມນີ້ຖືກລ໋ອກແລ້ວ'; end if;
  if cur is not null and cur = any(a.locked_groups) then raise exception 'ກຸ່ມຂອງເຈົ້າຖືກລ໋ອກແລ້ວ ຍ້າຍອອກບໍ່ໄດ້'; end if;
  select count(*) into cnt from memberships
    where activity_id = p_activity and group_no = p_group and student_code <> p_code;
  if cnt >= _cap(a, p_group) then raise exception 'ກຸ່ມນີ້ເຕັມແລ້ວ'; end if;
  insert into memberships (activity_id, student_code, group_no)
    values (p_activity, p_code, p_group)
    on conflict (activity_id, student_code) do update set group_no = excluded.group_no;
end $$;

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
      where not (n = any(a.locked_groups))
        and (select count(*) from memberships where activity_id = p_activity and group_no = n) < _cap(a, n)
      order by (select count(*) from memberships where activity_id = p_activity and group_no = n), random()
      limit 1;
    exit when g is null;
    insert into memberships values (p_activity, s.code, g);
    placed := placed + 1;
  end loop;
  return placed;
end $$;

-- แก้กิจกรรม: เทียบกับขนาดรายกลุ่ม; ลดจำนวนกลุ่มแล้วล้างค่ารายกลุ่ม/ล็อก/โน้ตของกลุ่มที่ถูกลบ
create or replace function admin_update_activity(p_pin text, p_activity uuid, p_title text, p_count int, p_size int)
returns int language plpgsql security definer set search_path = public as $$
declare removed int := 0; g record; a activities;
begin
  perform _check_pin(p_pin);
  select * into a from activities where id = p_activity for update;
  if not found then raise exception 'ບໍ່ພົບກິດຈະກຳ'; end if;
  if p_count < 1 or p_count > 50 or p_size < 1 or p_size > 100 then
    raise exception 'ຄ່າບໍ່ຖືກຕ້ອງ';
  end if;
  select m.group_no, count(*) as c, coalesce((a.group_sizes ->> m.group_no::text)::int, p_size) as cap into g
    from memberships m
    where m.activity_id = p_activity and m.group_no <= p_count
    group by m.group_no
    having count(*) > coalesce((a.group_sizes ->> m.group_no::text)::int, p_size)
    order by m.group_no limit 1;
  if found then
    raise exception 'ກຸ່ມ % ມີ % ຄົນ ເກີນ % ຄົນ ກະລຸນາຍ້າຍຄົນອອກກ່ອນ', g.group_no, g.c, g.cap;
  end if;
  delete from memberships where activity_id = p_activity and group_no > p_count;
  get diagnostics removed = row_count;
  delete from group_notes where activity_id = p_activity and group_no > p_count;
  update activities
     set title = coalesce(nullif(trim(p_title), ''), title), group_count = p_count, group_size = p_size,
         locked_groups = array(select x from unnest(locked_groups) x where x <= p_count),
         group_sizes = coalesce((select jsonb_object_agg(k, v) from jsonb_each(group_sizes) as e(k, v) where k::int <= p_count), '{}')
   where id = p_activity;
  return removed;
end $$;
