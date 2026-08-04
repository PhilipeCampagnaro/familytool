-- The 17 predicates behind every RLS policy were reachable over the REST API as
-- /rest/v1/rpc/<name>, because PostgREST exposes everything in `public` and they
-- are `security definer`. None of them takes an "act as somebody else" argument
-- — `can_read_list(uuid)` answers about the caller — so the exposure was an
-- oracle rather than a hole. It is still an oracle nobody asked for.
--
-- Revoking EXECUTE is not the fix: an RLS policy expression is evaluated as the
-- querying role, so `authenticated` losing EXECUTE would take every policy in
-- the database down with it. Moving them out of the exposed schema keeps the
-- policies working and takes the URL away.
--
-- The order matters. `ALTER FUNCTION ... SET SCHEMA` **preserves the OID**, and
-- pg_policy stores parsed expressions by OID — so the ~50 policies referencing
-- these keep working without being touched at all. `CREATE OR REPLACE` also
-- preserves the OID, which is what lets step 3 repoint the bodies (they call
-- each other by qualified name, since `search_path` is empty) without any policy
-- noticing. Recreating the functions under new OIDs would have meant rewriting
-- every policy, which is the version of this change that goes wrong.

create schema if not exists private;

-- Not granted to `anon`: nothing anonymous evaluates a policy, and the smaller
-- the surface the better.
grant usage on schema private to authenticated, service_role;

-- 1. Move (OIDs, ACLs and dependent policies all survive).
alter function public.can_edit_guest(public.shareable_kind, uuid)     set schema private;
alter function public.can_read_box(uuid)                              set schema private;
alter function public.can_read_calendar(uuid)                         set schema private;
alter function public.can_read_list(uuid)                             set schema private;
alter function public.can_read_shareable(public.shareable_kind, uuid) set schema private;
alter function public.can_read_task(uuid)                             set schema private;
alter function public.can_see_profile(uuid)                           set schema private;
alter function public.can_write_box(uuid)                             set schema private;
alter function public.can_write_calendar(uuid)                        set schema private;
alter function public.can_write_list(uuid)                            set schema private;
alter function public.can_write_task(uuid)                            set schema private;
alter function public.is_admin()                                      set schema private;
alter function public.is_guest_of(public.shareable_kind, uuid)        set schema private;
alter function public.my_family_id()                                  set schema private;
alter function public.my_role()                                       set schema private;
alter function public.owns_shareable(public.shareable_kind, uuid)     set schema private;
alter function public.shareable_family_id(public.shareable_kind, uuid) set schema private;

-- 2. Repoint the bodies. Identical logic; only the schema of the inner calls
--    changes. Leaf functions (no helper calls) are skipped — nothing in them
--    moved.

CREATE OR REPLACE FUNCTION private.can_read_box(p_box_id uuid)
 RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO ''
AS $function$
  select exists (
    select 1 from public.boxes b where b.id = p_box_id and (
      ( b.family_id = private.my_family_id()
        and ( b.visibility = 'family'
           or b.owner_id = (select auth.uid())
           or ( b.visibility = 'custom' and exists (
                  select 1 from public.box_shares s
                   where s.box_id = b.id and s.user_id = (select auth.uid())))))
      or private.is_guest_of('box', b.id)
    )
  );
$function$;

CREATE OR REPLACE FUNCTION private.can_read_calendar(p_calendar_id uuid)
 RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO ''
AS $function$
  select exists (
    select 1 from public.calendars c
     where c.id = p_calendar_id
       and c.family_id = private.my_family_id()
       and ( c.visibility = 'family'
          or c.owner_id = (select auth.uid())
          or ( c.visibility = 'custom' and exists (
                 select 1 from public.calendar_shares s
                  where s.calendar_id = c.id and s.user_id = (select auth.uid()))))
  );
$function$;

CREATE OR REPLACE FUNCTION private.can_read_list(p_list_id uuid)
 RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO ''
AS $function$
  select exists (
    select 1 from public.lists l where l.id = p_list_id and (
      ( l.family_id = private.my_family_id()
        and ( l.visibility = 'family'
           or l.owner_id = (select auth.uid())
           or ( l.visibility = 'custom' and exists (
                  select 1 from public.list_shares s
                   where s.list_id = l.id and s.user_id = (select auth.uid())))))
      or private.is_guest_of('list', l.id)
    )
  );
$function$;

CREATE OR REPLACE FUNCTION private.can_read_task(p_task_id uuid)
 RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO ''
