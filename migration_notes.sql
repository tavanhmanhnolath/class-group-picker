-- กรอบโน้ตของแต่ละกลุ่ม: คนในกลุ่มนั้น + แอดมิน เขียนได้ / ทุกคนอ่านได้
create table if not exists group_notes (
  activity_id uuid not null references activities(id) on delete cascade,
  group_no int not null,
  note text not null,
  updated_by text not null default '',
  updated_at timestamptz not null default now(),
  primary key (activity_id, group_no)
);
alter table group_notes enable row level security;
drop policy if exists "read notes" on group_notes;
create policy "read notes" on group_notes for select to anon using (true);
revoke all on group_notes from anon;
grant select on group_notes to anon;

-- สมาชิกในกลุ่มเขียน (ต้องยืนยัน PIN และอยู่ในกลุ่มนั้นจริง) ว่าง = ลบโน้ต
create or replace function set_group_note(p_activity uuid, p_code text, p_pin text, p_group int, p_note text)
returns void language plpgsql security definer set search_path = public as $$
declare n text := trim(coalesce(p_note, '')); nm text;
begin
  perform _check_student(p_code, p_pin);
  if not exists (select 1 from memberships where activity_id = p_activity and student_code = p_code and group_no = p_group) then
    raise exception 'ສະເພາະສະມາຊິກຂອງກຸ່ມນີ້ເທົ່ານັ້ນທີ່ຂຽນໄດ້';
  end if;
  if char_length(n) > 300 then raise exception 'ຍາວເກີນ 300 ຕົວອັກສອນ'; end if;
  if n = '' then
    delete from group_notes where activity_id = p_activity and group_no = p_group;
  else
    select name into nm from students where code = p_code;
    insert into group_notes (activity_id, group_no, note, updated_by, updated_at)
      values (p_activity, p_group, n, coalesce(nm, ''), now())
      on conflict (activity_id, group_no) do update
        set note = excluded.note, updated_by = excluded.updated_by, updated_at = excluded.updated_at;
  end if;
end $$;

-- แอดมินเขียนได้ทุกกลุ่ม
create or replace function admin_set_group_note(p_pin text, p_activity uuid, p_group int, p_note text)
returns void language plpgsql security definer set search_path = public as $$
declare n text := trim(coalesce(p_note, '')); a activities;
begin
  perform _check_pin(p_pin);
  select * into a from activities where id = p_activity;
  if not found then raise exception 'ບໍ່ພົບກິດຈະກຳ'; end if;
  if p_group < 1 or p_group > a.group_count then raise exception 'ກຸ່ມບໍ່ຖືກຕ້ອງ'; end if;
  if char_length(n) > 300 then raise exception 'ຍາວເກີນ 300 ຕົວອັກສອນ'; end if;
  if n = '' then
    delete from group_notes where activity_id = p_activity and group_no = p_group;
  else
    insert into group_notes (activity_id, group_no, note, updated_by, updated_at)
      values (p_activity, p_group, n, 'ແອດມິນ', now())
      on conflict (activity_id, group_no) do update
        set note = excluded.note, updated_by = excluded.updated_by, updated_at = excluded.updated_at;
  end if;
end $$;

grant execute on function set_group_note(uuid, text, text, int, text), admin_set_group_note(text, uuid, int, text) to anon;

-- ลดจำนวนกลุ่ม: โน้ตของกลุ่มที่ถูกลบหายไปด้วย
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
  delete from group_notes where activity_id = p_activity and group_no > p_count;
  update activities
     set title = coalesce(nullif(trim(p_title), ''), title), group_count = p_count, group_size = p_size
   where id = p_activity;
  return removed;
end $$;

alter publication supabase_realtime add table group_notes;
