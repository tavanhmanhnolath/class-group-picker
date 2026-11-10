-- นักศึกษาเสริม (เช่น คนมาเรียนคืน): แอดมินเพิ่ม/ตั้ง PIN/ลบ ได้
alter table students add column if not exists is_guest boolean not null default false;

-- เพิ่มนักศึกษา: คืนค่า code ที่ใช้ (ถ้าไม่ใส่ code จะสร้าง EXT001, EXT002, ...)
create or replace function admin_add_student(p_pin text, p_name text, p_gender text, p_code text, p_student_pin text)
returns text language plpgsql security definer set search_path = public as $$
declare c text; n int;
begin
  perform _check_pin(p_pin);
  if coalesce(trim(p_name), '') = '' then raise exception 'ກະລຸນາໃສ່ຊື່'; end if;
  if p_student_pin !~ '^[0-9]{4}$' then raise exception 'PIN ຕ້ອງເປັນຕົວເລກ 4 ຕົວ'; end if;
  select coalesce(max(no), 0) + 1 into n from students;
  c := nullif(trim(p_code), '');
  if c is null then c := 'EXT' || lpad(n::text, 3, '0'); end if;
  if exists (select 1 from students where code = c) then raise exception 'ລະຫັດນີ້ມີໃນລະບົບແລ້ວ'; end if;
  insert into students (code, no, gender, name, is_guest)
    values (c, n, nullif(trim(p_gender), ''), trim(p_name), true);
  insert into student_pins (code, pin) values (c, p_student_pin);
  return c;
end $$;

-- ตั้ง/เปลี่ยน PIN ของนักศึกษาคนใดก็ได้
create or replace function admin_set_student_pin(p_pin text, p_code text, p_student_pin text)
returns void language plpgsql security definer set search_path = public as $$
begin
  perform _check_pin(p_pin);
  if p_student_pin !~ '^[0-9]{4}$' then raise exception 'PIN ຕ້ອງເປັນຕົວເລກ 4 ຕົວ'; end if;
  update student_pins set pin = p_student_pin where code = p_code;
  if not found then raise exception 'ບໍ່ພົບນັກສຶກສາ'; end if;
end $$;

-- ลบได้เฉพาะนักศึกษาที่แอดมินเพิ่มเอง (ลบรายชื่อห้องหลักไม่ได้)
create or replace function admin_remove_student(p_pin text, p_code text)
returns void language plpgsql security definer set search_path = public as $$
begin
  perform _check_pin(p_pin);
  if not exists (select 1 from students where code = p_code and is_guest) then
    raise exception 'ລຶບໄດ້ສະເພາະນັກສຶກສາທີ່ເພີ່ມເອງ';
  end if;
  delete from memberships where student_code = p_code;
  delete from students where code = p_code;
end $$;

grant execute on function admin_add_student(text,text,text,text,text),
  admin_set_student_pin(text,text,text), admin_remove_student(text,text) to anon;

alter publication supabase_realtime add table students;
