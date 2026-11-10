-- แอดมินแก้ชื่อ/จำนวนกลุ่ม/คนต่อกลุ่ม หลังสร้างกิจกรรมแล้ว
-- ลดจำนวนกลุ่ม: คนในกลุ่มที่ถูกลบจะถูกถอดออก (คืนเป็น "ยังไม่มีกลุ่ม")
-- ลดคนต่อกลุ่ม: ถ้ามีกลุ่มที่เกิน ให้ error และต้องย้ายคนออกก่อน
-- คืนค่า: จำนวนคนที่ถูกถอดออก
create or replace function admin_update_activity(p_pin text, p_activity uuid, p_title text, p_count int, p_size int)
returns int language plpgsql security definer set search_path = public as $$
declare removed int := 0; g record;
begin
  perform _check_pin(p_pin);
  perform 1 from activities where id = p_activity for update;
  if not found then raise exception 'ไม่พบกิจกรรม'; end if;
  if p_count < 1 or p_count > 50 or p_size < 1 or p_size > 100 then
    raise exception 'ค่าไม่ถูกต้อง';
  end if;
  select group_no, count(*) as c into g from memberships
    where activity_id = p_activity and group_no <= p_count
    group by group_no having count(*) > p_size order by group_no limit 1;
  if found then
    raise exception 'กลุ่ม % มี % คน เกิน % คน กรุณาย้ายคนออกก่อน', g.group_no, g.c, p_size;
  end if;
  delete from memberships where activity_id = p_activity and group_no > p_count;
  get diagnostics removed = row_count;
  update activities
     set title = coalesce(nullif(trim(p_title), ''), title), group_count = p_count, group_size = p_size
   where id = p_activity;
  return removed;
end $$;
grant execute on function admin_update_activity(text, uuid, text, int, int) to anon;
