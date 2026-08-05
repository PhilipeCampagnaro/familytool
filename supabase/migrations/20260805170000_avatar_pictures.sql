-- Profile pictures.
--
-- `profiles.avatar_url` has existed since the first migration and nothing ever
-- wrote it; this is the storage behind it.
--
-- **The bucket is private, and the column holds an object path, not a URL.** A
-- public bucket would be one line less code and would put a photo of somebody's
-- kid on an unauthenticated CDN URL that outlives the account — the same trade
-- this app already refused for the household address and for device GPS. The
-- client signs a URL per member at load time instead (one batched call), so a
-- picture is reachable only by somebody who could already read the profile.
--
-- Layout is `avatars/<user_id>/<uuid>.<ext>`: the owner is the first path
-- segment, which is what both the write policies and the read policy key on.

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'avatars',
  'avatars',
  false,
  5 * 1024 * 1024,
  array['image/jpeg', 'image/png', 'image/heic', 'image/heif', 'image/webp']
)
on conflict (id) do update set
  public             = excluded.public,
  file_size_limit    = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

-- Read: exactly the people who may read the profile row that points at the
-- picture — household members, plus the guest who is allowed to resolve the few
-- profiles named on a list shared with them.
--
-- Joined through `profiles` on text rather than casting the path segment to
-- uuid: a cast raises on a malformed name, and an object nobody can read must
-- fail closed, not error the whole query.
create policy "avatars_read_visible_profiles"
  on storage.objects for select to authenticated
  using (
    bucket_id = 'avatars'
    and exists (
      select 1 from public.profiles p
       where p.id::text = (storage.foldername(name))[1]
         and private.can_see_profile(p.id)
    )
  );

-- Write: your own folder, nobody else's. An admin has no business replacing
-- another member's face, so this is deliberately narrower than the role checks
-- everywhere else.
create policy "avatars_insert_own"
  on storage.objects for insert to authenticated
  with check (
    bucket_id = 'avatars'
    and (storage.foldername(name))[1] = (select auth.uid())::text
  );

create policy "avatars_update_own"
  on storage.objects for update to authenticated
  using (
    bucket_id = 'avatars'
    and (storage.foldername(name))[1] = (select auth.uid())::text
  )
  with check (
    bucket_id = 'avatars'
    and (storage.foldername(name))[1] = (select auth.uid())::text
  );

-- Replacing a picture deletes the old object, so this is on the normal path,
-- not just the "remove picture" one.
create policy "avatars_delete_own"
  on storage.objects for delete to authenticated
  using (
    bucket_id = 'avatars'
    and (storage.foldername(name))[1] = (select auth.uid())::text
  );

comment on column public.profiles.avatar_url is
  'Object path in the private `avatars` bucket (<user_id>/<uuid>.<ext>), not a URL. Null means the avatar falls back to the initials and the tone colour.';
