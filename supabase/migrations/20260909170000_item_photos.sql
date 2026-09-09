-- Photographs of the things a household actually owns.
--
-- Two halves of one feature, and they are deliberately not the same shape,
-- because what they are for is not the same:
--
--   * A **box or a box item** gets **one** picture, and it stands in for the
--     symbol. A stored thing is found by recognising it — a photo of the drill
--     in the cellar says what "Bohrmaschine" and a hammer glyph cannot, and a
--     second photo of the same drill says nothing the first one didn't. Hence a
--     column, not a table: `photo_path` beside the `icon_asset` that stays as
--     the fallback for every box that has no picture.
--   * A **list article** keeps the attachment *list* it already had — the
--     receipt, the manual, the photo of the shelf — so `list_item_attachments`
--     is unchanged. It simply gains the bucket it was written for and never
--     got, which is why those attachments have been living in a Dart map and
--     dying with the process ever since.
--
-- **Both buckets are private, and the columns hold object paths, not URLs** —
-- the same trade `avatars` made and for the same reason: a public bucket would
-- put the inside of a family's cellar on an unauthenticated CDN URL that
-- outlives the account. The client signs per path at load time.
--
-- Layout is `<container_id>/<uuid>.<ext>` in both, so the **container** is the
-- first path segment and the read policy can ask the one question that matters:
-- may this user read that box / that list? Filing an item photo under its box
-- rather than under its item is what keeps that to a single predicate — an item
-- has no visibility of its own, it inherits the box's, so the box is the real
-- unit of access either way.

-- ---------------------------------------------------------------------------
-- Columns
-- ---------------------------------------------------------------------------

alter table public.boxes     add column if not exists photo_path text;
alter table public.box_items add column if not exists photo_path text;

comment on column public.boxes.photo_path is
  'Object path in the private `box-photos` bucket, `<box_id>/<uuid>.<ext>` — not a URL. Null means the box falls back to `icon_asset`.';
comment on column public.box_items.photo_path is
  'Object path in the private `box-photos` bucket, under the item''s **box** id (an item inherits the box''s visibility, so the box is the unit of access). Null means the item falls back to `icon_asset`.';

-- ---------------------------------------------------------------------------
-- Buckets
-- ---------------------------------------------------------------------------

-- Images only, and 10 MB is already generous: the client downscales to
-- `itemPhotoMaxDimension` before it uploads, so anything near the limit is a
-- picture that arrived some other way.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'box-photos',
  'box-photos',
  false,
  10 * 1024 * 1024,
  array['image/jpeg', 'image/png', 'image/heic', 'image/heif', 'image/webp']
)
on conflict (id) do update set
  public             = excluded.public,
  file_size_limit    = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

-- Wider, because "Dateien" is one of the three things the attach menu offers
-- and a manual is usually a PDF. Still an allowlist rather than `null`: the
-- picker can hand over anything the Files app holds, and a bucket that accepts
-- anything is a bucket that will eventually be asked to hold something nobody
-- meant to put there.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'list-attachments',
  'list-attachments',
  false,
  20 * 1024 * 1024,
  array[
    'image/jpeg', 'image/png', 'image/heic', 'image/heif', 'image/webp', 'image/gif',
    'application/pdf', 'text/plain'
  ]
)
on conflict (id) do update set
  public             = excluded.public,
  file_size_limit    = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

-- ---------------------------------------------------------------------------
-- Policies
-- ---------------------------------------------------------------------------
--
-- Keyed on `can_read_box` / `can_read_list` **alone**, never on household
-- membership — see the attachments note in docs/backend.md. A guest holding a
-- share link to one box can read that box's rows, and a storage policy that
-- asked "same household?" instead would hand them the words and keep the
-- pictures back.
--
-- Joined through the table on text rather than casting the path segment to
-- uuid, exactly as `avatars_read_visible_profiles` does: a cast raises on a
-- malformed object name, and an object nobody may read has to fail closed
-- rather than error the whole listing.

create policy "box_photos_read"
  on storage.objects for select to authenticated
  using (
    bucket_id = 'box-photos'
    and exists (
      select 1 from public.boxes b
       where b.id::text = (storage.foldername(name))[1]
         and private.can_read_box(b.id)
    )
  );

-- Writing a picture is editing the box, so it is the same predicate the box's
-- own UPDATE policy uses — which includes the guest who was granted `can_edit`
-- and excludes the one who wasn't.
create policy "box_photos_write"
  on storage.objects for insert to authenticated
  with check (
    bucket_id = 'box-photos'
    and exists (
      select 1 from public.boxes b
       where b.id::text = (storage.foldername(name))[1]
         and private.can_write_box(b.id)
    )
  );

-- Replacing a photo deletes the one it replaces, so delete has to be reachable
-- by whoever may write — not only by the uploader. A box whose picture nobody
-- but its first photographer could change would be a box with a wrong picture
-- on it forever.
create policy "box_photos_delete"
  on storage.objects for delete to authenticated
  using (
    bucket_id = 'box-photos'
    and exists (
      select 1 from public.boxes b
       where b.id::text = (storage.foldername(name))[1]
         and private.can_write_box(b.id)
    )
  );

create policy "list_attachments_read"
  on storage.objects for select to authenticated
  using (
    bucket_id = 'list-attachments'
    and exists (
      select 1 from public.lists l
       where l.id::text = (storage.foldername(name))[1]
         and private.can_read_list(l.id)
    )
  );

create policy "list_attachments_write"
  on storage.objects for insert to authenticated
  with check (
    bucket_id = 'list-attachments'
    and exists (
      select 1 from public.lists l
       where l.id::text = (storage.foldername(name))[1]
         and private.can_write_list(l.id)
    )
  );

create policy "list_attachments_delete"
  on storage.objects for delete to authenticated
  using (
    bucket_id = 'list-attachments'
    and exists (
      select 1 from public.lists l
       where l.id::text = (storage.foldername(name))[1]
         and private.can_write_list(l.id)
    )
  );
