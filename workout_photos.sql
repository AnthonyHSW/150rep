-- Workout photo metadata.
--
-- NOTE ON session_id: the original spec declared this as
--     session_id uuid references public.workout_sessions(id) on delete cascade
-- but there is no `workout_sessions` table in this project — workout sessions live only in
-- the app's local SwiftData store and are never written to Postgres. That foreign key, and
-- the RLS policy that joined through it, would both fail on creation.
--
-- So `session_id` is kept as a plain uuid (the on-device session id, used to group a
-- workout's photos) and ownership is carried directly on the row via `user_id`. If workout
-- sessions are ever synced to Postgres, this can become a real foreign key.

create table if not exists public.workout_photos (
    id uuid primary key default gen_random_uuid(),
    user_id uuid not null default auth.uid()
        references auth.users (id) on delete cascade,
    session_id uuid not null,
    storage_path text not null,
    public_url text not null,
    order_index integer not null,
    created_at timestamptz not null default now()
);

create index if not exists workout_photos_user_session_idx
    on public.workout_photos (user_id, session_id, order_index);

alter table public.workout_photos enable row level security;

-- Ownership is read off the row rather than derived from a sessions table. `with check`
-- matters as much as `using` here: without it a client could insert rows owned by someone
-- else, since the app supplies every column but user_id.
drop policy if exists "Users manage own workout photos" on public.workout_photos;

create policy "Users manage own workout photos"
    on public.workout_photos for all
    to authenticated
    using (user_id = auth.uid())
    with check (user_id = auth.uid());


-- Storage bucket: public so `getPublicURL` resolves, 5 MB cap, JPEG only.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('workout-photos', 'workout-photos', true, 5242880, array['image/jpeg'])
on conflict (id) do update
    set public = excluded.public,
        file_size_limit = excluded.file_size_limit,
        allowed_mime_types = excluded.allowed_mime_types;

-- Objects are uploaded as `{user_id}/{session_id}/{photo_id}.jpg`, so the first path segment
-- identifies the owner. Without this policy the uploads are rejected: storage.objects has RLS
-- on by default, and a public bucket grants read access only, never write.
--
-- The segment is compared case-insensitively. This is a text comparison, not a uuid one, so
-- the two sides have to agree on spelling: `auth.uid()::text` is lowercase, while the hex a
-- client prints may not be (Foundation's `UUID.uuidString` is uppercase). A case-sensitive
-- comparison turns that mismatch into a 403 on upload, which reads as an auth problem and
-- isn't one. Folding both sides keeps a build that spells it either way working.
drop policy if exists "Users manage own workout photo files" on storage.objects;

create policy "Users manage own workout photo files"
    on storage.objects for all
    to authenticated
    using (
        bucket_id = 'workout-photos'
        and lower((storage.foldername(name))[1]) = auth.uid()::text
    )
    with check (
        bucket_id = 'workout-photos'
        and lower((storage.foldername(name))[1]) = auth.uid()::text
    );