AS $function$
  select exists (
    select 1 from public.tasks t where t.id = p_task_id and (
      ( t.family_id = private.my_family_id()
        and ( t.visibility = 'family'
           or t.owner_id = (select auth.uid())
           or ( t.visibility = 'custom' and exists (
                  select 1 from public.task_shares s
                   where s.task_id = t.id and s.user_id = (select auth.uid())))))
      or private.is_guest_of('task', t.id)
    )
  );
$function$;

CREATE OR REPLACE FUNCTION private.can_read_shareable(p_kind public.shareable_kind, p_resource_id uuid)
 RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO ''
AS $function$
  select case p_kind
           when 'list' then private.can_read_list(p_resource_id)
           when 'box'  then private.can_read_box(p_resource_id)
           when 'task' then private.can_read_task(p_resource_id)
         end;
$function$;

CREATE OR REPLACE FUNCTION private.can_see_profile(p_user_id uuid)
 RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO ''
AS $function$
  select
    p_user_id = (select auth.uid())
    or exists (select 1 from public.family_members m
                where m.user_id = p_user_id and m.family_id = private.my_family_id())
    or exists (select 1 from public.guest_access g
                where g.user_id = p_user_id
                  and private.can_read_shareable(g.resource_kind, g.resource_id))
    or exists (
         select 1 from public.guest_access g
          where g.user_id = (select auth.uid())
            and (
              (g.resource_kind = 'list' and exists (
                 select 1 from public.lists l where l.id = g.resource_id
                  and ( l.owner_id = p_user_id
                        or exists (select 1 from public.list_items i
                                    where i.list_id = l.id
                                      and p_user_id in (i.created_by, i.assignee_id, i.done_by)))))
              or (g.resource_kind = 'box' and exists (
                 select 1 from public.boxes b where b.id = g.resource_id
                  and ( b.owner_id = p_user_id
                        or exists (select 1 from public.box_items bi
                                    where bi.box_id = b.id and bi.created_by = p_user_id))))
              or (g.resource_kind = 'task' and exists (
                 select 1 from public.tasks t where t.id = g.resource_id
                  and p_user_id in (t.owner_id, t.assignee_id, t.done_by)))
            )
       );
$function$;

CREATE OR REPLACE FUNCTION private.can_write_box(p_box_id uuid)
 RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO ''
AS $function$
  select private.can_read_box(p_box_id)
     and ( exists (select 1 from public.boxes b where b.id = p_box_id and b.family_id = private.my_family_id())
           or private.can_edit_guest('box', p_box_id) );
$function$;

CREATE OR REPLACE FUNCTION private.can_write_calendar(p_calendar_id uuid)
 RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO ''
AS $function$
  select private.can_read_calendar(p_calendar_id)
     and not exists (select 1 from public.calendars c where c.id = p_calendar_id and c.is_read_only);
$function$;

CREATE OR REPLACE FUNCTION private.can_write_list(p_list_id uuid)
 RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO ''
AS $function$
  select private.can_read_list(p_list_id)
     and ( exists (select 1 from public.lists l where l.id = p_list_id and l.family_id = private.my_family_id())
           or private.can_edit_guest('list', p_list_id) );
$function$;

CREATE OR REPLACE FUNCTION private.can_write_task(p_task_id uuid)
 RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO ''
AS $function$
  select private.can_read_task(p_task_id)
     and ( exists (select 1 from public.tasks t where t.id = p_task_id and t.family_id = private.my_family_id())
           or private.can_edit_guest('task', p_task_id) );
$function$;

CREATE OR REPLACE FUNCTION private.is_admin()
 RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO ''
AS $function$
  select coalesce(private.my_role() = 'admin', false);
$function$;

-- 3. The two functions that stay in `public` — both are called by name from an
--    Edge Function or a trigger — and reference a helper that moved.

CREATE OR REPLACE FUNCTION public.may_share_externally(p_kind public.shareable_kind, p_resource_id uuid, p_user_id uuid)
 RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO ''
AS $function$
  select exists (
    select 1 from public.family_members m
     where m.user_id = p_user_id
       and m.role in ('admin', 'member')
       and m.family_id = private.shareable_family_id(p_kind, p_resource_id)
  );
$function$;

CREATE OR REPLACE FUNCTION public.enforce_share_link_author()
 RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
AS $function$
begin
  if (select m.role from public.family_members m where m.user_id = new.created_by) = 'kid' then
    raise exception 'Kinder können keine externen Freigabe-Links erstellen.'
      using errcode = 'check_violation';
  end if;

  if private.shareable_family_id(new.resource_kind, new.resource_id) is distinct from new.family_id then
    raise exception 'Der Freigabe-Link gehört nicht zum Haushalt der Ressource.'
      using errcode = 'check_violation';
  end if;
  return new;
end;
$function$;
