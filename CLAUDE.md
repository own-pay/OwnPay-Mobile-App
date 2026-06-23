# OwnPay Console — Mobile App Operating Rules

> This file governs all work inside `mobile-app/`. The repository-root `CLAUDE.md` (senior-engineer
> discipline, "no placeholders / no stubs", security-by-default, change-documentation rules) still
> applies in full. The rules below **add** mobile-specific context and **non-negotiables**. Where this
> file is more specific than the root, follow this file for mobile work.

---

## 1. What this app is

The **OwnPay Console** is a **single Flutter app** published on **Google Play**. It pairs to a
**self-hosted** OwnPay server, reads carrier **MFS/bank transaction-receipt SMS** (bKash, Nagad,
Rocket, …), filters them **on-device**, and forwards only whitelisted *financial* SMS — AES-256-GCM
encrypted — to the **user's own** OwnPay server to **auto-confirm offline payments**. It also shows a
dashboard and payment notifications.

The SMS-automation purpose is the app's **core function**; the dashboard is the management surface *for*
that purpose, never the headline.

---

## 2. Non-negotiables (the product's identity — do not "improve" these away)

1. **One app, one build.** No build flavors, no sideload-vs-playstore split. The dual-flavor design in
   `../docs/v2/mobile_app/` is **rejected** — see [ROADMAP.md](ROADMAP.md) §Decision.
2. **SMS capture = `READ_SMS` + `RECEIVE_SMS`** via Play's *"SMS-based financial transactions"*
   exception. **Do NOT** use the SMS Retriever API or Manual-Share as the primary capture path — they
   cannot read third-party bank SMS. See [docs/PLAY_STORE.md](docs/PLAY_STORE.md).
3. **On-device privacy gate is mandatory and FAIL-CLOSED.** OTPs, PINs, login codes, and personal SMS
   **never leave the device**. If filter rules cannot be loaded (offline/first-run), the whitelist is
   **empty** → send nothing. See [docs/SECURITY.md](docs/SECURITY.md).
4. **Data sovereignty.** The app talks **only** to the user's own OwnPay server (URL set at pairing).
   **No Firebase, no APNs, no third-party analytics/crash/cloud, no external AI.** Notifications are
   **poll-based**.
5. **Secrets** (access JWT, refresh token, per-device AES key) live in **platform secure storage**
   (Android Keystore / iOS Keychain) **only** — never in Hive, SharedPreferences, logs, or backups.
6. **Production-ready only.** No `TODO`/placeholder/stub in delivered code. **Never log** SMS bodies,
   tokens, AES keys, or decrypted payloads — not even in debug builds.

---

## 3. Tech stack (locked — change only with a documented reason)

| Concern | Choice |
|---|---|
| Framework / language | Flutter (stable channel) · Dart 3 (sound null safety) |
| State management | `flutter_bloc` (Cubit/Bloc) |
| Dependency injection | `get_it` + `injectable` |
| Navigation | `go_router` |
| HTTP | `dio` (single client; interceptors: bearer-attach, 401 auto-refresh, cert-pin in release) |
| Offline storage | `hive` / `hive_flutter` (queue + caches; **non-secret data only**) |
| Secret storage | `flutter_secure_storage` |
| QR pairing | `mobile_scanner` |
| Local notifications | `flutter_local_notifications` |
| Connectivity | `connectivity_plus` |
| Crypto | `cryptography` or `pointycastle` — AES-256-GCM, byte-compatible with the server (see SECURITY.md) |
| Background | Android foreground service (persistent "monitoring payments" notification) |

Per root rule §4: add a dependency only if it is actively maintained, the community standard, free of
known CVEs, and not replaceable by a few lines of native code.

---

## 4. The backend

The PHP backend already exists at the repository root (`../`). Mobile endpoints live under
`/api/mobile/v1/*` — the integration contract is [docs/API_CONTRACT.md](docs/API_CONTRACT.md).

> ✅ **FIND-019 — resolved.** The pairing and token-refresh routes (`POST /api/mobile/v1/devices`,
> `POST /api/mobile/v1/devices/token-refreshes`) run in the JWT-free `mobile-bootstrap` middleware group,
> so a fresh (token-less) device **can** pair: it authenticates with the OTP in the body, and refresh
> uses the refresh-JWT in the body. Fixed in the backend 2026-06-11 and guarded by
> `../tests/Integration/MobileBootstrapRouteTest.php`. The rest of `/api/mobile/v1/*` stays JWT-gated.

---

## 5. Conventions

- **Feature-first layout**: `lib/features/<feature>/` (presentation / domain / data), with `lib/core/`
  for cross-cutting concerns. See [ARCHITECTURE.md](ARCHITECTURE.md).
- **All network I/O** goes through the single Dio client — never construct ad-hoc HTTP calls.
- **Money is never a `double`.** Use `Decimal`/string and mirror the server's `DECIMAL(20,6)` precision.
- **No silent failures.** Surface errors as Bloc states. A failed SMS stays in the queue and is retried;
  it is **never silently dropped** (dropping is reserved for the privacy gate, by design).
- **Time**: store/transmit ISO-8601 with timezone; the device clock is untrusted for security decisions.
- **Comments** explain *why* (especially around the privacy gate and crypto), not *what*.

---

## 6. Testing & definition of done

- The **privacy gate**, **crypto envelope**, **sync worker**, and **JWT auto-refresh** require
  exhaustive unit tests. The privacy gate is the compliance cornerstone — test every drop/pass branch,
  including the fail-closed path.
- Critical flows (pairing, disclosure consent, sync) get widget/integration tests.
- A change is **done** when: implemented fully (no stubs), `flutter analyze` is clean, tests pass, the
  privacy/security invariants in §2 hold, and any architectural change is reflected in the docs here.
