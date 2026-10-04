# RideAlong

Community ride-sharing for India. Instead of booking a new cab, a passenger joins a car that is **already going their way**: drivers publish a trip they're making anyway, and passengers request a seat and share the cost.

Pilot plan: one Hyderabad commute corridor, inside a closed community (one company, campus or apartment network). Full product and technical blueprint: [Docs/RideAlong_Product_Technical_Blueprint.docx](Docs/RideAlong_Product_Technical_Blueprint.docx).

## Status

Phase 1 (core loop) is working and tested on a device:

- Email OTP login, profile, "I also drive" toggle
- Driver: add vehicle, offer a ride (route, departure, seats, contribution per seat)
- Passenger: find rides, request seats, cancel
- Driver: accept or decline requests, start, complete or cancel the ride
- Both sides rate each other after the trip

Next up: maps and real locations (Phase 2), then urgent "Need a ride now" matching (Phase 3). The full checklist is in [TODO.md](TODO.md).

## Tech stack

| Layer | Choice |
|---|---|
| App | Flutter (Android first; iOS later) |
| Backend | Supabase: Auth, Postgres + PostGIS, Row-Level Security |
| Session storage | `flutter_secure_storage` (Android Keystore / iOS Keychain) |
| Later | Google Maps, Firebase Cloud Messaging, Razorpay |

## Repository layout

```
app/                 Flutter app
  lib/main.dart        startup, auth gate, secure session storage
  lib/ui.dart          theme and shared widgets
  lib/*_screen.dart    one file per screen
  env/dev.json         Supabase URL + publishable key (public by design)
supabase/
  migrations/          database schema, applied in order
  tests/core_loop.sql  security and flow self-check (rolls back, leaves no data)
  templates/           auth email templates
  config.toml          auth settings (SMTP credentials come from supabase/.env)
Docs/                product blueprint
TODO.md              build plan and progress
```

## Getting started

**Prerequisites:** Flutter SDK (stable), Android SDK (via Android Studio), Node.js (for `npx supabase`).

Run the app:

```sh
cd app
flutter pub get
flutter run --dart-define-from-file=env/dev.json
```

In VS Code you can use the **RideAlong (dev)** launch configuration instead; it passes the config file for you.

Debug builds also offer a password sign-in for test users created in the Supabase dashboard (Authentication → Users → Add user, with Auto Confirm on). Release builds don't include it.

## Database

All schema changes live in `supabase/migrations/`. Never edit the database by hand.

```sh
npx supabase login
npx supabase link --project-ref <project-ref>
npx supabase db push                                         # apply migrations
npx supabase db query --linked -f supabase/tests/core_loop.sql   # expect: ALL CORE LOOP TESTS PASSED
```

## Security model

- **Row-Level Security on every table.** Logged-out users can read and call nothing.
- **The app never writes rides, requests or ratings directly.** Every change goes through server functions (`create_ride`, `request_seat`, `respond_request`, `cancel_request`, `update_ride_status`, `rate_user`), each of which checks who is calling and whether the action is allowed.
- **No double-booking:** accepting a request reserves its seats in one locked update.
- **Privacy:** emergency contacts are visible only to their owner. A driver's vehicle and plate number are visible only to passengers they have accepted, and passengers can't see each other's requests.
- **Only the publishable key ships in the app.** The service-role key, SMTP password and future payment secrets never enter the app or Git.

## Secrets

`supabase/.env` holds the SMTP credentials and is **git-ignored**. Never commit it. Create it locally:

```
SMTP_USER=you@gmail.com
SMTP_PASS=<gmail app password>
```

Then apply the auth email settings with `npx supabase config push`.

## Before a public launch

Read section 17 of the blueprint first. Paid ride-sharing in India may fall under the Motor Vehicles Aggregator Guidelines 2025 and Telangana's aggregator policy, so get legal review before taking real payments.
