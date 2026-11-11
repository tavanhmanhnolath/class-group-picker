-- ประวัติการแก้โน้ต: ชื่อคนแก้/เวลา เก็บในตารางที่ anon อ่านไม่ได้ ดูได้เฉพาะแอดมิน
create table if not exists group_note_history (
  id bigint generated always as identity primary key,
  activity_id uuid not null,
  group_no int not null,
  note text not null,          -- ว่าง = ลบโน้ต
  author text not null,
  made_at timestamptz not null default now()
);
alter table group_note_history enable row level security;
revoke all on group_note_history from anon;

-- ย้ายชื่อที่เคยเก็บใน group_notes เข้าประวัติ แล้วลบชื่อออกจากตารางที่สาธารณะอ่านได้
insert into group_note_history (activity_id, group_no, note, author, made_at)
  select activity_id, group_no, note, updated_by, updated_at from group_notes
  where updated_by <> '' and not exists (select 1 from group_note_history);
update group_notes set updated_by = '' where updated_by <> '';

create or replace function set_group_note(p_activity uuid, p_code text, p_pin text, p_group int, p_note text)
returns void language plpgsql security definer set search_path = public as $$
declare n text := trim(coalesce(p_note, '')); nm text;
begin
  perform _check_student(p_code, p_pin);
  if not exists (select 1 from memberships where activity_id = p_activity and student_code = p_code and group_no = p_group) then
    raise exception 'ສະເພາະສະມາຊິກຂອງກຸ່ມນີ້ເທົ່ານັ້ນທີ່ຂຽນໄດ້';
  end if;
  if char_length(n) > 100 then raise exception 'ຍາວເກີນ 100 ຕົວອັກສອນ'; end if;
  select name into nm from students where code = p_code;
  if n = '' then
    delete from group_notes where activity_id = p_activity and group_no = p_group;
  else
    insert into group_notes (activity_id, group_no, note, updated_by, updated_at)
      values (p_activity, p_group, n, '', now())
      on conflict (activity_id, group_no) do update
        set note = excluded.note, updated_by = '', updated_at = excluded.updated_at;
  end if;
  insert into group_note_history (activity_id, group_no, note, author) values (p_activity, p_group, n, coalesce(nm, p_code));
end $$;

create or replace function admin_set_group_note(p_pin text, p_activity uuid, p_group int, p_note text)
returns void language plpgsql security definer set search_path = public as $$
declare n text := trim(coalesce(p_note, '')); a activities;
begin
  perform _check_pin(p_pin);
  select * into a from activities where id = p_activity;
  if not found then raise exception 'ບໍ່ພົບກິດຈະກຳ'; end if;
  if p_group < 1 or p_group > a.group_count then raise exception 'ກຸ່ມບໍ່ຖືກຕ້ອງ'; end if;
  if char_length(n) > 100 then raise exception 'ຍາວເກີນ 100 ຕົວອັກສອນ'; end if;
  if n = '' then
    delete from group_notes where activity_id = p_activity and group_no = p_group;
  else
    insert into group_notes (activity_id, group_no, note, updated_by, updated_at)
      values (p_activity, p_group, n, '', now())
      on conflict (activity_id, group_no) do update
        set note = excluded.note, updated_by = '', updated_at = excluded.updated_at;
  end if;
  insert into group_note_history (activity_id, group_no, note, author) values (p_activity, p_group, n, 'ແອດມິນ');
end $$;

create or replace function admin_get_note_history(p_pin text)
returns table (made_at timestamptz, title text, grp int, author text, note_text text)
language plpgsql security definer set search_path = public as $$
begin
  perform _check_pin(p_pin);
  return query
    select h.made_at, a.title, h.group_no, h.author, h.note
    from group_note_history h left join activities a on a.id = h.activity_id
    order by h.made_at desc limit 300;
end $$;
grant execute on function admin_get_note_history(text) to anon;
