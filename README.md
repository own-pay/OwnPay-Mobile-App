# OwnPay Console (Mobile)

A **single Flutter app** for Google Play that turns a phone into a payment-confirmation device for a
**self-hosted OwnPay** server. It reads carrier mobile-money / bank **transaction-receipt SMS**, filters
them **on the device**, and securely forwards only the whitelisted *financial* messages to the merchant's
**own** server — so offline MFS payments (bKash, Nagad, Rocket, …) are confirmed automatically. It also
provides a live dashboard and payment notifications.

> **Status:** under active development. The PHP backend (`../`) is built; this folder is the Flutter app.
> Read **[CLAUDE.md](CLAUDE.md)** before writing any code, and **[docs/ROADMAP.md](docs/ROADMAP.md)** for
> what is done vs pending.

---

## Documentation map

| Document | Purpose |
|---|---|
| **[CLAUDE.md](CLAUDE.md)** | Operating rules & non-negotiables. **Start here.** |
| **[ARCHITECTURE.md](ARCHITECTURE.md)** | Layers, modules, data flows, `lib/` layout. |
| **[DESIGN.md](DESIGN.md)** | Design system, screens, flows, accessibility, localization. |
| **[docs/API_CONTRACT.md](docs/API_CONTRACT.md)** | Backend REST contract + FIND-019 bootstrap-auth note (resolved). |
| **[docs/SECURITY.md](docs/SECURITY.md)** | Threat model, crypto envelope, secrets, the privacy gate. |
| **[docs/PLAY_STORE.md](docs/PLAY_STORE.md)** | SMS-permission compliance & approval strategy. |
| **[docs/ROADMAP.md](docs/ROADMAP.md)** | Decision record + phased build checklist (live status). |

## The one rule that shapes everything

**One app, one build**, Play-Store only, capturing SMS with `READ_SMS`/`RECEIVE_SMS` under Play's
*"SMS-based financial transactions"* exception — **not** a flavor split, **not** SMS Retriever.
Everything that leaves the phone is filtered on-device and sent only to the user's own server.

---

## Verify (this is the bar — keep it green)

```bash
flutter analyze        # static analysis (strict; must be clean)
flutter test           # unit tests (crypto, privacy gate, sync, …)
flutter build apk --debug   # full compile incl. native Android
```

## Prerequisites

- **Flutter SDK** (stable) + Android toolchain (`flutter doctor`).
- A reachable **OwnPay server** running the mobile API. (FIND-019 — the pairing/refresh bootstrap-auth
  fix — is **already in the backend**; see [CLAUDE.md](CLAUDE.md) §4.)
- An admin account to generate device-pairing OTP/QR.

See [docs/SECURITY.md](docs/SECURITY.md) for release hardening (cert pinning, obfuscation, secure
storage) and [docs/PLAY_STORE.md](docs/PLAY_STORE.md) for the listing + SMS declaration.
