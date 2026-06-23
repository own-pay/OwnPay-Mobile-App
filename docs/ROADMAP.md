# OwnPay Console — Decision Record & Build Roadmap

> Status legend: `[ ]` pending · `[/]` in progress · `[x]` done. Update as work lands.

## Build progress — 2026-06-23 (verified: `flutter analyze` clean · 29 unit tests pass)

**Done & verified**
- Project scaffolded (`flutter create`), dependencies resolved, **codegen-free** stack chosen.
- Strict `analysis_options.yaml` (strict-casts/raw-types, `avoid_print`/`avoid_dynamic_calls` = error).
- **Core IP (fully unit-tested):**
  - `core/crypto/AesGcmCipher` — AES-256-GCM, server-compatible `IV‖ct‖tag` base64 envelope (6 tests:
    round-trip, envelope layout, IV-uniqueness, tamper-detection, key validation).
  - `features/privacy_gate` — `PrivacyGate` + `FilterRules` (16 tests: fail-closed, whitelist,
    negative-priority, positive, parsing, cache, staleness).
  - `features/sync` — `QueuedSms` + `RetryPolicy` (7 tests: syncable, copyWith, map round-trip,
    wire-shape excludes plaintext, exponential backoff capped).
- `core/error/Failure` (typed), `core/network/ApiResult`, `core/config/AppConfig`.
- **App shell (widget-tested):** `AppTheme` (M3, brand teal) + `main.dart`/`app.dart` + branded
  unpaired `HomeScreen` — the app launches as **OwnPay Console**.
- Dependencies confirmed **latest** (direct + dev all up-to-date; the only newer versions are
  Flutter-SDK-pinned transitives, which require a `flutter upgrade` of the SDK itself).
- **Infra (increment 1):** `SecureStore` (Keystore/Keychain) · `ApiClient` (Dio, typed `ApiResult`)
  + `AuthInterceptor` (single-flight 401→refresh, replay) · `get_it` DI · `go_router` (paired vs
  un-paired start location).
- **Pairing (increment 2):** `DeviceRepository` (pair + token-refresh, persists credentials) ·
  `PairingCubit` · `PairingScreen` (manual URL+OTP and QR via `mobile_scanner`) — unpaired → pairing,
  paired → home.
- `INTERNET` permission added for release networking.
- Verified end-to-end: `flutter analyze` clean · **29 tests pass** · **debug APK builds**.

> Runtime note: the backend **FIND-019** fix is already in place — pair/refresh run in the JWT-free
> `mobile-bootstrap` group, regression-guarded by `../../tests/Integration/MobileBootstrapRouteTest.php`.
> The only runtime requirement left for pairing is a reachable server; the client side is wired.

**Not yet built (next increments)** — secure storage wrapper · Dio client + AuthInterceptor (401
refresh) + cert pinning · repositories (device/auth, sms, config, notifications, dashboard) · DI
(`get_it`) · router (`go_router`) · theme/design-system widgets · feature Blocs + screens (pairing,
disclosure, dashboard, audit, notifications, settings) · **native Android** `RECEIVE_SMS` receiver +
foreground service + `AndroidManifest` permissions · localization (en/bn) · `main.dart` wiring ·
`flutter build apk` compile-proof.

---

## Decision record (why this shape)

**Context.** Two prior plans existed: `../docs/v2/mobile_app/` (a build plan proposing a 3-tier SMS
capture with **separate `sideload` and `playstore` build flavors**) and
`../docs/v2/Claude_audit/.../mobile_architecture.md` (a readiness + Play-compliance audit recommending a
**single app with `READ_SMS` via the financial-transactions exception**).

**Decision.** Build **one app, one build**, on Play Store, capturing SMS with `READ_SMS`/`RECEIVE_SMS`
under the exception use case, with an on-device fail-closed privacy gate.

**Rationale.**
- The SMS Retriever API (the "Play-safe" tier of the dual-flavor plan) **cannot read third-party bank
  SMS** — it only receives the app's own hash-tagged OTP. Manual-Share defeats the automation. So the
  dual-flavor plan's *only* working capture path was sideload-only `READ_SMS` = **two versions**, which is
  out of scope ("one version of app").
- A single `READ_SMS` app is legitimately publishable via the exception + Declaration Form + privacy gate
  ([PLAY_STORE.md](PLAY_STORE.md)). The already-built backend (filter-rules whitelist, GCM ingest)
  already supports exactly this model.

**Consequences / what we keep vs drop.**
- **Keep** the backend (built, tested) and the app architecture (Dio/Hive/Bloc, offline sync, audit
  trail, foreground service).
