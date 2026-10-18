-- Gym machines and their current status.
--
-- Status lives on the machine row rather than in a log table: every endpoint here asks
-- "what is it doing now", and a single row answers that without a per-machine subquery.
-- If usage history is ever wanted — occupancy over a day, say — this becomes a
-- `machine_status_events` table and `machines` keeps a denormalized latest pointer.

CREATE TABLE IF NOT EXISTS public.machines (
    id SERIAL PRIMARY KEY,
    name TEXT NOT NULL UNIQUE,
    location TEXT,
    is_in_use BOOLEAN NOT NULL DEFAULT FALSE,
    -- Null until somebody first reports on it, which is how "never reported" is told
    -- apart from "reported as free".
    status_updated_at TIMESTAMPTZ,
    status_updated_by INTEGER REFERENCES public.users(id) ON DELETE SET NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- The list endpoint orders by location then name so machines arrive grouped by room.
CREATE INDEX IF NOT EXISTS machines_location_name_idx
    ON public.machines (location, name);
