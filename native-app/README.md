# HODOR Native App

Native iOS and Android shells for the existing HODOR attendance system.

## App identity
- Display name: HODOR
- Bundle ID / Android application ID: `com.modernlibrary.hodor`
- Backend: existing Supabase project (same users and data as the website)
- Camera: QR attendance gate and attendance scanning
- Location: attendance geofence validation

## Local build
Requires Node.js 20+, Android Studio + Android SDK for Android, and macOS + Xcode for iOS.

```bash
cd native-app
npm install
npm run copy:web
npx cap add android
npx cap add ios
npx cap sync
```

Open with `npx cap open android` or `npx cap open ios`.

## Automated builds
The GitHub Actions workflow `.github/workflows/native-build.yml` creates:
- An Android debug APK for device testing.
- An unsigned iOS Simulator .app for simulator testing.

Download these from the workflow run's Artifacts section. The iOS Simulator build is not installable on a physical iPhone.

## Store release requirements
A public App Store release needs an Apple Developer Program account, App Store Connect app record, bundle ID confirmation, signing certificates/profiles, privacy disclosures, screenshots, and review. Google Play release needs a Play Console account, store listing, privacy policy/data-safety disclosures, signing key, and a signed Android App Bundle (AAB).

No signing credentials, store account, or private keys are stored in this repository. Do not commit signing keys or service-role Supabase keys. The public Supabase publishable key used by the web app is not a service-role key.

## Important
This first native shell packages the current web UI locally and uses the same Supabase backend. It requires internet for login and database actions. Test QR camera and GPS permissions on actual devices before store submission.
