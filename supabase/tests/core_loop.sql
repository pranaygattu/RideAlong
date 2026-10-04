-- Core loop + security self-check. Runs in a transaction and rolls back; leaves no data.
-- Run: npx supabase db query --linked -f supabase/tests/core_loop.sql
begin;

create function pg_temp.expect_error(p_sql text, p_msg text) returns void language plpgsql as $$
begin
  execute p_sql;
  raise exception 'FAIL: expected error "%" from: %', p_msg, p_sql;
exception when others then
  if sqlerrm not like '%' || p_msg || '%' then
    raise exception 'FAIL: got "%", expected "%" from: %', sqlerrm, p_msg, p_sql;
  end if;
end $$;

create function pg_temp.login(p_user uuid) returns void language sql as $$
  select set_config('request.jwt.claims', json_build_object('sub', p_user, 'role', 'authenticated')::text, true);
$$;

insert into auth.users (id, email, aud, role) values
  ('00000000-0000-0000-0000-0000000000d1', 'driver@test.local', 'authenticated', 'authenticated'),
  ('00000000-0000-0000-0000-0000000000a1', 'p1@test.local', 'authenticated', 'authenticated'),
  ('00000000-0000-0000-0000-0000000000a2', 'p2@test.local', 'authenticated', 'authenticated');

do $$
declare
  d  uuid := '00000000-0000-0000-0000-0000000000d1';
  p1 uuid := '00000000-0000-0000-0000-0000000000a1';
  p2 uuid := '00000000-0000-0000-0000-0000000000a2';
  v_vehicle uuid;
  v_ride uuid;
  r1 uuid;
  r2 uuid;
  n int;
begin
  set local role authenticated;

  -- Profiles + vehicle
  perform pg_temp.login(d);
  insert into public.profiles (id, name, can_drive) values (d, 'Driver', true);
  insert into public.vehicles (model, registration_number, seat_capacity) values ('Swift', 'TS09AB1234', 3)
    returning id into v_vehicle;
  perform pg_temp.login(p1);
  insert into public.profiles (id, name) values (p1, 'P1');
  perform pg_temp.expect_error(format('insert into public.profiles (id, name) values (%L, %L)', p2, 'spoof'), 'row-level security');
  perform pg_temp.login(p2);
  insert into public.profiles (id, name) values (p2, 'P2');

  -- Direct writes are blocked
  perform pg_temp.expect_error('update public.profiles set rating_avg = 5', 'permission denied');
  perform pg_temp.expect_error(format('select public.create_ride(%L, %L, %L, now() + interval ''1 hour'', 1, 50)', v_vehicle, 'A', 'B'), 'Only drivers');
  select count(*) into n from public.vehicles;
  assert n = 0, 'passenger can see driver vehicle before acceptance';

  -- Driver offers a 2-seat ride
  perform pg_temp.login(d);
  v_ride := public.create_ride(v_vehicle, 'Gachibowli', 'Hitech City', now() + interval '1 hour', 2, 50);
  perform pg_temp.expect_error(format('select public.create_ride(%L, %L, %L, now() + interval ''1 hour'', 4, 50)', v_vehicle, 'A', 'B'), 'More seats');
  perform pg_temp.expect_error(format('select public.request_seat(%L, 1)', v_ride), 'own ride');
  perform pg_temp.expect_error(format('update public.rides set seats_booked = 0 where id = %L', v_ride), 'permission denied');

  -- Passengers request
  perform pg_temp.login(p1);
  r1 := public.request_seat(v_ride, 2);
  perform pg_temp.expect_error(format('select public.request_seat(%L, 1)', v_ride), 'already requested');
  perform pg_temp.expect_error(format('select public.respond_request(%L, true)', r1), 'Request not found');
  perform pg_temp.login(p2);
  r2 := public.request_seat(v_ride, 1);
  select count(*) into n from public.ride_requests;
  assert n = 1, 'passenger can see other passengers'' requests';

  -- Driver accepts p1 (fills the car); p2 can no longer be accepted
  perform pg_temp.login(d);
  select count(*) into n from public.ride_requests;
  assert n = 2, 'driver should see both requests';
  perform public.respond_request(r1, true);
  select seats_available into n from public.rides where id = v_ride;
  assert n = 0, 'seats not booked';
  perform pg_temp.expect_error(format('select public.respond_request(%L, true)', r2), 'Not enough seats');
  perform pg_temp.expect_error(format('select public.respond_request(%L, false)', r1), 'no longer pending');

  -- Vehicle visible to accepted passenger only
  perform pg_temp.login(p1);
  select count(*) into n from public.vehicles;
  assert n = 1, 'accepted passenger should see vehicle';
  perform pg_temp.login(p2);
  select count(*) into n from public.vehicles;
  assert n = 0, 'pending passenger can see vehicle';

  -- p1 cancels -> seats freed; requests again for 1 seat and is accepted
  perform pg_temp.login(p1);
  perform public.cancel_request(r1);
  r1 := public.request_seat(v_ride, 1);
  perform pg_temp.login(d);
  select seats_available into n from public.rides where id = v_ride;
  assert n = 2, 'cancel did not free seats';
  perform public.respond_request(r1, true);

  -- Start -> p2 pending request expires; complete
  perform pg_temp.expect_error(format('select public.update_ride_status(%L, %L)', v_ride, 'completed'), 'Cannot change ride');
  perform public.update_ride_status(v_ride, 'started');
  assert (select status from public.ride_requests where id = r2) = 'expired', 'pending request not expired on start';
  perform public.update_ride_status(v_ride, 'completed');

  -- Ratings
  perform pg_temp.login(p1);
  perform public.rate_user(v_ride, d, 5, 'Smooth ride');
  perform pg_temp.expect_error(format('select public.rate_user(%L, %L, 4)', v_ride, d), 'Already rated');
  perform pg_temp.login(p2);
  perform pg_temp.expect_error(format('select public.rate_user(%L, %L, 1)', v_ride, d), 'only rate people');
  perform pg_temp.login(d);
  perform public.rate_user(v_ride, p1, 4);
  assert (select rating_avg from public.profiles where id = d) = 5.00, 'driver rating wrong';
  assert (select rating_count from public.profiles where id = p1) = 1, 'passenger rating count wrong';

  -- Anonymous users get nothing
  reset role;
  set local role anon;
  perform pg_temp.expect_error('select 1 from public.rides', 'permission denied');
  perform pg_temp.expect_error(format('select public.request_seat(%L, 1)', v_ride), 'permission denied');
  reset role;
end $$;

-- Only reached if every check above passed (any failure aborts the transaction).
select 'ALL CORE LOOP TESTS PASSED' as result;
rollback;
