# OwnPay Console — Security & Privacy Model

> The app handles people's bank SMS. Security and privacy are the product, not a feature. This document
> is binding; deviations require an explicit, documented decision. See [CLAUDE.md](../CLAUDE.md) §2.

---

## 1. Threat model (what we defend against)

| Threat | Defense |
|---|---|
| Personal SMS / OTP exfiltration | On-device **privacy gate**, fail-closed; server-side belt-and-suspenders re-filter |
| Token/key theft from device storage | Secrets in **Keystore/Keychain** only; short access TTL; revocation; no logs/backups |
| Network interception / MITM | HTTPS + **certificate pinning** (release); GCM-encrypted payloads end-to-end to the user's server |
| Stolen access token reuse | ~15-min TTL + server-side device-revocation check on every call + fingerprint binding |
| Malicious/rogue paired device | Admin can revoke/bulk-revoke; refresh re-checks device status + fingerprint |
| Reverse engineering | Release **obfuscation** + ProGuard; no secrets in code; treat all client checks as advisory |
| Config tampering (widening whitelist) | TLS-only `filter-rules`; recommend **signed** config; fail-closed default |

The app is **not** a trust anchor — the server enforces authorization. The app's duty is to never leak
non-financial SMS and never expose secrets.

---

## 2. The on-device privacy gate (compliance cornerstone)

Runs for **every** captured SMS, on-device, **before any persistence or network**. Order matters:

1. **Whitelist** — drop if `sender ∉ allowed_senders`.
2. **Negative keywords** — drop if the body matches `negative_keywords` (OTP/PIN/password/verify/
   verification/code…), **even from a whitelisted sender**.
3. **Positive keywords** — drop if the body matches **no** `positive_keywords`.
4. **Pass** — only now encrypt (§3) and enqueue.

Rules:
- **Fail-closed.** No rules loaded (offline / first run / expired / fetch error) ⇒ **empty whitelist** ⇒
  capture nothing. Never default to an open gate.
- **Dropped means gone.** A dropped SMS is never written to the queue, never encrypted, never logged in
  full. The privacy log may record *that* a message from sender X was ignored by rule Y — **never its
  body**.
- **Exhaustively tested.** Every branch (each drop reason, the pass, and the fail-closed path) has unit
  tests. This is the single most important test suite in the app.
- **Defense in depth.** The server re-applies the negative-keyword filter on ingest; a stale/compromised
  client must not be able to push OTP text into storage.

---

## 3. Cryptography

- **Payload encryption:** AES-256-GCM. Envelope = `base64( IV(12 bytes) ‖ ciphertext ‖ tag(16 bytes) )`,
  **byte-compatible** with the server's `SmsParserService::decryptSmsPayload`. Fresh random 12-byte IV
  per message (never reuse an IV with the same key).
- **Key:** the per-device AES-256 key issued at pairing (hex-64). Lives in `SecureStore` (Keystore/
  Keychain); loaded into memory only for the encrypt call; never logged, never sent back, never copied to
  Hive/prefs.
- **Hashing/randomness:** use the platform CSPRNG for any client-side nonce. No home-rolled crypto — use
  a vetted library (`cryptography`/`pointycastle`).

---

## 4. Secret handling

| Secret | Storage | Lifetime |
|---|---|---|
| Access JWT | SecureStore | ~15 min; refreshed silently |
| Refresh token | SecureStore | ~30 days; rotated each refresh (old one invalid) |
| Per-device AES key | SecureStore | persistent; rotated on re-pair |
| `server_url`, `device_uuid` | SecureStore | persistent |

- **Never** place any of the above in Hive, SharedPreferences, app logs, crash payloads, screenshots, or
  Android auto-backup (set `android:allowBackup="false"`, exclude from backup rules).
- **Single-flight refresh:** the `AuthInterceptor` refreshes at most once per 401 and serializes
  concurrent refreshes to avoid token-rotation races.

---

## 5. Transport & build hardening

- **Certificate pinning** in release builds (pin the user's server cert/public-key; provide a documented
  re-pin path for cert rotation). Debug builds may relax pinning for local dev only.
- **Obfuscation:** `--obfuscate --split-debug-info`; Android ProGuard/R8 rules checked in.
- **No cleartext traffic:** `android:usesCleartextTraffic="false"`.
- **Min SDK** chosen to support runtime SMS permission semantics; document the floor.

---

## 6. Permissions

Declare the **minimum**: `READ_SMS` + `RECEIVE_SMS` only. Do **not** declare `SEND_SMS` (no outbound-SMS
feature ships) or any other SMS/Call-Log permission. Runtime grant is requested **only after** the
full-screen disclosure (see [DESIGN.md](../DESIGN.md) §4.2 and [PLAY_STORE.md](PLAY_STORE.md)).

---

## 7. Local audit trail

- A user-viewable, **biometric-locked** log of gate decisions (matched / ignored-by-rule) and sync
  outcomes — metadata only (sender, time, rule, status), **never** OTP/PII bodies.
- Strengthens user trust and is a strong artifact for Play review (demonstrates the gate works).

---

## 8. Lifecycle: revoke, re-pair, wipe

- **Revoke (server)** → next call/refresh fails → app enters **re-pair required**, stops the sync worker,
  and prompts.
- **Re-pair** rotates all credentials (new AES key, new tokens, new fingerprint binding).
- **Revoke & wipe (in-app)** → call revoke endpoint, then **secure-wipe** all secrets + local queue +
  caches. Leave zero recoverable secret material.

---

## 9. Logging discipline (hard rule)

Never log: SMS bodies (raw or decrypted), tokens, the AES key, `encrypted_payload`, or full request/
response bodies of `/sms`. Log only non-sensitive metadata (counts, statuses, error codes). This holds in
**all** build types — there is no "debug-only" exception for sensitive data.
