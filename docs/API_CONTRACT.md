# OwnPay Console — Backend API Contract

> The REST contract the app integrates against. Endpoints are served by the OwnPay PHP backend
> (`../src/Controller/Api/Mobile/*`). Shapes below reflect the agreed design; **verify exact field names
> against the controllers** before wiring each call. Base path: `{server_url}/api/mobile/v1`.

---

## 0. Bootstrap auth model — FIND-019 (RESOLVED)

> ✅ **Already fixed in the backend** (committed 2026-06-11) and guarded by
> [`../../tests/Integration/MobileBootstrapRouteTest.php`](../../tests/Integration/MobileBootstrapRouteTest.php).
> No backend action required — documented here because it defines the auth model in §1.

**The hazard (historical).** If **every** mobile route (including pairing) sat in the `mobile` group
`[Cors, RateLimiter, JwtAuth]`, `JwtAuthMiddleware` would return **401** whenever no bearer token is
present — but a fresh device has none and authenticates pairing with the **OTP in the request body**, so
pairing would be rejected before it ran.

**The fix (in place now).** The two bootstrap routes live in a JWT-free `mobile-bootstrap` group:

```php
// config/middleware.php
'mobile-bootstrap' => [\OwnPay\Middleware\CorsMiddleware::class, \OwnPay\Middleware\RateLimiterMiddleware::class],
// config/routes/api.php
$router->post('/api/mobile/v1/devices', 'Api\\Mobile\\DeviceController@pair', 'mobile-bootstrap');
$router->post('/api/mobile/v1/devices/token-refreshes', 'Api\\Mobile\\DeviceController@refresh', 'mobile-bootstrap');
```

Pairing stays authenticated by the single-use `FOR UPDATE` OTP; refresh by the refresh-JWT in the body.
Everything else stays under `mobile` (JWT-gated). The regression test asserts exactly this: pairing &
refresh resolve to a middleware stack **without** `JwtAuthMiddleware`, the bootstrap routes keep CORS +
rate-limiting, and the authenticated surface keeps the JWT gate.

---

## 1. Authentication model

- **Bootstrap** (`mobile-bootstrap`, no bearer): `POST /devices` (OTP in body), `POST
  /devices/token-refreshes` (refresh token in body).
- **Authenticated** (`mobile`, bearer required): everything else. Send `Authorization: Bearer <access>`.
- **Tokens** (treat as opaque): **access ≈ 15 min** (`expires_in: 900`), **refresh ≈ 30 days**, rotated
  on each refresh (old `jti` blacklisted). HS256, with `iss`+`aud` required server-side and a device
  fingerprint bound at pairing.
- **On 401**: perform exactly one refresh, store the rotated pair, retry once. If refresh fails →
  **re-pair required** (stop the sync worker; prompt the user).
- **Transport**: HTTPS only, **certificate-pinned in release**.

### Standard envelope
Success and error bodies are JSON. Treat any non-2xx (or `success:false`) as a `Failure`; surface `error`
/`message` to the UI. Example error:
```json
{ "success": false, "error": "INVALID_OTP", "message": "Pairing code is invalid or expired" }
```

---

## 2. Endpoints

| # | Method | Path | Group | Purpose |
|---|---|---|---|---|
| 1 | POST | `/devices` | bootstrap | Pair with OTP → tokens + AES key |
| 2 | POST | `/devices/token-refreshes` | bootstrap | Rotate access token |
| 3 | POST | `/devices/heartbeats` | mobile | Liveness ping |
| 4 | GET | `/devices/statuses` | mobile | Connection/device status |
| 5 | DELETE | `/devices/{id}` | mobile | Revoke this/other device |
| 6 | POST | `/devices/bulk-revocations` | mobile | Bulk revoke |
| 7 | POST | `/sms` | mobile | Ingest GCM-encrypted SMS (single/batch) |
| 8 | GET | `/sms/queues` | mobile | Outbound SMS queue (if used) |
| 9 | GET | `/notifications` | mobile | Poll pending notifications |
| 10 | POST | `/notifications/acknowledgements` | mobile | Acknowledge handled notifications |
| 11 | GET | `/dashboard` | mobile | Dashboard data |
| 12 | GET | `/config/filter-rules` | mobile | On-device privacy-gate config |

---

## 3. Key request/response shapes

### (1) `POST /devices` — pair
```jsonc
// request
{ "pairing_code": "482910", "device_name": "Galaxy A54",
  "device_id": "<androidId>:<certSha256>", "app_version": "1.0.0", "platform": "android" }
// response 201
{ "success": true, "access_token": "<jwt>", "refresh_token": "<token>",
  "expires_in": 900, "aes_key": "<hex_64>", "device_uuid": "<uuid>" }
```
Store all secrets + `server_url` in secure storage. The `aes_key` is the per-device AES-256 key for §7
payloads.

### (2) `POST /devices/token-refreshes` — refresh
```jsonc
// request  { "refresh_token": "<token>" }
// response { "success": true, "access_token": "<jwt>", "refresh_token": "<rotated>", "expires_in": 900 }
```

### (7) `POST /sms` — ingest (batch)
```jsonc
// request (JWT)
{ "messages": [
  { "local_id": 42, "encrypted_payload": "<base64 IV‖ct‖tag>",
    "sender": "bKash", "received_at": "2026-05-20T10:30:00+06:00" } ] }
// response 200
{ "success": true, "results": [ { "local_id": 42, "status": "accepted", "server_ref": "sms_abc123" } ] }
```
`encrypted_payload` is the AES-256-GCM envelope of the **SMS body** (§7). The plaintext body is never
sent. Map results: `accepted → approved`; reject/error → keep queued per [ARCHITECTURE.md](../ARCHITECTURE.md) §4.5.

### (12) `GET /config/filter-rules` — privacy-gate config
```jsonc
{ "success": true, "version": 1, "updated_at": "2026-05-20T10:00:00Z",
  "allowed_senders": ["bKash","16247","Nagad","DBBL"],
  "positive_keywords": ["received","credited","TrxID","TxnID","deposited","Tk","BDT"],
  "negative_keywords": ["OTP","PIN","password","verify","verification","code"],
  "check_interval_hours": 24 }
```
Cache locally; refresh every `check_interval_hours`. **Fail-closed** if unavailable (empty whitelist).

### (9) `GET /notifications` / (10) acknowledgements
Poll returns device-scoped pending notifications `[{id,type,title,body,payload,created_at}]`; ack with
`{ "ids": [...] }`.

### (11) `GET /dashboard`
Returns today/period stats, recent transactions, unread count, and `server_time`. Cache for offline.

---

## 4. Verified security primitives (server-side, for context)

- **OTP**: 6-digit CSPRNG, sha256-stored, 5-min expiry, **single-use** (`SELECT … FOR UPDATE`), rate-
  limited 5/300s per admin, prior OTPs invalidated on regen.
- **JWT**: HS256 (alg-pinned), CSPRNG `jti`, refresh rotation blacklists the old `jti`, device status +
  fingerprint re-checked on refresh; `iss`+`aud` required.
- **GCM transport**: AES-256-GCM, `IV(12)‖ciphertext‖tag(16)`, 32-byte key validated; per-device key
  stored encrypted server-side.
- **Brand isolation**: every call is tenant-scoped from the JWT `mid` claim.

> These are the server's guarantees; the app's job is to uphold its half (secure storage, fail-closed
> gate, cert pinning, no logging). See [SECURITY.md](SECURITY.md).
