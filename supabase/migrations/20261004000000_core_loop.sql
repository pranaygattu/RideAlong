-- Phase 1: profiles, vehicles, rides, requests, ratings.
-- Security model:
--   * Clients may SELECT (under RLS) and edit only their own profile, vehicles and emergency contacts.
--   * Every ride / request / rating state change goes through the security-definer functions below,
--     which check the caller and keep seat counts consistent. Clients have no direct write on those tables.

-- Supabase grants everything on new objects to anon/authenticated by default; turn that off for this schema.
alter default privileges for role postgres in schema public revoke all on tables from anon, authenticated;
alter default privileges for role postgres in schema public revoke execute on functions from public, anon, authenticated;

-- ---------- Tables ----------

create table public.profiles (
  id uuid primary key references auth.users on delete cascade,
  name text not null check (char_length(name) between 1 and 80),
  can_drive boolean not null default false,
  rating_avg numeric(3,2) not null default 0,
  rating_count int not null default 0,
  created_at timestamptz not null default now()
);

create table public.emergency_contacts (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid() references public.profiles on delete cascade,
  name text not null check (char_length(name) between 1 and 80),
  phone text not null check (phone ~ '^\+?[0-9]{8,15}$'),
  relationship text check (char_length(relationship) <= 40)
);
create index on public.emergency_contacts (user_id);

create table public.vehicles (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null default auth.uid() references public.profiles on delete cascade,
  model text not null check (char_length(model) between 1 and 60),
  registration_number text not null check (registration_number ~ '^[A-Z0-9 -]{4,15}$'),
  seat_capacity int not null check (seat_capacity between 1 and 7), -- passenger seats, excluding driver
  created_at timestamptz not null default now()
);
create index on public.vehicles (owner_id);

create table public.rides (
  id uuid primary key default gen_random_uuid(),
  driver_id uuid not null references public.profiles on delete cascade,
  vehicle_id uuid references public.vehicles on delete set null,
  origin_text text not null check (char_length(origin_text) between 1 and 200),
  destination_text text not null check (char_length(destination_text) between 1 and 200),
  departure_time timestamptz not null,
  seats_total int not null check (seats_total between 1 and 7),
  seats_booked int not null default 0,
  seats_available int generated always as (seats_total - seats_booked) stored,
  contribution_amount numeric(8,2) not null check (contribution_amount between 0 and 5000), -- per seat, INR
  status text not null default 'scheduled' check (status in ('scheduled', 'started', 'completed', 'cancelled')),
  created_at timestamptz not null default now(),
  check (seats_booked between 0 and seats_total)
);
create index on public.rides (status, departure_time);
create index on public.rides (driver_id);
create index on public.rides (vehicle_id);

create table public.ride_requests (
  id uuid primary key default gen_random_uuid(),
  ride_id uuid not null references public.rides on delete cascade,
  passenger_id uuid not null references public.profiles on delete cascade,
  seats int not null check (seats between 1 and 4),
  status text not null default 'pending' check (status in ('pending', 'accepted', 'rejected', 'cancelled', 'expired')),
  created_at timestamptz not null default now()
);
-- One live request per passenger per ride.
create unique index ride_requests_one_active on public.ride_requests (ride_id, passenger_id)
  where status in ('pending', 'accepted');
create index on public.ride_requests (passenger_id);

create table public.ratings (
  id uuid primary key default gen_random_uuid(),
  ride_id uuid not null references public.rides on delete cascade,
  from_user uuid not null references public.profiles on delete cascade,
  to_user uuid not null references public.profiles on delete cascade,
  score int not null check (score between 1 and 5),
  comment text check (char_length(comment) <= 500),
  created_at timestamptz not null default now(),
  unique (ride_id, from_user, to_user),
  check (from_user <> to_user)
);
create index on public.ratings (to_user);
create index on public.ratings (from_user);

