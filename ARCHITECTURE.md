# OwnPay Console — Architecture

> Technical architecture for the single Flutter app. Read alongside [CLAUDE.md](CLAUDE.md) (rules),
> [docs/SECURITY.md](docs/SECURITY.md) (crypto/privacy), and [docs/API_CONTRACT.md](docs/API_CONTRACT.md)
> (backend). Date: 2026-06-23.

---

## 1. System overview

```
┌──────────────────────────── ANDROID DEVICE (one Play Store app) ───────────────────────────┐
│                                                                                             │
│  SMS broadcast ──▶ Privacy Gate ──▶ AES-256-GCM ──▶ Offline Queue ──▶ Sync Worker ──┐       │
│  (RECEIVE_SMS)     (on-device,        (per-device     (Hive,           (batch POST)  │       │
│                     fail-closed)       key)            durable)                      │       │
│                                                                                     │       │
│  Foreground Service keeps capture + poll alive   Notification Poller ◀── poll ──────┤       │
│  Dashboard (cached) ◀── poll/refresh ───────────────────────────────────────────────┤       │
│  Secrets (JWT / refresh / AES key) ── Keystore/Keychain only                         │       │
└─────────────────────────────────────────────────────────────────────────────────────┼──────┘
                                                                                        │ HTTPS
                                                                          JWT (bearer)  │ + cert pin
                                                                                        ▼
                                                       Self-hosted OwnPay server  /api/mobile/v1/*
                                              (the ONLY destination — no third-party cloud)
```

Only data that passes the on-device gate is encrypted and transmitted, and it goes **exclusively** to the
user's own server. There is no OwnPay-operated backend, no push service, no analytics endpoint.

---

## 2. Layering (Clean-ish, feature-first)

Three responsibilities per feature, plus a shared core:

- **Presentation** — Widgets + `Bloc`/`Cubit`. No business logic in widgets; they render state and
  dispatch events.
- **Domain** — Pure Dart: entities, value objects, repository *interfaces*, and use-cases. No Flutter,
  no `dio`, no `hive` imports here. Unit-testable in isolation.
- **Data** — Repository *implementations*, DTOs, the API client, and local data sources (Hive, secure
  storage). Maps DTO ⇄ domain entity.

`core/` holds cross-cutting infrastructure shared by all features (network, crypto, storage, services,
config, error types).

Dependency rule: **presentation → domain ← data**. Domain depends on nothing outward.

---

## 3. Folder structure

```
lib/
├── main.dart                         # bootstrap: DI init, run app
├── app/
│   ├── app.dart                      # MaterialApp.router, theme, locale
│   ├── router.dart                   # go_router config + guards (paired? → routes)
│   └── di.dart                       # get_it + injectable wiring
├── core/
│   ├── config/                       # constants, build config, endpoints
│   ├── crypto/                       # AesGcmCipher (256-bit, server-compatible envelope)
│   ├── network/                      # Dio client, AuthInterceptor (bearer+refresh), CertPinning, ApiResult
│   ├── storage/                      # HiveBoxes, SecureStore (Keystore/Keychain wrapper)
│   ├── services/                     # ConnectivityService, ForegroundService, ClockService
│   ├── error/                        # Failure types, exception→Failure mapping
│   └── utils/                        # formatters (money/date), validators
├── features/
│   ├── pairing/                      # QR scan + manual URL/OTP, pair call, credential storage
│   ├── permissions/                  # full-screen disclosure + runtime SMS consent (compliance-critical)
│   ├── sms_capture/                  # RECEIVE_SMS listener → raw message stream
│   ├── privacy_gate/                 # the on-device filter engine (+ FilterRules cache)
│   ├── sync/                         # offline queue, batch sync worker, retry/backoff
│   ├── audit/                        # local audit trail UI (All | Synced | Issues)
│   ├── notifications/               # poll service → flutter_local_notifications
│   ├── dashboard/                    # home stats, transactions list/detail (cached)
│   └── settings/                     # device info, re-pair, clear data, privacy log, server status
└── shared/
    ├── models/                       # cross-feature DTOs/entities
    ├── widgets/                      # design-system widgets (see DESIGN.md)
    └── theme/                        # colors, typography, spacing tokens
```

---

## 4. Core modules

### 4.1 Pairing & auth (`features/pairing`, `core/network`)
- Admin generates a 6-digit OTP + QR `{"server_url": "...", "otp": "482910"}` in the web panel.
- App scans QR (or manual entry) → `POST /api/mobile/v1/devices` with `pairing_code`, `device_id`
  (`androidId:certSha256`), `device_name`, `platform`, `app_version`.
- Server returns `access_token`, `refresh_token`, `aes_key` (hex-64), `device_uuid`, `expires_in`.
- **Storage:** all four secrets → `SecureStore` (Keystore/Keychain). The `server_url` → secure store too
  (it is the only allowed destination thereafter).
- **`AuthInterceptor`** attaches `Authorization: Bearer <access>`; on `401` it performs a **single**
  refresh via `POST …/devices/token-refreshes` (sending the refresh token), stores the rotated pair, and
  retries the original request once. A failed refresh → emit "re-pair required" and halt sync.

