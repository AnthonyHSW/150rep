-- Active Workouts: lets every signed-in user watch the workouts happening right now.
--
-- Run once in the Supabase SQL editor, after workout_sync.sql. Every statement is
-- idempotent, so re-running is safe.
--
-- Two things are missing before a workout can be watched. The first is that an in-progress
-- session never reached the server at all: WorkoutSyncService only pushed a workout once it
-- was finished, so there was nothing live to read. The client now republishes an open
-- session on a timer, which is what `last_active_at` records.
--
-- The second is that the only policy on these tables is owner-scoped. A watcher is by
-- definition not the owner, so reading someone else's workout needs its own select policy —
-- the narrowest one that still makes the feature work: active sessions with a recent
-- heartbeat, and nothing else.
--
-- `last_active_at` is deliberately separate from `updated_at`. updated_at is touched by any
-- write, including the one that finishes or corrects a workout days later, so using it would
-- light up sessions nobody is actually doing. This column means one thing: the device had
-- this workout open on screen at that moment.

begin;

-- =============================================================================
-- 1. Columns
-- =============================================================================

-- owner_name and owner_avatar_url are denormalized onto the session rather than joined out
-- of auth.users, which is not readable by other users and shouldn't be. They're a snapshot
-- of what the publisher's own Google profile said when the workout was published, which is
-- all a watcher needs to put a face on a row. Both are nullable: an account without a
-- Google name or picture still has a workout worth showing, and the client falls back to
-- initials exactly as it does for the signed-in user's own avatar.
alter table public.workout_sessions
    add column if not exists owner_name text,
    add column if not exists owner_avatar_url text,
    add column if not exists last_active_at timestamptz;

-- Partial, because the live feed only ever asks about active sessions and they are a tiny
-- slice of the table — every finished workout ever recorded is the rest of it.
create index if not exists workout_sessions_live_idx
    on public.workout_sessions (last_active_at desc)
    where status = 'active';

-- =============================================================================
-- 2. What counts as live
-- =============================================================================

-- One definition, called by all three policies, so the window can't drift between them.
-- LiveWorkoutService.liveWindow mirrors this value on the client; it is the server's
-- number that decides what is readable, the client's only keeps it from asking for rows it
-- knows it can't have.
create or replace function public.live_workout_cutoff()
returns timestamptz
language sql
stable
as $$
    select now() - interval '10 minutes';
$$;

-- security definer on purpose. These run inside a policy on exercise_logs/exercise_sets and
-- have to see the parent row to judge it; as plain subqueries they would be filtered by the
-- very policies they exist to decide. Both are read-only, take a single id, and return a
-- boolean, so defining them this way exposes nothing beyond "is this row live" — and the
-- pinned search_path keeps a shadowing table on someone else's path out of it.
create or replace function public.is_live_workout(p_session_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
    select exists (
        select 1
        from public.workout_sessions s
        where s.id = p_session_id
          and s.status = 'active'
          and s.last_active_at > public.live_workout_cutoff()
    );
$$;

create or replace function public.is_live_exercise_log(p_log_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
    select exists (
        select 1
        from public.exercise_logs l
        join public.workout_sessions s on s.id = l.session_id
        where l.id = p_log_id
          and s.status = 'active'
          and s.last_active_at > public.live_workout_cutoff()
    );
$$;

-- Supabase grants function execution to PUBLIC by default. These helpers are used by
-- authenticated RLS policies, so limit direct invocation to that role.
revoke all on function public.live_workout_cutoff() from public, anon;
revoke all on function public.is_live_workout(uuid) from public, anon;
revoke all on function public.is_live_exercise_log(uuid) from public, anon;
grant execute on function public.live_workout_cutoff() to authenticated;
grant execute on function public.is_live_workout(uuid) to authenticated;
grant execute on function public.is_live_exercise_log(uuid) to authenticated;

-- =============================================================================
-- 3. Read policies for watchers
-- =============================================================================

-- Permissive policies, so each of these is OR'd with the owner policy already on the table
-- rather than narrowing it: the owner keeps full access to their own rows, and everybody
-- else gains read access to the live ones. They are `for select` only — nobody but the
-- owner can write a workout, and the owner policy's `using (user_id = auth.uid())` is still
-- the only thing that admits an update or a delete.

drop policy if exists "Anyone can watch live workouts" on public.workout_sessions;
create policy "Anyone can watch live workouts"
    on public.workout_sessions for select
    to authenticated
    using (
        status = 'active'
        and last_active_at > public.live_workout_cutoff()
    );

drop policy if exists "Anyone can watch live workout exercises" on public.exercise_logs;
create policy "Anyone can watch live workout exercises"
    on public.exercise_logs for select
    to authenticated
    using (public.is_live_workout(session_id));

drop policy if exists "Anyone can watch live workout sets" on public.exercise_sets;
create policy "Anyone can watch live workout sets"
    on public.exercise_sets for select
    to authenticated
    using (public.is_live_exercise_log(exercise_log_id));

-- Photos are left out. The feed shows what someone is lifting right now, which is the
-- exercises and sets; the photos on a session are a different kind of thing to publish to
-- strangers, and no policy here grants them.

-- =============================================================================
-- 4. Refresh the PostgREST schema cache
-- =============================================================================

-- The new columns are invisible to the API until it reloads, and a select naming them comes
-- back as PGRST204 in the meantime.
notify pgrst, 'reload schema';

commit;
