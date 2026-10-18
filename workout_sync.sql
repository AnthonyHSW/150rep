-- Workout sync schema: sessions, exercises, and sets, plus the foreign key that finally
-- gives workout_photos.session_id something to point at.
--
-- Run once in the Supabase SQL editor. Every statement is idempotent, so re-running is
-- safe. Full rationale lives in 150repMDs/workout-sync.md.
--
-- Primary keys are supplied by the client, not generated here: the SwiftData models already
-- carry stable UUIDs, and reusing them is what makes re-syncing idempotent — each write is
-- an upsert on a key the device already owns, so a retry after a partial failure overwrites
-- instead of duplicating.
--
-- user_id is denormalized onto every table rather than joined back through the session,
-- the same call workout_photos made, and for the same reason: it keeps each RLS policy a
-- direct comparison instead of a subquery against a parent table.

-- =============================================================================
-- 1. Tables
-- =============================================================================

create table if not exists public.workout_sessions (
    id uuid primary key,
    user_id uuid not null default auth.uid()
        references auth.users (id) on delete cascade,
    title text not null,
    start_time timestamptz not null,
    end_time timestamptz,
    status text not null check (status in ('active', 'completed', 'discarded')),
    notes text,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now()
);

create table if not exists public.exercise_logs (
    id uuid primary key,
    session_id uuid not null
        references public.workout_sessions (id) on delete cascade,
    user_id uuid not null default auth.uid()
        references auth.users (id) on delete cascade,
    exercise_id text not null,
    name text not null,
    primary_muscle text not null,
    image_name text not null default '',
    order_index integer not null,
    notes text
);

create table if not exists public.exercise_sets (
    id uuid primary key,
    exercise_log_id uuid not null
        references public.exercise_logs (id) on delete cascade,
    user_id uuid not null default auth.uid()
        references auth.users (id) on delete cascade,
    set_number integer not null,
    set_type text not null check (set_type in ('W', 'N', 'D', 'F')),
    weight double precision not null default 0,
    reps integer not null default 0,
    is_completed boolean not null default false,
    completed_at timestamptz
);

-- `status` mirrors SessionStatus and `set_type` mirrors SetType, both stored as the raw
-- strings the Swift enums already encode. The check constraints are what stops a rename on
-- one side from silently writing values the other can't read.

create index if not exists workout_sessions_user_start_idx
    on public.workout_sessions (user_id, start_time desc);
create index if not exists exercise_logs_session_order_idx
    on public.exercise_logs (session_id, order_index);
create index if not exists exercise_sets_log_number_idx
    on public.exercise_sets (exercise_log_id, set_number);

-- =============================================================================
-- 2. Connect photos to their sessions
-- =============================================================================

-- `not valid` enforces this on new and updated rows while leaving existing ones unchecked,
-- so no pre-existing photo is deleted by adding it. Promote it once every historical photo
-- has a session row:
--
--     alter table public.workout_photos
--         validate constraint workout_photos_session_id_fkey;
--
-- If that errors, orphans remain; find them with:
--
--     select p.id, p.session_id, p.created_at
--     from public.workout_photos p
--     where not exists (
--         select 1 from public.workout_sessions s where s.id = p.session_id
--     );
--
-- This foreign key also imposes an ordering on the client: a session row must exist before
-- its photos are inserted. WorkoutSyncService already syncs photos last.
do $$
begin
    if not exists (
        select 1 from pg_constraint
        where conname = 'workout_photos_session_id_fkey'
    ) then
        alter table public.workout_photos
            add constraint workout_photos_session_id_fkey
            foreign key (session_id) references public.workout_sessions (id)
            on delete cascade
            not valid;
    end if;
end
$$;

-- =============================================================================
-- 3. Row-level security
-- =============================================================================

alter table public.workout_sessions enable row level security;
alter table public.exercise_logs    enable row level security;
alter table public.exercise_sets    enable row level security;

-- `with check` matters as much as `using`: without it a client could insert rows owned by
-- somebody else, since the app supplies every column but user_id.
--
-- The ilike clause is the @uci.edu rule restated. It matches is_uci_email in api.py — the
-- domain must be exactly uci.edu, so someone@grad.uci.edu is rejected by both. It sits in
-- `with check` only, so a user who somehow has rows can still read them but cannot write
-- new ones.

drop policy if exists "Users manage own workout sessions" on public.workout_sessions;
create policy "Users manage own workout sessions"
    on public.workout_sessions for all
    to authenticated
    using (user_id = auth.uid())
    with check (
        user_id = auth.uid()
        and coalesce(auth.jwt() ->> 'email', '') ilike '%@uci.edu'
    );

drop policy if exists "Users manage own exercise logs" on public.exercise_logs;
create policy "Users manage own exercise logs"
    on public.exercise_logs for all
    to authenticated
    using (user_id = auth.uid())
    with check (
        user_id = auth.uid()
        and coalesce(auth.jwt() ->> 'email', '') ilike '%@uci.edu'
    );

drop policy if exists "Users manage own exercise sets" on public.exercise_sets;
create policy "Users manage own exercise sets"
    on public.exercise_sets for all
    to authenticated
    using (user_id = auth.uid())
    with check (
        user_id = auth.uid()
        and coalesce(auth.jwt() ->> 'email', '') ilike '%@uci.edu'
    );

-- =============================================================================
-- 4. Keep updated_at honest
-- =============================================================================

-- Last-write-wins is the conflict policy and the client is the writer, so this has to be
-- set server-side or it only records whatever the device claims.

create or replace function public.touch_updated_at()
returns trigger language plpgsql as $$
begin
    new.updated_at := now();
    return new;
end;
$$;

drop trigger if exists workout_sessions_touch_updated_at on public.workout_sessions;
create trigger workout_sessions_touch_updated_at
    before update on public.workout_sessions
    for each row execute function public.touch_updated_at();

-- =============================================================================
-- 5. Refresh the PostgREST schema cache
-- =============================================================================

-- Without this the API keeps answering PGRST205 ("Could not find the table ... in the
-- schema cache") until it reloads on its own.
notify pgrst, 'reload schema';
