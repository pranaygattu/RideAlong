-- Let the app save its profile with one idempotent upsert (safe to retry after a dropped response).
-- Upsert's ON CONFLICT ... SET id = excluded.id needs UPDATE on id; RLS still pins id to auth.uid().
grant update (id) on public.profiles to authenticated;
