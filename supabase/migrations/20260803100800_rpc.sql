-- Aporah backend — the two operations that must be atomic, and the one
-- authorisation check that cannot use auth.uid().
--
-- Joining a household is several statements that must all happen or none:
-- dissolve the old household, create the membership, recolour the avatar, close
-- the invite. supabase-js cannot open a transaction, so the logic lives here and
-- the Edge Function only hashes the token and calls in.
--
-- Every function here takes p_user_id rather than reading auth.uid(), because
-- the caller is service_role and auth.uid() is null there. That makes them
-- forgeable by anyone who can execute them, so execution is granted to
-- service_role alone — see the revokes at the bottom.

create or replace function public.accept_family_invite(
  p_token_hash text,
  p_user_id uuid
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_invite  public.family_invites;
  v_email   text;
  v_current uuid;
  v_others  integer;
  v_tone    smallint;
begin
  select * into v_invite
    from public.family_invites
   where token_hash = p_token_hash
     and status = 'pending'
   for update;

  if not found then
    raise exception 'Diese Einladung ist ungültig oder wurde bereits verwendet.'
      using errcode = 'check_violation';
  end if;

  if v_invite.expires_at <= now() then
    update public.family_invites set status = 'expired' where id = v_invite.id;
    raise exception 'Diese Einladung ist abgelaufen.'
      using errcode = 'check_violation';
  end if;

  -- The invite is bound to the address it was sent to. Forwarding the mail does
  -- not transfer it.
  select lower(u.email) into v_email from auth.users u where u.id = p_user_id;
  if v_email is distinct from lower(v_invite.email) then
    raise exception 'Diese Einladung wurde an eine andere E-Mail-Adresse gesendet.'
      using errcode = 'check_violation';
  end if;

  select m.family_id into v_current
    from public.family_members m
   where m.user_id = p_user_id;

  -- Already a member — accepting again is a no-op, not an error.
  if v_current = v_invite.family_id then
    update public.family_invites
       set status = 'accepted', accepted_at = now(), accepted_by = p_user_id
     where id = v_invite.id;
    return v_invite.family_id;
  end if;

  if v_current is not null then
    select count(*) into v_others
      from public.family_members m
     where m.family_id = v_current
       and m.user_id <> p_user_id;

    -- Dissolving a household that a spouse and children live in must never be a
    -- side effect of tapping a link in an e-mail.
    if v_others > 0 then
      raise exception 'Du bist noch Teil eines Haushalts mit anderen Mitgliedern. Verlasse ihn zuerst oder lass dich entfernen, bevor du einem anderen Haushalt beitrittst.'
        using errcode = 'check_violation';
    end if;

    -- Solo household: dissolve it. The FK cascade clears the membership and all
    -- content; enforce_last_admin and rehome_removed_member both stand aside
    -- because the families row is already gone by the time they run.
    delete from public.families where id = v_current;
  end if;

  -- Picked before the insert, so the new member's own (old) tone does not count
  -- as taken and push them onto a colour they did not need to move to.
  v_tone := public.next_free_tone(v_invite.family_id);

  insert into public.family_members (family_id, user_id, role)
  values (v_invite.family_id, p_user_id, v_invite.role);

  update public.profiles set tone = v_tone where id = p_user_id;

  update public.family_invites
     set status = 'accepted', accepted_at = now(), accepted_by = p_user_id
   where id = v_invite.id;

  return v_invite.family_id;
end;
$$;

create or replace function public.redeem_share_link(
  p_token_hash text,
  p_user_id uuid
)
returns table (resource_kind public.shareable_kind, resource_id uuid)
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_link public.share_links;
begin
  select * into v_link
    from public.share_links
   where token_hash = p_token_hash
   for update;

  if not found then
    raise exception 'Dieser Link ist ungültig.' using errcode = 'check_violation';
  end if;

  if v_link.revoked_at is not null then
    raise exception 'Dieser Link wurde widerrufen.' using errcode = 'check_violation';
  end if;

  if v_link.expires_at is not null and v_link.expires_at <= now() then
    raise exception 'Dieser Link ist abgelaufen.' using errcode = 'check_violation';
  end if;

  if v_link.max_uses is not null and v_link.use_count >= v_link.max_uses then
    raise exception 'Dieser Link wurde bereits vollständig genutzt.' using errcode = 'check_violation';
  end if;

  -- Someone from the owning household following their own link already has
  -- access through the household branch; granting them guest access on top
  -- would be noise in the Teilen sheet.
  if exists (
    select 1 from public.family_members m
     where m.user_id = p_user_id and m.family_id = v_link.family_id
  ) then
    return query select v_link.resource_kind, v_link.resource_id;
    return;
  end if;

  insert into public.guest_access (
    resource_kind, resource_id, user_id, can_edit, granted_via, invited_by
  )
  values (
    v_link.resource_kind, v_link.resource_id, p_user_id,
    v_link.can_edit, v_link.id, v_link.created_by
  )
  on conflict (resource_kind, resource_id, user_id)
    do update set can_edit = excluded.can_edit;

  update public.share_links set use_count = use_count + 1 where id = v_link.id;

  return query select v_link.resource_kind, v_link.resource_id;
  return;
end;
$$;

-- May this user hand a resource to someone outside the household at all?
--
-- Only the role and household question — whether they can *see* the resource is
-- checked separately, by the Edge Function reading it through the caller's own
-- JWT so that RLS answers it. Re-implementing the visibility predicate here
-- would create a second copy that could drift from can_read_*.
create or replace function public.may_share_externally(
  p_kind public.shareable_kind,
  p_resource_id uuid,
  p_user_id uuid
)
returns boolean
language sql
security definer
stable
set search_path = ''
as $$
  select exists (
    select 1
      from public.family_members m
     where m.user_id = p_user_id
       and m.role in ('admin', 'member')
       and m.family_id = public.shareable_family_id(p_kind, p_resource_id)
  );
$$;

-- These take a user id as an argument, so anyone able to execute them could act
-- as anyone else. service_role only — and service_role never ships in the app.
revoke all on function public.accept_family_invite(text, uuid) from public, anon, authenticated;
revoke all on function public.redeem_share_link(text, uuid) from public, anon, authenticated;
revoke all on function public.may_share_externally(public.shareable_kind, uuid, uuid)
  from public, anon, authenticated;

grant execute on function public.accept_family_invite(text, uuid) to service_role;
grant execute on function public.redeem_share_link(text, uuid) to service_role;
grant execute on function public.may_share_externally(public.shareable_kind, uuid, uuid) to service_role;
