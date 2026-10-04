-- RLS helpers don't need to be callable over the REST API; move them to a schema PostgREST doesn't expose.
-- Policies reference functions by OID, so they keep working. Policies run as the caller, so the caller still
-- needs USAGE/EXECUTE here — but there is no /rpc endpoint for this schema.
create schema if not exists private;
revoke all on schema private from public, anon;
grant usage on schema private to authenticated;

alter function public.is_ride_driver(uuid) set schema private;
alter function public.is_ride_passenger(uuid) set schema private;
alter function public.can_see_vehicle(uuid) set schema private;

-- Remaining advisor warnings (create_ride, request_seat, respond_request, cancel_request,
-- update_ride_status, rate_user) are intentional: they ARE the app's write API and check auth.uid() themselves.