### 4.2 SMS capture (`features/sms_capture`)
- A `RECEIVE_SMS` `BroadcastReceiver` (via a thin platform channel / maintained plugin) yields a
  `Stream<RawSms>` of `{sender, body, receivedAt}`.
- The stream feeds **straight into the privacy gate** — raw SMS are **never** persisted or transmitted
  before the gate runs. There is exactly **one** capture path (no Retriever/Manual fallbacks).

### 4.3 Privacy gate (`features/privacy_gate`) — the cornerstone
Applies, **in order**, on-device, before any storage/network:
1. **Sender whitelist** — drop if `sender ∉ allowed_senders`.
2. **Negative keywords** — drop if body matches `negative_keywords` (OTP/PIN/verify/…), even from a
   whitelisted sender.
3. **Positive keywords** — drop if body matches no `positive_keywords` (received/credited/TrxID/…).
4. **Pass** → hand off to crypto + queue.

`FilterRules` come from `GET /api/mobile/v1/config/filter-rules`, cached locally, refreshed every
`check_interval_hours`. **Fail-closed:** if rules are missing/expired/unfetchable, the effective
whitelist is **empty** (capture nothing). See [docs/SECURITY.md](docs/SECURITY.md) §Privacy gate.

### 4.4 Crypto (`core/crypto`)
`AesGcmCipher` encrypts a passed message with the per-device AES-256 key into the server's envelope:
`base64( IV(12 bytes) ‖ ciphertext ‖ GCM-tag(16 bytes) )`. Must be **byte-for-byte decryptable** by the
server's `SmsParserService::decryptSmsPayload`. The key never leaves `SecureStore` in plaintext.

### 4.5 Offline sync (`features/sync`)
- **Queue:** Hive box `sms_queue` (durable). New gate-passed messages are inserted `status=pending`
  carrying only the **encrypted** payload (never plaintext).
- **Worker:** on connectivity + periodically, batch-select `status IN (pending, failed) AND retry < 5`,
  `POST /api/mobile/v1/sms` (batch), then map per-result: `accepted → approved (+server_ref)`;
  `401 → failed: re-pair`; `5xx/timeout → failed: retry++ (exponential backoff)`.
- **Durability:** nothing is dropped on error; the queue survives restarts; `approved` rows auto-purge
  after 30 days, `failed` rows persist until the user clears them.

### 4.6 Notifications (`features/notifications`)
Poll `GET /api/mobile/v1/notifications` every 10–15 s (interval server-configurable) from within the
foreground service → raise native notifications via `flutter_local_notifications` → `POST
…/notifications/acknowledgements` with the handled `ids`. **No push provider.**

### 4.7 Dashboard (`features/dashboard`)
`GET /api/mobile/v1/dashboard` for today/period stats, recent transactions, unread count, server time.
Last response cached in Hive; offline shows cached data + an "as of <time>" banner; reconnect refreshes.

### 4.8 Background execution (`core/services`)
A single Android **foreground service** (persistent notification "OwnPay is monitoring payments") keeps
SMS capture + notification polling alive, requests battery-optimization exclusion, and restarts on boot/
kill. iOS cannot read SMS — iOS builds expose dashboard/notifications/pairing only (capture is Android).

---

## 5. State management

- One `Bloc`/`Cubit` per feature surface; immutable states (`sealed`/`freezed`-style unions:
  `Loading | Data | Error`).
- Blocs depend on **domain use-cases / repository interfaces** (injected), never on `dio`/`hive` directly.
- Long-running concerns (capture stream, sync worker, poller) live in `core/services` singletons that
  Blocs observe — not inside widget state.

---

## 6. Networking & errors

- **Single `Dio`** instance built in DI with: base URL = paired `server_url`; `AuthInterceptor`
  (bearer + one-shot refresh); `CertPinningInterceptor` (release); timeouts; and a normalizing layer
  that converts responses/exceptions into a typed `ApiResult<T>` / `Failure`.
- Every repository returns `Either<Failure, T>` (or an equivalent typed result) — no raw exceptions leak
  to Blocs. UI renders `Failure` as user-facing copy; security-relevant failures (401/revoked) drive the
  re-pair flow.

---

## 7. Local persistence summary

| Store | Tech | Holds | Notes |
|---|---|---|---|
| Secrets | `flutter_secure_storage` | access JWT, refresh token, AES key, `server_url`, device_uuid | Keystore/Keychain; never logged/backed-up |
| `sms_queue` | Hive | encrypted payload, sender, receivedAt, status, retry, server_ref | plaintext SMS never stored |
| `filter_rules` | Hive | cached whitelist + keywords + interval + fetchedAt | fail-closed when stale/missing |
| `dashboard_cache` | Hive | last dashboard snapshot + timestamp | offline display |
| `audit_log` | Hive | matched/ignored decisions (metadata only) | biometric-lock recommended; no OTP/PII bodies |

---

## 8. Backend contract

All endpoints, request/response shapes, auth, and the FIND-019 bootstrap-auth model (resolved) are in
[docs/API_CONTRACT.md](docs/API_CONTRACT.md). Treat issued tokens as **opaque** bearer credentials; do
not branch on JWT claim internals client-side.
