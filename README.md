# OwnPay Console (Mobile App)

[![Flutter](https://img.shields.io/badge/Flutter-stable-02569B?logo=flutter&logoColor=white)](https://flutter.dev)
[![Dart](https://img.shields.io/badge/Dart-3-0175C2?logo=dart&logoColor=white)](https://dart.dev)
[![License](https://img.shields.io/badge/License-AGPL--3.0-orange.svg)](LICENSE)

**OwnPay Console** is the companion mobile application for [OwnPay](https://github.com/own-pay/ownpay), the self-hosted, enterprise-grade, open-source payment gateway. 

The app's core purpose is to read carrier-received Mobile Financial Service (MFS) and bank transaction-receipt SMS (such as bKash, Nagad, Rocket, etc. in Bangladesh), filter them locally on-device, encrypt them with AES-256-GCM, and securely forward them to your self-hosted OwnPay server to **automatically confirm offline/manual payments**. It also provides a merchant dashboard and real-time transaction notifications.

---

## 📱 Features

* **On-Device SMS Automation:** Read MFS and bank transaction SMS directly and match them to open checkout invoices/payment intents without manual intervention.
* **Privacy-First (Fail-Closed) Gate:** Whitelist sender filtering combined with negative keyword checks (e.g., OTPs, PINs, personal codes, or password-reset messages never leave the device). If rules cannot be fetched from the server, the gate fails closed and captures nothing.
* **Data Sovereignty:** The app connects directly to your own self-hosted server URL. No Firebase, no APNs/FCM, no third-party analytics, and no cloud middlemen.
* **Cryptographic Envelopes:** All whitelisted SMS payloads are encrypted with AES-256-GCM before transmission or local storage.
* **Secure Storage:** Sensitive items (JWT tokens, refresh tokens, per-device AES keys, server URL) are stored exclusively in platform secure storage (Android Keystore / iOS Keychain).
* **Certificate Pinning:** Features Release Trust-On-First-Use (TOFU) certificate pinning to prevent Man-in-the-Middle (MITM) attacks on self-hosted domains.
* **Local Audit Trail:** Users can inspect gate decisions and sync histories directly on the device with a secure "tap to reveal" decrypted text option (decrypted only in memory, never persisted or logged in plaintext).
* **Native Foreground Service:** Runs as a persistent Android foreground service with an ongoing notification to guarantee reliable, continuous monitoring and survive OS battery-saving/Doze modes.

---

## 🛠️ Tech Stack

* **Framework:** [Flutter](https://flutter.dev) (stable channel) · Dart 3 (sound null safety)
* **State Management:** `flutter_bloc` (Cubit/Bloc pattern)
* **Dependency Injection:** `get_it` + `injectable`
* **Navigation:** `go_router`
* **Network client:** `dio` (with single-flight JWT token refresh interceptors)
* **Offline Databases:** `hive` (for non-sensitive cached configurations and the encrypted sync queue)
* **Secrets Storage:** `flutter_secure_storage`
* **QR Pairing:** `mobile_scanner`
* **Local Notifications:** `flutter_local_notifications`

> [!NOTE]
> **iOS Platform Constraint:** Direct SMS interception (`READ_SMS` / `RECEIVE_SMS`) is only supported on Android due to iOS platform security restrictions. On iOS, the app functions as a dashboard and payment notification console.

---

## 🚀 Getting Started

### Option 1: Install the Pre-built APK (Recommended for Android Users)

We provide pre-built APKs for users who want to run the application immediately without setting up a build environment.

1. **Download:** Go to the [Releases](https://github.com/ownpay/ownpay/releases) page on GitHub and download the latest `ownpay-console.apk`.
2. **Install:** Sideload the APK on your Android device (you may need to enable "Install from unknown sources" in your browser/file manager settings).
3. **Pairing:**
   * Go to your OwnPay Admin Panel (accessible on your master domain).
   * Navigate to **Mobile & SMS** -> **Devices** -> **Pair New Device**.
   * Scan the pairing QR code shown in the web browser with the mobile app camera.
4. **Grant Permissions:**
   * **SMS Permission:** Grant `READ_SMS` and `RECEIVE_SMS` when prompted. This is necessary for the app to automate payment confirmations.
   * **Notifications:** Grant permission to display notifications so you receive instant alerts on new payments.
   * **Battery Optimization Bypass:** Go to Android Settings -> Apps -> Special App Access -> Battery Optimization, select OwnPay Console, and choose **Don't Optimize** (or "Unrestricted") to prevent Android from killing the foreground service.

---

### Option 2: Building from Source

To build the app yourself, make sure you have the [Flutter SDK](https://docs.flutter.dev/get-started/install) installed and configured on your system.

#### Prerequisites

* Flutter SDK (stable channel)
* Android SDK (for Android builds, SDK version 34+)
* Xcode & CocoaPods (for iOS builds, macOS required)
* Java Development Kit (JDK 17+)

#### 1. Setup

Clone the repository and fetch dependencies:

```bash
cd mobile-app
flutter pub get
```

#### 2. Run Debug Mode

To launch the app on a connected emulator or physical device:

```bash
flutter run
```

#### 3. Run Code Analysis & Tests

We enforce strict linting rules and require all tests to pass:

```bash
flutter analyze
flutter test
```

#### 4. Building the Production Release (Android APK & App Bundle)

Before building, set up your Android release signing key. Create a file named `android/key.properties` (this file is git-ignored):

```properties
storePassword=your-keystore-password
keyPassword=your-key-password
keyAlias=your-key-alias
storeFile=/path/to/your/keystore.jks
```

Build the release APK:

```bash
flutter build apk --release
```

Build the Android App Bundle (AAB) for Google Play:

```bash
flutter build appbundle --release --obfuscate --split-debug-info=build/app/outputs/symbols
```

Build split APKs per ABI (significantly reduces download sizes when sideloading):

```bash
flutter build apk --split-per-abi --release
```

#### 5. Building the Production Release (iOS IPA)

To build the iOS archive:

```bash
flutter build ipa --release
```

---

## 🏛️ Play Store Availability

The OwnPay Console mobile app will **soon be available on the Google Play Store**. 

We utilize Google Play's **"SMS-based financial transactions"** exception to safely request the `READ_SMS` and `RECEIVE_SMS` permissions. We guarantee absolute compliance with Play Store policies:
1. **Prominent Disclosure:** A full-screen disclosure is shown to the user on first launch explaining exactly *what* is read, *why* it is read, and *how* the data is processed.
2. **Fail-Closed Privacy Gate:** OTPs, PINs, and personal messages are immediately filtered and deleted on-device before hitting the sync queue or network.
3. **Data Protection:** Payloads are encrypted end-to-end, and the app never shares data with any third-party services.

---

## 🔒 Security Policy & Logging Discipline

For security, the application enforces a strict logging discipline:
* **Never log** SMS bodies (raw or decrypted), access/refresh tokens, or the per-device AES encryption keys—even in debug builds.
* All network requests are routed through a single certificate-pinned HTTP client.
* To report security vulnerabilities, please refer to the main repository's [SECURITY.md](https://github.com/own-pay/ownpay/SECURITY.md) guidelines.

---

## 📄 License

This mobile application is licensed under the GNU Affero General Public License v3.0 (or later). See [LICENSE](LICENSE) for details.
