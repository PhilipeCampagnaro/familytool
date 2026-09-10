-- Every box photo and every list attachment was refused, and the reason was a
-- name that resolved to the wrong table.
--
-- `20260909170000_item_photos.sql` wrote each of the six policies as
--
--     exists (select 1 from public.boxes b
--              where b.id::text = (storage.foldername(name))[1] and …)
--
-- and inside that subquery `name` is **`boxes.name`**, not
-- `storage.objects.name` — the inner relation wins, and Postgres resolved it
-- silently. So the predicate asked whether a box's uuid equals the first path
-- segment of the box's *own name* ("Keller"), which is false for every row
-- there will ever be. Both buckets were therefore write-closed and
-- read-closed: `storage.objects` held nothing under either of them, and the
-- Listen attach menu's "Foto konnte nicht hochgeladen werden" was the honest
-- report of a policy that could not be satisfied.
--
-- `avatars_read_visible_profiles` already had this right — it says
-- `storage.foldername(objects.name)` — and that is the shape used here
-- throughout. **Qualify the column whenever a storage policy joins another
-- table**; the unqualified form is not a shorthand, it is a different column.

drop policy if exists "box_photos_read"        on storage.objects;
drop policy if exists "box_photos_write"       on storage.objects;
drop policy if exists "box_photos_delete"      on storage.objects;
drop policy if exists "list_attachments_read"  on storage.objects;
drop policy if exists "list_attachments_write" on storage.objects;
drop policy if exists "list_attachments_delete" on storage.objects;

create policy "box_photos_read"
  on storage.objects for select to authenticated
  using (
    bucket_id = 'box-photos'
    and exists (
      select 1 from public.boxes b
       where b.id::text = (storage.foldername(objects.name))[1]
         and private.can_read_box(b.id)
    )
  );

create policy "box_photos_write"
  on storage.objects for insert to authenticated
  with check (
    bucket_id = 'box-photos'
    and exists (
      select 1 from public.boxes b
       where b.id::text = (storage.foldername(objects.name))[1]
         and private.can_write_box(b.id)
    )
  );

create policy "box_photos_delete"
  on storage.objects for delete to authenticated
  using (
    bucket_id = 'box-photos'
    and exists (
      select 1 from public.boxes b
       where b.id::text = (storage.foldername(objects.name))[1]
         and private.can_write_box(b.id)
    )
  );

create policy "list_attachments_read"
  on storage.objects for select to authenticated
  using (
    bucket_id = 'list-attachments'
    and exists (
      select 1 from public.lists l
       where l.id::text = (storage.foldername(objects.name))[1]
         and private.can_read_list(l.id)
    )
  );

create policy "list_attachments_write"
  on storage.objects for insert to authenticated
  with check (
    bucket_id = 'list-attachments'
    and exists (
      select 1 from public.lists l
       where l.id::text = (storage.foldername(objects.name))[1]
         and private.can_write_list(l.id)
    )
  );

create policy "list_attachments_delete"
  on storage.objects for delete to authenticated
  using (
    bucket_id = 'list-attachments'
    and exists (
      select 1 from public.lists l
       where l.id::text = (storage.foldername(objects.name))[1]
         and private.can_write_list(l.id)
    )
  );
