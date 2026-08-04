-- Aporah backend — RLS for content.
--
-- Same conventions as the identity policies: `to authenticated` everywhere,
-- `(select auth.uid())` never bare, one policy per command.
--
-- Reading is always delegated to a can_read_* predicate rather than inlined, so
-- a container and the rows inside it can never disagree about who may see them.

alter table public.lists                 enable row level security;
alter table public.list_shares           enable row level security;
alter table public.list_items            enable row level security;
alter table public.list_item_attachments enable row level security;
alter table public.boxes                 enable row level security;
alter table public.box_shares            enable row level security;
alter table public.box_items             enable row level security;
alter table public.tasks                 enable row level security;
alter table public.task_shares           enable row level security;
alter table public.calendars             enable row level security;
alter table public.calendar_shares       enable row level security;
alter table public.events                enable row level security;

-- ---------------------------------------------------------------------------
-- Listen
-- ---------------------------------------------------------------------------

create policy "lists_select" on public.lists for select to authenticated
  using (public.can_read_list(id));

-- You can only create a list in your own household, owned by you. A guest
-- creating a list therefore creates it at home, not in the household that
-- shared something with them.
create policy "lists_insert" on public.lists for insert to authenticated
  with check (
    family_id = public.my_family_id()
    and owner_id = (select auth.uid())
  );

create policy "lists_update" on public.lists for update to authenticated
  using (public.can_write_list(id))
  with check (public.can_write_list(id));

-- Deleting a whole list is the owner's call, or an admin's for tidying up.
-- An admin cannot reach a private list they were never able to see.
create policy "lists_delete" on public.lists for delete to authenticated
  using (
    public.can_read_list(id)
    and (
      owner_id = (select auth.uid())
      or (public.is_admin() and family_id = public.my_family_id())
    )
  );

create policy "list_shares_select" on public.list_shares for select to authenticated
  using (public.can_read_list(list_id));

create policy "list_shares_insert" on public.list_shares for insert to authenticated
  with check (
    exists (
      select 1 from public.lists l
       where l.id = list_id and l.owner_id = (select auth.uid())
    )
  );

create policy "list_shares_delete" on public.list_shares for delete to authenticated
  using (
    exists (
      select 1 from public.lists l
       where l.id = list_id and l.owner_id = (select auth.uid())
    )
  );

create policy "list_items_select" on public.list_items for select to authenticated
  using (public.can_read_list(list_id));

create policy "list_items_insert" on public.list_items for insert to authenticated
  with check (
    public.can_write_list(list_id)
    and created_by = (select auth.uid())
  );

create policy "list_items_update" on public.list_items for update to authenticated
  using (public.can_write_list(list_id))
  with check (public.can_write_list(list_id));

-- Your own items, always. Other people's items only as an admin of the
-- household that owns the list — which excludes guests, who are admins of their
-- own household but not of this one.
create policy "list_items_delete" on public.list_items for delete to authenticated
  using (
    public.can_write_list(list_id)
    and (
      created_by = (select auth.uid())
      or (
        public.is_admin()
        and exists (
          select 1 from public.lists l
           where l.id = list_id and l.family_id = public.my_family_id()
        )
      )
    )
  );

create policy "list_item_attachments_select" on public.list_item_attachments for select to authenticated
  using (
    exists (
      select 1 from public.list_items i
       where i.id = item_id and public.can_read_list(i.list_id)
    )
  );

create policy "list_item_attachments_insert" on public.list_item_attachments for insert to authenticated
  with check (
    created_by = (select auth.uid())
    and exists (
      select 1 from public.list_items i
       where i.id = item_id and public.can_write_list(i.list_id)
    )
  );

create policy "list_item_attachments_delete" on public.list_item_attachments for delete to authenticated
  using (
    created_by = (select auth.uid())
    and exists (
      select 1 from public.list_items i
       where i.id = item_id and public.can_write_list(i.list_id)
    )
  );

-- ---------------------------------------------------------------------------
-- Box
-- ---------------------------------------------------------------------------

create policy "boxes_select" on public.boxes for select to authenticated
  using (public.can_read_box(id));

create policy "boxes_insert" on public.boxes for insert to authenticated
  with check (
    family_id = public.my_family_id()
    and owner_id = (select auth.uid())
  );

create policy "boxes_update" on public.boxes for update to authenticated
  using (public.can_write_box(id))
  with check (public.can_write_box(id));

create policy "boxes_delete" on public.boxes for delete to authenticated
  using (
    public.can_read_box(id)
    and (
      owner_id = (select auth.uid())
      or (public.is_admin() and family_id = public.my_family_id())
    )
  );

create policy "box_shares_select" on public.box_shares for select to authenticated
  using (public.can_read_box(box_id));

