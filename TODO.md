# RideAlong — Build Plan

Source of truth for what we build. Blueprint: [Docs/RideAlong_Product_Technical_Blueprint.docx](Docs/RideAlong_Product_Technical_Blueprint.docx).
Add items at the bottom under **Backlog**; move them into a phase when we commit to them.

## Decisions
- **Flutter app first** (Android first; iOS needs a Mac to build). Web later if needed. *Deviates from blueprint's web-first plan.*
- **Backend: hosted Supabase** (Auth, Postgres + PostGIS, Realtime, Edge Functions). No custom server.
- **Pilot:** closed community, one Hyderabad corridor, commute hours.
- **Keep it small:** few packages, `setState` + Supabase streams before any state-management library; plain `Navigator` before a router package. Add only when it hurts.

## Packages (add per phase, not upfront)
| Package | Phase |
|---|---|
| `supabase_flutter` | 1 |
| `google_maps_flutter`, `geolocator` | 3 |
| `firebase_messaging` | 4 |
| `razorpay_flutter` | 5 |

## Security rules (apply from day one)
- [ ] Row-Level Security ON for every table; no table without policies.
- [ ] App ships only the Supabase **anon** key. Service-role key, Razorpay secret, Maps server key live only in Edge Function secrets.
- [ ] All state changes that matter (accept request, seat count, ride status, price, payment) happen in **Postgres functions / Edge Functions**, never trusted from the client.
- [ ] Seat booking is atomic (single SQL update with `seats_available >= n` check) — no double-booking.
- [ ] DB constraints: `seats_available between 0 and seats_total`, status enums, amounts > 0.
- [ ] Never trust client "payment success"; verify Razorpay signature + order status server-side, plus webhook.
- [ ] Google Maps key restricted to app package name + SHA-1.
- [ ] Rate-limit OTP and urgent-request endpoints.
- [ ] Exact home addresses never shown to other users; show pickup point only after acceptance.
- [ ] Location only with explicit permission + reason; urgent mode is always an explicit user action.
- [ ] Secrets never committed (`.gitignore` env files, `key.properties`, `google-services.json` reviewed).
- [ ] Release build: obfuscation (`--obfuscate --split-debug-info`), no debug logs of tokens/PII.

## Phase 0 — Setup
- [x] Flutter SDK installed at `C:\dev\flutter` (on user PATH).
- [x] Android SDK + NDK 28.2 installed, `flutter doctor` green for Android, debug APK builds. Web/Windows targets disabled.
- [x] Hosted Supabase dev project `bkzaatsccqemfuejowxw` (us-east-1) linked; PostGIS migration pushed.
- [x] `flutter create` app in `app/` (android, ios), `git init`, `.gitignore` secrets.
- [x] Supabase migrations folder in `supabase/`; first migration enables PostGIS.

## Phase 1 — Auth + core loop (no maps, no payments)
- [x] Auth: email OTP (dev). Session stored in Keystore/Keychain (`flutter_secure_storage`). Android backup off.
- [x] Debug-only password login (`kDebugMode`, compiled out of release) for dashboard-created test users.
- [ ] Custom SMTP: fill `SMTP_PASS` in `supabase/.env` (git-ignored), run `npx supabase config push`.
- [ ] Before pilot: phone OTP via SMS provider (MSG91/Twilio) **and** custom SMTP (Supabase default email only reaches project team members, ~2/hour).
- [x] Profile: name, can drive.
- [ ] Profile: emergency contact (table + RLS ready).
- [x] Tables: `profiles`, `emergency_contacts`, `vehicles`, `rides`, `ride_requests`, `ratings` + RLS.
      Writes to rides/requests/ratings only via RPCs: `create_ride`, `request_seat`, `respond_request`, `cancel_request`, `update_ride_status`, `rate_user`.
      Self-check: `npx supabase db query --linked -f supabase/tests/core_loop.sql` → `ALL CORE LOOP TESTS PASSED`.
