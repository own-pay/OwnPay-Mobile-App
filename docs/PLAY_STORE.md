# OwnPay Console — Google Play SMS Compliance & Release Strategy

> How a **single** Play Store app legitimately reads bank/MFS SMS. Grounded in Google Play's *"Use of SMS
> or Call Log permission groups"* policy and the **Apr 10 2025 / Jul 10 2025** updates (current as of
> 2026-06; **re-verify the live policy + form wording at submission**). This is the decisive constraint —
> it is why the dual-flavor / SMS-Retriever design was rejected (see [ROADMAP.md](ROADMAP.md)).

---

## 1. Why direct `READ_SMS` is the only viable mechanism

| Option | Reads third-party bank SMS? | Verdict |
|---|---|---|
| **SMS Retriever API** | ❌ No — only the app's *own* OTP message carrying the app hash | Cannot perform the core function |
| **SMS User Consent API** | ⚠️ One message, user-prompted each time, time-boxed | Not viable for continuous monitoring |
| **Notification listener** | ⚠️ Unreliable/truncated/locale-dependent; Play disfavors it here | Rejected |
| **Manual share** | ⚠️ User forwards each SMS by hand | Defeats the automation |
| **`READ_SMS` + `RECEIVE_SMS`** | ✅ Yes | **The only mechanism**, allowed via an exception use case |

So the app declares `READ_SMS` + `RECEIVE_SMS` and qualifies under an **exception use case** (no
default-SMS-handler requirement).

---

## 2. The exception use case to declare

Declare primarily **"SMS-based financial transactions"** (*"e.g. UPI, verifications for financial
transactions"*), with **"SMS-based money management"** as the secondary framing for the merchant ledger
view. Both permit `READ_SMS` + `RECEIVE_SMS` without being the default handler.

**Request the minimum:** `READ_SMS` + `RECEIVE_SMS` only. Do **not** declare `SEND_SMS`,
`RECEIVE_MMS`/`WAP_PUSH`, or any Call-Log permission.

---

## 3. Permissions Declaration Form — the four pillars

The Console declaration is mandatory and graded on four pillars. Address each explicitly and make the
store listing, first-run UX, data-safety form, and in-app disclosure all **say the same thing** (reviewers
cross-check consistency).

1. **Core functionality.** State plainly: *"The app's core function is to automatically confirm offline
   mobile-money payments by reading carrier transaction-receipt SMS and matching them to the user's
   self-hosted OwnPay gateway."* SMS access is inseparable from the primary purpose. Keep the dashboard
   visibly secondary — it is the console *for* the SMS automation.
2. **No less-sensitive alternative.** Pre-empt the #1 rejection reason: document why each alternative in
   §1 fails — the receipt SMS is the *only* machine-readable confirmation for the bank-SMS/personal-
   wallet rails OwnPay targets (no server-to-server API exists for them).
3. **Prominent disclosure + runtime consent.** Show the full-screen disclosure (what / why / where /
   what-is-ignored) **before** the OS permission dialog, gated behind an explicit affirmative tap. The app
   must remain usable if declined (manual-confirm mode). See [DESIGN.md](../DESIGN.md) §4.2.
4. **Data-safety honesty.** Declare SMS-message collection, processed for app functionality, **not shared
   with third parties**; emphasize on-device filtering and the user-controlled destination (their own
   server).

---

## 4. The privacy gate is the strongest compliance asset

The Apr-2025 update specifically restricts financial apps from exfiltrating non-financial/personal SMS.
OwnPay's on-device gate ([SECURITY.md](SECURITY.md) §2) reads **only** whitelisted financial senders and
discards everything else (OTPs/PINs/personal) **before anything leaves the phone**. Plus: the app is
**self-hosted** — data goes only to the user's own server, with **no OwnPay cloud, no third-party
transit, no shared analytics**. This is the cleanest possible posture for the declaration.

---

## 5. Approval-risk assessment (be realistic)

- Even eligible apps face **manual review** and frequent first-pass rejections ("declaration does not
  match core functionality"). Mitigate by centering the SMS-automation purpose in the listing, app name,
  and first-run.
- **Provide a review demo account + screencast** showing: pairing → the disclosure → a whitelisted bank
  SMS matched → a personal/OTP SMS **ignored on-device** (the privacy log makes this visible).
- **Residual risk:** if rejected, the fallback is *not* a second sideload build (that contradicts the
  one-app rule) — it is to iterate the declaration/listing with Google. Plan time for 1–2 review cycles.

---

## 6. Pre-submission checklist

- [ ] `READ_SMS` + `RECEIVE_SMS` only in the manifest; no `SEND_SMS`/Call-Log.
- [ ] Declaration form completed against the four pillars (§3); wording matches listing + disclosure +
      data-safety.
- [ ] Full-screen disclosure precedes the runtime request; decline path works.
- [ ] Data-safety section: SMS collected, for functionality, not shared, encrypted in transit.
- [ ] Demo video + reviewer test account prepared (shows ignore-OTP behavior).
- [ ] Privacy policy URL live; describes on-device filtering + self-hosted destination.
- [ ] Release build obfuscated, cert-pinned, `allowBackup=false`, no cleartext traffic.
- [ ] Re-verified the live Play policy + form wording on the submission date.

**Sources** (re-check at submission):
- Use of SMS or Call Log permission groups — Play Console Help (answer 10208820)
- Policy announcement Apr 10 2025 (answer 15899442) · Jul 10 2025 (answer 16296680)
- Declare permissions for your app (answer 9214102)