create policy "box_shares_insert" on public.box_shares for insert to authenticated
  with check (
    exists (select 1 from public.boxes b where b.id = box_id and b.owner_id = (select auth.uid()))
  );

create policy "box_shares_delete" on public.box_shares for delete to authenticated
  using (
    exists (select 1 from public.boxes b where b.id = box_id and b.owner_id = (select auth.uid()))
  );

create policy "box_items_select" on public.box_items for select to authenticated
  using (public.can_read_box(box_id));

create policy "box_items_insert" on public.box_items for insert to authenticated
  with check (
    public.can_write_box(box_id)
    and created_by = (select auth.uid())
  );

create policy "box_items_update" on public.box_items for update to authenticated
  using (public.can_write_box(box_id))
  with check (public.can_write_box(box_id));

create policy "box_items_delete" on public.box_items for delete to authenticated
  using (
    public.can_write_box(box_id)
    and (
      created_by = (select auth.uid())
      or (
        public.is_admin()
        and exists (
          select 1 from public.boxes b
           where b.id = box_id and b.family_id = public.my_family_id()
        )
      )
    )
  );

-- ---------------------------------------------------------------------------
-- Board
-- ---------------------------------------------------------------------------

create policy "tasks_select" on public.tasks for select to authenticated
  using (public.can_read_task(id));

create policy "tasks_insert" on public.tasks for insert to authenticated
  with check (
    family_id = public.my_family_id()
    and owner_id = (select auth.uid())
  );

-- Ticking off someone else's chore is normal family behaviour and stays
-- allowed; enforce_container_ownership still keeps visibility and ownership out
-- of reach for everyone but the owner.
create policy "tasks_update" on public.tasks for update to authenticated
  using (public.can_write_task(id))
  with check (public.can_write_task(id));

create policy "tasks_delete" on public.tasks for delete to authenticated
  using (
    public.can_read_task(id)
    and (
      owner_id = (select auth.uid())
      or (public.is_admin() and family_id = public.my_family_id())
    )
  );

create policy "task_shares_select" on public.task_shares for select to authenticated
  using (public.can_read_task(task_id));

create policy "task_shares_insert" on public.task_shares for insert to authenticated
  with check (
    exists (select 1 from public.tasks t where t.id = task_id and t.owner_id = (select auth.uid()))
  );

create policy "task_shares_delete" on public.task_shares for delete to authenticated
  using (
    exists (select 1 from public.tasks t where t.id = task_id and t.owner_id = (select auth.uid()))
  );

-- ---------------------------------------------------------------------------
-- Kalender
-- ---------------------------------------------------------------------------

create policy "calendars_select" on public.calendars for select to authenticated
  using (public.can_read_calendar(id));

create policy "calendars_insert" on public.calendars for insert to authenticated
  with check (
    family_id = public.my_family_id()
    and owner_id = (select auth.uid())
  );

create policy "calendars_update" on public.calendars for update to authenticated
  using (
    public.can_read_calendar(id)
    and (owner_id = (select auth.uid()) or public.is_admin())
  )
  with check (
    public.can_read_calendar(id)
    and (owner_id = (select auth.uid()) or public.is_admin())
  );

create policy "calendars_delete" on public.calendars for delete to authenticated
  using (
    public.can_read_calendar(id)
    and (
      owner_id = (select auth.uid())
      or (public.is_admin() and family_id = public.my_family_id())
    )
  );

create policy "calendar_shares_select" on public.calendar_shares for select to authenticated
  using (public.can_read_calendar(calendar_id));

create policy "calendar_shares_insert" on public.calendar_shares for insert to authenticated
  with check (
    exists (
      select 1 from public.calendars c
       where c.id = calendar_id and c.owner_id = (select auth.uid())
    )
  );

create policy "calendar_shares_delete" on public.calendar_shares for delete to authenticated
  using (
    exists (
      select 1 from public.calendars c
       where c.id = calendar_id and c.owner_id = (select auth.uid())
    )
  );

create policy "events_select" on public.events for select to authenticated
  using (public.can_read_calendar(calendar_id));

-- can_write_calendar refuses read-only calendars, so a synced Ferien or Abfall
-- feed cannot be written to from the app.
create policy "events_insert" on public.events for insert to authenticated
  with check (
    public.can_write_calendar(calendar_id)
    and created_by = (select auth.uid())
  );

create policy "events_update" on public.events for update to authenticated
  using (public.can_write_calendar(calendar_id))
  with check (public.can_write_calendar(calendar_id));

create policy "events_delete" on public.events for delete to authenticated
  using (
    public.can_write_calendar(calendar_id)
    and (
      created_by = (select auth.uid())
      or (
        public.is_admin()
        and exists (
          select 1 from public.calendars c
           where c.id = calendar_id and c.family_id = public.my_family_id()
        )
      )
    )
  );