- [x] Driver: Offer Ride (origin, destination as text for now, time, seats, contribution) + add vehicle.
- [x] Passenger: Find Ride (list of upcoming rides, search), request seat.
- [x] Driver: accept / reject (server function, atomic seat decrement).
- [x] Ride status: scheduled → started → completed / cancelled.
- [x] Rate each other after completion.
- [x] My trips tab (driving + requested, upcoming/past). Light + dark theme.
- [x] Manual test of full loop on device with driver@test.com + rider@test.com.

## Phase 2 — Maps
- [ ] Places autocomplete for origin/destination/pickup.
- [ ] Store points as PostGIS `geography(Point)`; route as `geography(LineString)` from Directions API (called via Edge Function, server key).
- [ ] Map view on ride details.

## Phase 3 — Urgent matching (the core)
- [ ] "Need a Ride Now" button.
- [ ] Driver "live intent": going now + willing to take 1–2 passengers, discoverable for a limited window.
- [ ] Match query (first version, one SQL function):
      route passes within R of pickup AND within R of destination AND pickup comes before destination along the route (`ST_LineLocatePoint`), departing within window, seats available, not blocked.
      Rank by pickup distance + departure gap. *Weighted score from blueprint §7.4 later, once we have data.*
- [ ] Send to top 3 drivers; request expires (e.g. 2 min); expand radius and retry; stop all on accept.
- [ ] Log every match outcome (sent / accepted / rejected / expired) for tuning.

## Phase 4 — Realtime + notifications
- [ ] Supabase Realtime for request/ride status in-app.
- [ ] FCM push for new requests and acceptances.
- [ ] Optional live driver location during trip (only while trip active).

## Phase 5 — Payments (Razorpay TEST mode)
- [ ] Edge Function: create order (server computes amount + fee).
- [ ] App opens Razorpay Checkout with server `order_id` (UPI Intent/QR, not UPI Collect).
- [ ] Edge Function: verify signature + fetch order status; webhook handler.
- [ ] Tables: `payments`, `refunds`, `ledger_entries` (append-only).
- [ ] Cancellation / refund policy per blueprint §10.
- [ ] **Legal review before any real money** (Aggregator Guidelines 2025, Telangana policy).

## Phase 6 — Safety
- [ ] Driver ID + vehicle verification (manual admin review first).
- [ ] Block / report user.
- [ ] Share live trip link with trusted contact.
- [ ] SOS button (call emergency number + notify contacts).
- [ ] Reliability score: penalize accept-then-cancel.

## Phase 7 — Admin + metrics
- [ ] Admin via Supabase dashboard + SQL views first (no admin app until needed).
- [ ] Metrics views: time-to-match, acceptance, completion, cancellation, repeat rate.

## Phase 8 — Pilot launch
- [ ] Create **prod** Supabase project in **Mumbai (ap-south-1)**; `link` + `db push`. (Dev project `bkzaatsccqemfuejowxw` stays in us-east-1 — developer is in the US.)
- [ ] Privacy policy, terms, cancellation policy, grievance contact.
- [ ] Play Store internal testing track.
- [ ] Onboard one community; measure; tune matching.

## Software to install
| Tool | Why | Notes |
|---|---|---|
| Flutter SDK (stable) | build the app | add `flutter\bin` to PATH |
| Android Studio | Android SDK, emulator, bundled JDK | run `flutter doctor --android-licenses` |
| VS Code Flutter + Dart extensions | editor support | VS Code already installed |
| Supabase CLI | migrations | runs via `npx supabase` (Node already installed) — no install |
| ~~Docker~~ | local Supabase | skipped: use hosted dev project instead |
| Xcode (Mac only) | iOS builds | later |

Accounts needed: Supabase, Google Cloud (Maps), Firebase (Phase 4), Razorpay test (Phase 5), SMS provider for OTP (before pilot).

## Backlog
- iOS build
- Web version
- Demand heat map for drivers (blueprint §8.2)
- Saved places (home/work)
- Weighted match score + tuning
- Driver settlements / payouts
