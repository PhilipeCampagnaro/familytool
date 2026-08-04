-- Aporah backend — function-level grants.
--
-- Supabase grants EXECUTE on every function in `public` to anon and
-- authenticated, which publishes each one at /rest/v1/rpc/<name>. None of these
-- are meant to be called directly, so the grants are withdrawn to whatever each
-- one actually needs. Found by `get_advisors` after the first deploy.

-- The one function that missed `set search_path` when it was written.
create or replace function public.touch_updated_at()
returns trigger language plpgsql set search_path = '' as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

-- Trigger functions lose both grants: PostgreSQL does not check EXECUTE when
-- firing a trigger, so revoking costs nothing and takes them off the API.
revoke all on function public.touch_updated_at() from public, anon, authenticated;
revoke all on function public.handle_new_user() from public, anon, authenticated;
revoke all on function public.enforce_last_admin() from public, anon, authenticated;
revoke all on function public.enforce_membership_immutable() from public, anon, authenticated;
revoke all on function public.rehome_removed_member() from public, anon, authenticated;
revoke all on function public.enforce_container_ownership() from public, anon, authenticated;
revoke all on function public.reassign_content_on_member_removal() from public, anon, authenticated;
revoke all on function public.enforce_share_link_author() from public, anon, authenticated;
revoke all on function public.revoke_link_guests() from public, anon, authenticated;
revoke all on function public.cleanup_guest_access() from public, anon, authenticated;

-- Only ever called by accept_family_invite, which runs as service_role.
revoke all on function public.next_free_tone(uuid) from public, anon, authenticated;
grant execute on function public.next_free_tone(uuid) to service_role;

-- The policy helpers keep EXECUTE for `authenticated`: RLS evaluates them as
-- the querying role, so revoking it would deny every read in the app. They lose
-- `anon`, which has no business reaching them — nothing in Aporah is public.
--
-- They remain reachable at /rest/v1/rpc/<name> by a signed-in user, which the
-- linter still flags (0029). Each one only ever answers about the caller's own
-- access, so the disclosure is bounded to an existence oracle on ids the caller
-- already holds. The real fix is moving them into a schema PostgREST does not
-- expose; that means rewriting every body, since LANGUAGE sql bodies are stored
-- as text and their `public.`-qualified calls would not follow the move.
revoke all on function public.my_family_id() from public, anon;
revoke all on function public.my_role() from public, anon;
revoke all on function public.is_admin() from public, anon;
revoke all on function public.can_see_profile(uuid) from public, anon;
revoke all on function public.is_guest_of(public.shareable_kind, uuid) from public, anon;
revoke all on function public.can_edit_guest(public.shareable_kind, uuid) from public, anon;
revoke all on function public.can_read_shareable(public.shareable_kind, uuid) from public, anon;
revoke all on function public.owns_shareable(public.shareable_kind, uuid) from public, anon;
revoke all on function public.shareable_family_id(public.shareable_kind, uuid) from public, anon;
revoke all on function public.can_read_list(uuid) from public, anon;
revoke all on function public.can_read_box(uuid) from public, anon;
revoke all on function public.can_read_task(uuid) from public, anon;
revoke all on function public.can_read_calendar(uuid) from public, anon;
revoke all on function public.can_write_list(uuid) from public, anon;
revoke all on function public.can_write_box(uuid) from public, anon;
revoke all on function public.can_write_task(uuid) from public, anon;
revoke all on function public.can_write_calendar(uuid) from public, anon;

grant execute on function public.my_family_id() to authenticated;
grant execute on function public.my_role() to authenticated;
grant execute on function public.is_admin() to authenticated;
grant execute on function public.can_see_profile(uuid) to authenticated;
grant execute on function public.is_guest_of(public.shareable_kind, uuid) to authenticated;
grant execute on function public.can_edit_guest(public.shareable_kind, uuid) to authenticated;
grant execute on function public.can_read_shareable(public.shareable_kind, uuid) to authenticated;
grant execute on function public.owns_shareable(public.shareable_kind, uuid) to authenticated;
grant execute on function public.shareable_family_id(public.shareable_kind, uuid) to authenticated;
grant execute on function public.can_read_list(uuid) to authenticated;
grant execute on function public.can_read_box(uuid) to authenticated;
grant execute on function public.can_read_task(uuid) to authenticated;
grant execute on function public.can_read_calendar(uuid) to authenticated;
grant execute on function public.can_write_list(uuid) to authenticated;
grant execute on function public.can_write_box(uuid) to authenticated;
grant execute on function public.can_write_task(uuid) to authenticated;
grant execute on function public.can_write_calendar(uuid) to authenticated;
