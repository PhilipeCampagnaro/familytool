-- ---------------------------------------------------------------------------
-- An article can point at where to buy it
--
-- The attach menu already offered a photo, a camera and a file, which covers
-- the receipt and the manual and the picture of the shelf — and missed the one
-- thing a shopping list is most often about: the product page. A family that
-- has agreed on *which* Bohrmaschine has agreed on a URL, and re-finding it
-- from the word "Bohrmaschine" a week later at the shop is the whole problem.
--
-- A **column, not a row in `list_item_attachments`**. That table is "one object
-- in the private `list-attachments` bucket" all the way down — every path
-- through it signs, copies and deletes a storage object — and a link has no
-- object, so a row there would be a row whose `storage_path` lies. It is also
-- one link per article rather than a list of them, for the same reason a box
-- gets one photograph: a second link to the same article is a second opinion
-- about it, and an article the household has two opinions about is two
-- articles.
--
-- **Not a URL we ever fetch.** Nothing server-side opens it, nothing renders a
-- preview of it, no title or picture is scraped off it — it is handed to
-- `UIApplication.open` and that is all. So there is no third party learning
-- what a household is shopping for, and no copy of somebody's shop page in our
-- database.
--
-- The check is deliberately shallow: a scheme we are willing to hand to the OS
-- and a sane length. Anything stricter would be this database having opinions
-- about URLs, which ages badly; the client normalises a pasted `amazon.de/...`
-- into `https://` before it ever gets here.
--
-- No policy touched: an additive nullable column on a table whose RLS is
-- row-shaped needs none.
-- ---------------------------------------------------------------------------

alter table public.list_items
  add column if not exists link_url text;

alter table public.list_items
  drop constraint if exists list_items_link_url_shape;

alter table public.list_items
  add constraint list_items_link_url_shape
  check (
    link_url is null
    or (link_url ~* '^https?://.' and length(link_url) between 8 and 2000)
  );

comment on column public.list_items.link_url is
  'Optional http(s) link to the product/page this article is about. Opened by the device, never fetched by us — no preview, no title, no scrape.';
