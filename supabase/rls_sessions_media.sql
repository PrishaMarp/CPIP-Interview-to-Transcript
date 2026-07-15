-- RLS for direct iOS → Supabase writes (sessions + media)
-- Run in the Supabase SQL editor.
--
-- Your schema has no user_id on sessions/media yet, so these policies allow any
-- authenticated user (including anonymous auth from the iOS app) to insert/read.
-- Enable Anonymous sign-ins: Authentication → Providers → Anonymous → Enable
--
-- When you add user_id (or use owned sessions), tighten these policies.

alter table sessions enable row level security;
alter table media enable row level security;

drop policy if exists "Authenticated can insert sessions" on sessions;
drop policy if exists "Authenticated can read sessions" on sessions;
drop policy if exists "Authenticated can insert media" on media;
drop policy if exists "Authenticated can read media" on media;

create policy "Authenticated can insert sessions"
on sessions for insert
to authenticated
with check (true);

create policy "Authenticated can read sessions"
on sessions for select
to authenticated
using (true);

create policy "Authenticated can insert media"
on media for insert
to authenticated
with check (true);

create policy "Authenticated can read media"
on media for select
to authenticated
using (true);

-- Webhook /extract typically runs as service role and bypasses RLS.
-- After media insert, configure a Database Webhook or Edge Function trigger
-- on media INSERT (e.g. when processing_status = 'pending') → Railway POST /extract.
