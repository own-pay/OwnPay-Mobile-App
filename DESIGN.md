# OwnPay Console — Design (UI/UX)

> Visual + interaction design for the app. Pairs with [ARCHITECTURE.md](ARCHITECTURE.md). The
> **permission disclosure** screen (§4.2) is compliance-critical — see [docs/PLAY_STORE.md](docs/PLAY_STORE.md).

---

## 1. Design principles

1. **Trust through transparency.** The user is letting an app read their SMS — every screen should make
   it obvious *what* is read, *why*, and *where it goes* (their own server). Show, don't hide.
2. **Calm & glanceable.** This runs in the background; the foreground UI is a status/console, not a feed.
   Default to "everything is working" at a glance; surface problems loudly.
3. **Honest states.** Always represent loading / empty / error / offline explicitly. Never a blank screen.
4. **Reachable.** One-handed use, large tap targets (≥48dp), high contrast, full dark-mode, and
   localized (English + Bengala/বাংলা for the primary market).

---

## 2. Visual language

### Color (aligns with OwnPay brand)
| Token | Light | Dark | Use |
|---|---|---|---|
| `primary` | `#0D9488` (teal) | `#2DD4BF` | brand, primary actions |
| `primaryContainer` | `#CCFBF1` | `#134E4A` | selected/active surfaces |
| `success` | `#16A34A` | `#4ADE80` | synced / payment confirmed |
| `warning` | `#D97706` | `#FBBF24` | pending / attention |
| `danger` | `#DC2626` | `#F87171` | failed / revoked / errors |
| `surface` | `#FFFFFF` | `#0F172A` | cards |
| `background` | `#F8FAFC` | `#020617` | app background |
| `onSurfaceMuted` | `#64748B` | `#94A3B8` | secondary text |

Status semantics are consistent everywhere: **teal**=brand, **green**=synced/confirmed,
**amber**=pending, **red**=failed/blocked/revoked.

### Typography
System font stack (Roboto/SF) + a tabular-figure style for money. Scale: `display 28/700`,
`title 20/600`, `body 16/400`, `label 14/500`, `caption 12/400`. Amounts use tabular lining figures so
columns align.

### Spacing & shape
4-pt base grid (`4/8/12/16/24/32`). Cards: `16` radius, subtle elevation. Inputs/buttons: `12` radius,
`48` min height. Generous padding — this is a calm console, not dense.

---

## 3. Component library (`lib/shared/widgets`)

- **StatusChip** — pill with icon + label in the status color (Pending / Synced / Failed / Ignored).
- **MoneyText** — formats `Decimal` with currency, tabular figures, never floats.
- **StatCard** — large number + label + delta (dashboard summary).
- **TxnListTile** — amount, sender/gateway, time, status chip.
- **DisclosureSheet** — the full-screen consent UI (see §4.2); reusable shell with icon, body, accept/deny.
- **OfflineBanner** — top inline banner: "Offline — showing data as of <time>".
- **EmptyState / ErrorState / LoadingState** — standard placeholders with icon + message + optional action.
- **ServerBadge** — shows the paired server host + connection dot (green/amber/red) in the app bar.

---

## 4. Screens & flows

### 4.1 Onboarding / pairing
1. **Welcome** — one screen stating the purpose plainly: "Confirm your mobile-money payments
   automatically by reading bank receipt SMS — sent only to *your* server." Primary: **Pair this device**.
2. **Pair** — `mobile_scanner` camera to scan the web-panel QR; a **Enter manually** affordance (server
   URL + 6-digit OTP) as the accessibility/no-camera path (this is a manual *entry* fallback, **not** an
   alternate SMS-capture method).
3. **Pairing result** — success → continue to disclosure; failure (expired/used OTP, wrong server) →
   clear error + retry.

### 4.2 Permission disclosure (compliance-critical — must come *before* the OS dialog)
A **full-screen** `DisclosureSheet`, not a generic prompt, stating in plain language:
- **What** is accessed: only SMS from whitelisted bank/wallet senders.
- **Why**: to automatically confirm your payments.
- **Where it goes**: encrypted, to **your own** OwnPay server — never sold, never shared, never to any
  third party.
- **What is ignored**: OTPs, PINs, verification codes, and personal messages stay on the phone.

Two explicit buttons: **Allow SMS access** (→ triggers the runtime `READ_SMS`/`RECEIVE_SMS` request) and
**Not now** (→ app still works in a manual/confirm-only mode; capture stays off). The wording here must
match the Play Console declaration and the data-safety form verbatim in spirit.

### 4.3 Home / dashboard
App bar with `ServerBadge`. Content: 2–3 `StatCard`s (today received total, count, last payment),
recent `TxnListTile`s, and a prominent **monitoring status** strip (green "Monitoring active" / amber
"Permission needed" / red "Re-pair required"). `OfflineBanner` when cached. Pull-to-refresh.

### 4.4 Transactions
List (paginated) of confirmed/expected payments → **detail** (amount, gateway, trx id, matched SMS
sender/time, status timeline). Read-only.

### 4.5 SMS audit trail (transparency feature)
Tabs: **All · Synced (✅) · Issues (❌)**. Each row: sender, time, `StatusChip`, and — for issues — the
reason ("Auth error — re-pair", "Server error — retrying"). A separate **Privacy log** (in Settings)
shows *decisions* (matched / ignored-by-rule) as metadata only — never the body of an ignored OTP.

### 4.6 Notifications
In-app list mirroring the native notifications; tap → transaction detail. Acked items move to read.

### 4.7 Settings
- **Device**: name, paired server host, device id, last heartbeat, connection status.
- **Re-pair**: re-run pairing (rotates credentials).
- **Privacy**: view current filter rules (whitelist + keywords), open the privacy log (biometric-gated),
  re-fetch rules.
- **Data**: clear local queue / cached data; **Revoke & wipe** (revokes server-side + secure-wipes
  secrets).
- **About**: version, links to privacy policy.

### Navigation map
```
Welcome → Pair → Disclosure → [Home]
[Home] ⇄ Transactions ⇄ Detail
[Home] → Audit (All|Synced|Issues)
[Home] → Notifications → Detail
[Home] → Settings → {Device, Privacy(+log), Data, About}
```
A `go_router` redirect guard sends un-paired devices to **Welcome** and paired ones to **Home**.

---

## 5. Critical UX details

- **Foreground-service notification**: non-dismissible, low-key — "OwnPay is monitoring payments" with a
  tap-through to Home. Required for reliable background capture; explain it during onboarding so it's not
  alarming.
- **Battery-optimization exclusion**: request with an explanatory screen (why background access matters),
  never silently.
- **Declined permission**: the app must remain usable (dashboard, notifications, manual confirmation) —
  Play requires a working experience without the grant.
- **Re-pair required** state: a single, calm, full-width call-to-action; pause the sync worker and stop
  retry storms until resolved.
- **Empty whitelist (fail-closed)**: if rules can't load, show an amber strip "Waiting for filter rules
  from your server — no SMS is being read yet," not a silent no-op.

---

## 6. Accessibility & localization

- Semantics labels on all interactive elements; min 4.5:1 contrast; dynamic type respected.
- Strings externalized (`flutter_localizations` + ARB). Ship **en** and **bn**; money/date formatted per
  locale. No hardcoded user-facing strings.
