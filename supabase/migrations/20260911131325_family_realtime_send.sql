-- Let a household member *send* on their own channel.
--
-- The previous migration deliberately shipped without this, on the reasoning
-- that every message should come from the trigger. That reasoning did not
-- survive contact with the platform: `realtime.messages` is RANGE-partitioned on
-- `inserted_at` and this project has **no partitions**, so `realtime.send`
-- silently warns and drops every row it is handed — it catches its own insert
-- failure by design. A database-side broadcast therefore reaches nobody until
-- Supabase's Realtime service provisions those partitions, which it does on its
-- own schedule and which nothing in SQL can force.
--
-- So the client becomes the sender. A device that writes a list item also
-- broadcasts "lists changed" over the socket it is already holding, and the
-- Realtime server relays it to the household without it having to be stored.
-- The trigger stays where it is: it costs nothing while it is dropping messages,
-- it is the only thing that can announce a change no client made — `spend-ingest`
-- writing an Apple Pay transaction to a locked phone is exactly that — and it
-- starts working by itself the day partitions exist.
--
-- **What this gives up.** A member can now broadcast on their household's topic
-- without having written anything, so they could tell the family's other devices
-- that a list changed when it had not. The blast radius is their own household
-- and the cost is a wasted re-read; every one of those devices still reads
-- through RLS and learns nothing it could not already see. That is a fair price
-- for a feature that otherwise does not work at all.

create policy "aporah members send on their household channel"
on realtime.messages
for insert
to authenticated
with check (
  (select realtime.topic()) = 'family:' || (select private.my_family_id())::text
  and realtime.messages.extension = 'broadcast'
);
