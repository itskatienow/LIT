# LIT — Lactation Induction Tracker

A Flutter app for tracking an induced-lactation protocol: daily medication,
pumping output, and reminders. All data stays on the device.

## Pages

- **Dashboard**: log a day (today by default; use the arrows or the calendar to
  change the date). The header shows the phase (Prime, Switch or Supply), the day
  count and the next milestone. Inputs are Estradiol (a switch, or a 0–2 counter when
  sublingual), Progesterone, Domperidone tablets (+/−), Pumped → sessions, power pumped and total output (mL), and notes.
  Changes save automatically. The day's timed schedule is listed at the bottom.
- **Trends**: total output, latest 7-day average, highest day, total pump sessions,
  estimated domperidone remaining (and how long it lasts on the ramp-up), a
  daily output chart (7/14/30 days), logged-vs-scheduled adherence, and recent days.
- **Settings**: start date (Day 1), key dates, estradiol method and dose, progesterone dose, domperidone tablet count, times for the
  "morning/evening/nightly" items, reminders, backup export/restore, and clearing logged data.

## Protocol rules

All numbers are in [`lib/models/protocol.dart`](lib/models/protocol.dart). Day 1 is the start date.

| | |
|---|---|
| Prime | Days 1–40 (hormones build up) |
| Switch | Days 41–42 (progesterone stops, pumping starts) |
| Supply | Day 43 onward |
| Domperidone | Days 1–7: 10 mg at 6 AM, noon, 6 PM · Days 8–14: 20 / 10 / 20 mg · Day 15+: 20 mg at 6 AM, noon, 6 PM, midnight |
| Estradiol | Set in Settings (ongoing). **Injection**: weekly dose ÷ 1, 2 or 3 injections, rounded up to the next 0.5 mg, with the mL to draw from the vial strength. 3 a week: Wed AM, Fri PM, Sun AM · 2 a week: Wed AM, Sat PM · 1 a week: Wed AM. Default 6 mg a week over 3 (2 mg each). **Oral**: the daily dose once, in the morning. **Sublingual**: half the daily dose morning and evening |
| Progesterone | Nightly, Days 1–40. Dose set in Settings (default 300 mg) |
| Pumping | From Day 41: 6 AM, 9 AM, noon, 3 PM, 6 PM, 9 PM, midnight, 3–4 AM (15–20 min) |
| Power pumping | From Day 56, once each evening: 20 pump / 10 rest / 10 pump / 10 rest / 10 pump |

Domperidone is counted in 10 mg tablets (a 20 mg dose = 2 tablets).

## Reminders

Local notifications on Android and iOS (not on web). Turn them on in Settings.
Doses and pumps due at the same time are combined into one notification. LIT schedules
the next **7 days** of reminders and tops them up whenever the app is opened or settings
change. **Open the app at least once a week to keep reminders going.**
Reminders use exact alarms (`USE_EXACT_ALARM`, granted automatically on Android 13+).

Developer tools: in LIT Dev (debug/profile builds), Settings → Reminders also has
**Send a test notification** and **Test a scheduled reminder** (arrives in a minute through
the same alarm path as real reminders). They're hidden in the release app unless it's built
with `--dart-define=LIT_DEBUG_TOOLS=true` (see `lib/config.dart`).

## Backups

Settings → **Backup & data** → **Export backup** saves a JSON file with your settings and
every logged day. Use Android's save dialog to put it somewhere off the phone (e.g. Google
Drive). **Restore from backup** replaces everything in the app with a backup's contents.

## Two apps: LIT and LIT Dev

| Build | App ID | Name on phone | Signed with |
|---|---|---|---|
| release | `com.lactationinductiontracker.app` | LIT | your release key |
| debug / profile | `com.lactationinductiontracker.app.dev` | LIT Dev | the debug key |

They install side by side with separate data, so running a debug build never replaces
or wipes the real app. If both have reminders on, you'll get duplicate notifications,
so keep reminders off in LIT Dev.

### Installing or updating the real app

In VS Code press **Ctrl+Shift+B** (task *Install LIT on phone*), or run
`powershell -ExecutionPolicy Bypass -File android\install-release.ps1`. It builds a
release APK, updates the app in place with `adb install -r` (data kept), and opens it so
reminders get scheduled.

Don't use these for the real app:
- **`flutter run --release`** (or a release launch config): stopping the session
  force-stops the app, and Android then deletes all its scheduled reminders until LIT is
  next opened.
- **`flutter install`**: it uninstalls the old version first, which **deletes all data**.

On Samsung phones, also add LIT under Settings → Battery → Background usage limits →
**Never sleeping apps**, so the phone never puts it into deep sleep (which blocks reminders).

## Release signing (one-time setup)

```powershell
powershell -ExecutionPolicy Bypass -File android\create-release-key.ps1
```

This prompts for a password, creates `Documents\LIT Signing Key\lit-release.jks`, and
writes `android/key.properties` (git-ignored). **Back up the keystore and its password.**
Android only installs an update over the existing app when it's signed with the same
key; without it you'd have to uninstall LIT, which deletes its data. Restore from a
backup file if that ever happens.

Without `key.properties`, release builds fall back to the debug key and print a warning.

## Development

```sh
flutter pub get
flutter run            # debug build -> "LIT Dev"
flutter test
flutter analyze
```

App icon: the source images are in `lib/assets/` (see `flutter_launcher_icons.yaml`).
After changing them, run `dart run flutter_launcher_icons`.