-- ---------- RLS helpers (security definer so policies don't recurse into each other) ----------

create function public.is_ride_driver(p_ride uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (select 1 from public.rides where id = p_ride and driver_id = auth.uid());
$$;

create function public.is_ride_passenger(p_ride uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (select 1 from public.ride_requests where ride_id = p_ride and passenger_id = auth.uid());
$$;

-- Passengers see the vehicle (registration number) only once accepted.
create function public.can_see_vehicle(p_vehicle uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from public.rides r join public.ride_requests q on q.ride_id = r.id
    where r.vehicle_id = p_vehicle and q.passenger_id = auth.uid() and q.status = 'accepted'
  );
$$;

-- ---------- RLS + grants ----------

alter table public.profiles enable row level security;
alter table public.emergency_contacts enable row level security;
alter table public.vehicles enable row level security;
alter table public.rides enable row level security;
alter table public.ride_requests enable row level security;
alter table public.ratings enable row level security;

revoke all on public.profiles, public.emergency_contacts, public.vehicles,
  public.rides, public.ride_requests, public.ratings from anon, authenticated;

-- profiles: everyone signed in can see name + rating; you edit only your own name/role.
grant select on public.profiles to authenticated;
grant insert (id, name, can_drive), update (name, can_drive) on public.profiles to authenticated;
create policy profiles_select on public.profiles for select to authenticated using (true);
create policy profiles_insert on public.profiles for insert to authenticated with check (id = (select auth.uid()));
create policy profiles_update on public.profiles for update to authenticated
  using (id = (select auth.uid())) with check (id = (select auth.uid()));

-- emergency_contacts: private to the owner.
grant select, delete on public.emergency_contacts to authenticated;
grant insert (name, phone, relationship), update (name, phone, relationship) on public.emergency_contacts to authenticated;
create policy emergency_contacts_owner on public.emergency_contacts for all to authenticated
  using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));

-- vehicles: owner manages; accepted passengers can read.
grant select, delete on public.vehicles to authenticated;
grant insert (model, registration_number, seat_capacity), update (model, registration_number, seat_capacity)
  on public.vehicles to authenticated;
create policy vehicles_select on public.vehicles for select to authenticated
  using (owner_id = (select auth.uid()) or public.can_see_vehicle(id));
create policy vehicles_insert on public.vehicles for insert to authenticated with check (owner_id = (select auth.uid()));
create policy vehicles_update on public.vehicles for update to authenticated
  using (owner_id = (select auth.uid())) with check (owner_id = (select auth.uid()));
create policy vehicles_delete on public.vehicles for delete to authenticated using (owner_id = (select auth.uid()));

-- rides: open upcoming rides are browsable; otherwise only driver and requesters.
grant select on public.rides to authenticated;
create policy rides_select on public.rides for select to authenticated using (
  driver_id = (select auth.uid())
  or (status = 'scheduled' and departure_time > now() - interval '15 minutes')
  or public.is_ride_passenger(id)
);

-- ride_requests: the passenger and the ride's driver.
grant select on public.ride_requests to authenticated;
create policy ride_requests_select on public.ride_requests for select to authenticated
  using (passenger_id = (select auth.uid()) or public.is_ride_driver(ride_id));

-- ratings: giver and receiver.
grant select on public.ratings to authenticated;
create policy ratings_select on public.ratings for select to authenticated
  using (from_user = (select auth.uid()) or to_user = (select auth.uid()));

-- ---------- State-changing functions (the only write path for rides/requests/ratings) ----------

create function public.create_ride(
  p_vehicle_id uuid, p_origin text, p_destination text,
  p_departure timestamptz, p_seats int, p_contribution numeric
) returns uuid
language plpgsql security definer set search_path = '' as $$
declare
  v_capacity int;
  v_id uuid;
begin
  if not exists (select 1 from public.profiles where id = auth.uid() and can_drive) then
    raise exception 'Only drivers can offer rides';
  end if;
  select seat_capacity into v_capacity from public.vehicles where id = p_vehicle_id and owner_id = auth.uid();
  if v_capacity is null then
    raise exception 'Vehicle not found';
  end if;
  if p_seats > v_capacity then
    raise exception 'More seats than the vehicle has';
  end if;
  if p_departure < now() - interval '5 minutes' or p_departure > now() + interval '30 days' then
    raise exception 'Departure must be between now and 30 days ahead';
  end if;
  insert into public.rides (driver_id, vehicle_id, origin_text, destination_text, departure_time, seats_total, contribution_amount)
  values (auth.uid(), p_vehicle_id, p_origin, p_destination, p_departure, p_seats, p_contribution)
  returning id into v_id;
  return v_id;
end $$;

create function public.request_seat(p_ride_id uuid, p_seats int) returns uuid
language plpgsql security definer set search_path = '' as $$
declare
  v_ride public.rides;
  v_id uuid;
begin
  if not exists (select 1 from public.profiles where id = auth.uid()) then
    raise exception 'Complete your profile first';
  end if;
  select * into v_ride from public.rides where id = p_ride_id;
  if v_ride.id is null or v_ride.status <> 'scheduled' or v_ride.departure_time < now() - interval '15 minutes' then
    raise exception 'Ride is not available';
  end if;
  if v_ride.driver_id = auth.uid() then
    raise exception 'You cannot request your own ride';
  end if;
  if p_seats > v_ride.seats_available then
    raise exception 'Not enough seats';
  end if;
  begin
    insert into public.ride_requests (ride_id, passenger_id, seats)
    values (p_ride_id, auth.uid(), p_seats)
    returning id into v_id;
  exception when unique_violation then
    raise exception 'You already requested this ride';
  end;
  return v_id;
end $$;

create function public.respond_request(p_request_id uuid, p_accept boolean) returns void
language plpgsql security definer set search_path = '' as $$
declare
  v_req public.ride_requests;
begin
  -- Lock the request so it can't be accepted twice.
  select q.* into v_req
  from public.ride_requests q join public.rides r on r.id = q.ride_id
  where q.id = p_request_id and r.driver_id = auth.uid()
  for update of q;
  if v_req.id is null then
    raise exception 'Request not found';
  end if;
  if v_req.status <> 'pending' then
    raise exception 'Request is no longer pending';
  end if;
  if p_accept then
    -- Atomic seat booking: the WHERE re-checks capacity under the row lock.
    update public.rides set seats_booked = seats_booked + v_req.seats
    where id = v_req.ride_id and status = 'scheduled' and seats_total - seats_booked >= v_req.seats;
    if not found then
      raise exception 'Not enough seats left';
    end if;
  end if;
  update public.ride_requests set status = case when p_accept then 'accepted' else 'rejected' end
  where id = p_request_id;
end $$;

create function public.cancel_request(p_request_id uuid) returns void
language plpgsql security definer set search_path = '' as $$
declare
  v_req public.ride_requests;
begin
  select * into v_req from public.ride_requests
  where id = p_request_id and passenger_id = auth.uid()
  for update;
  if v_req.id is null then
    raise exception 'Request not found';
  end if;
  if v_req.status not in ('pending', 'accepted') then
    raise exception 'Request cannot be cancelled';
  end if;
  if v_req.status = 'accepted' then
    update public.rides set seats_booked = seats_booked - v_req.seats
    where id = v_req.ride_id and status = 'scheduled';
    if not found then
      raise exception 'Ride has already started';
    end if;
  end if;
  update public.ride_requests set status = 'cancelled' where id = p_request_id;
end $$;

-- Driver-only transitions: scheduled -> started | cancelled, started -> completed.
create function public.update_ride_status(p_ride_id uuid, p_status text) returns void
language plpgsql security definer set search_path = '' as $$
declare
  v_ride public.rides;
begin
  select * into v_ride from public.rides where id = p_ride_id and driver_id = auth.uid() for update;
  if v_ride.id is null then
    raise exception 'Ride not found';
  end if;
  if not ((v_ride.status = 'scheduled' and p_status in ('started', 'cancelled'))
       or (v_ride.status = 'started' and p_status = 'completed')) then
    raise exception 'Cannot change ride from % to %', v_ride.status, p_status;
  end if;
  update public.rides set status = p_status where id = p_ride_id;
  if p_status = 'cancelled' then
    update public.ride_requests set status = 'cancelled' where ride_id = p_ride_id and status in ('pending', 'accepted');
  elsif p_status = 'started' then
    update public.ride_requests set status = 'expired' where ride_id = p_ride_id and status = 'pending';
  end if;
end $$;

-- Driver rates an accepted passenger, or an accepted passenger rates the driver, after completion.
create function public.rate_user(p_ride_id uuid, p_to_user uuid, p_score int, p_comment text default null) returns void
language plpgsql security definer set search_path = '' as $$
declare
  v_driver uuid;
  v_passenger uuid;
begin
  select driver_id into v_driver from public.rides where id = p_ride_id and status = 'completed';
  if v_driver is null then
    raise exception 'Ride is not completed';
  end if;
  v_passenger := case when v_driver = auth.uid() then p_to_user
                      when v_driver = p_to_user then auth.uid() end;
  if v_passenger is null or v_passenger = v_driver or not exists (
    select 1 from public.ride_requests where ride_id = p_ride_id and passenger_id = v_passenger and status = 'accepted'
  ) then
    raise exception 'You can only rate people from this ride';
  end if;
  begin
    insert into public.ratings (ride_id, from_user, to_user, score, comment)
    values (p_ride_id, auth.uid(), p_to_user, p_score, p_comment);
  exception when unique_violation then
    raise exception 'Already rated';
  end;
  update public.profiles
  set rating_avg = round((rating_avg * rating_count + p_score) / (rating_count + 1), 2),
      rating_count = rating_count + 1
  where id = p_to_user;
end $$;

-- Only signed-in users may call functions; anon gets nothing.
revoke execute on all functions in schema public from public, anon;
grant execute on function
  public.create_ride(uuid, text, text, timestamptz, int, numeric),
  public.request_seat(uuid, int),
  public.respond_request(uuid, boolean),
  public.cancel_request(uuid),
  public.update_ride_status(uuid, text),
  public.rate_user(uuid, uuid, int, text),
  public.is_ride_driver(uuid),
  public.is_ride_passenger(uuid),
  public.can_see_vehicle(uuid)
to authenticated;