- **Drop** build flavors, the SMS Retriever path, and Manual-Share as primary capture.
- **Reconcile** stale numbers from the old plan: verified tokens are **access ≈ 15 min / refresh ≈ 30 d**
  (not 90 d), and tokens are opaque to the client.

---

## Prerequisite (backend) — ✅ cleared

- [x] **FIND-019** fixed: `POST /devices` and `POST /devices/token-refreshes` run in the JWT-free
  `mobile-bootstrap` group (committed 2026-06-11; regression-guarded by
  `../../tests/Integration/MobileBootstrapRouteTest.php`). Devices can pair. See [API_CONTRACT.md](API_CONTRACT.md) §0.

**Backend status:** the mobile API surface (pairing, JWT, SMS ingest + 2-tier parser, notifications,
dashboard, admin SMS-center UIs) is **implemented and tested** in `../`. This roadmap covers the **Flutter
app**, which is greenfield.

---

## Phase 0 — Project scaffold
- [x] `flutter create` in place — package `org.ownpay.console`, app name "OwnPay Console", Dart package `ownpay_console` (Android + iOS).
- [ ] Add locked dependencies (see [CLAUDE.md](../CLAUDE.md) §3); `flutter pub get`.
- [ ] Folder structure per [ARCHITECTURE.md](../ARCHITECTURE.md) §3; DI (`get_it`+`injectable`); router
  (`go_router`) with a paired/un-paired redirect guard.
- [ ] Theme tokens + base design-system widgets ([DESIGN.md](../DESIGN.md) §2–3).
- [ ] `flutter analyze` clean; CI lint/test gate.

## Phase 1 — Pairing & auth
- [ ] QR scan (`mobile_scanner`) + manual server-URL/OTP entry screen.
- [ ] `POST /devices` pairing; store secrets + `server_url` in `flutter_secure_storage`.
- [ ] Dio client + `AuthInterceptor` (bearer attach, single-flight 401 refresh, retry-once) + cert pin.
- [ ] Device fingerprint (`androidId:certSha256`).
- [ ] "Re-pair required" state on refresh failure.
- [ ] Tests: auth interceptor refresh/rotation, secure-store round-trip.

## Phase 2 — SMS capture & privacy gate
- [ ] Full-screen disclosure ([DESIGN.md](../DESIGN.md) §4.2) **before** runtime `READ_SMS`/`RECEIVE_SMS`.
- [ ] Single `RECEIVE_SMS` capture stream (no Retriever/Manual fallbacks).
- [ ] `FilterRules` fetch + cache from `/config/filter-rules`; refresh on interval.
- [ ] Privacy gate engine (whitelist → negative → positive), **fail-closed**.
- [ ] AES-256-GCM cipher, byte-compatible with server envelope.
- [ ] **Exhaustive** gate + crypto unit tests (every branch incl. fail-closed).

## Phase 3 — Offline sync & audit trail
- [ ] Hive `sms_queue` (encrypted payload only) with status/retry.
- [ ] Connectivity monitor; batch sync worker → `POST /sms`; result mapping; exp. backoff (max 5).
- [ ] Audit UI: All | Synced | Issues; auto-purge approved >30 d; manual clear of failed.
- [ ] Biometric-locked privacy log (decision metadata only).
- [ ] Tests: sync worker outcomes, retry/backoff, durability across restart.

## Phase 4 — Notifications & dashboard
- [ ] Foreground service (persistent notification, boot/kill restart, battery-exclusion request).
- [ ] Poller (10–15 s) → `flutter_local_notifications`; ack via `/notifications/acknowledgements`.
- [ ] Dashboard (`/dashboard`) with Hive cache + offline banner; transactions list/detail.
- [ ] Tests: poller ack flow, offline cache fallback.

## Phase 5 — Hardening & release
- [ ] Cert pinning verified; release obfuscation + ProGuard/R8; `allowBackup=false`; no cleartext.
- [ ] Localization (en + bn); accessibility pass.
- [ ] Play listing + privacy policy + data-safety + **SMS Declaration Form** ([PLAY_STORE.md](PLAY_STORE.md)).
- [ ] Reviewer demo account + screencast (whitelisted match vs OTP ignored).
- [ ] `flutter build appbundle --release --obfuscate --split-debug-info=…`; internal-test track first.

---

*Created 2026-06-23. This roadmap supersedes `../docs/v2/mobile_app/todo.md` for the Flutter app (the
backend portions there remain the record of completed server work).*
