# LIT — Lactation Induction Tracker

A Flutter app for tracking an induced-lactation protocol: daily medication,
pumping output, and reminders. All data stays on the device.

## Pages

- **Dashboard**: log a day (today by default; use the arrows or the calendar to
  change the date). The header shows the phase (Build, Birth or Lactation), the day
  count and the next milestone. Inputs are Estradiol, Progesterone, Domperidone
  tablets (+/−), Pumped → sessions, power pumped and total output (mL), and notes.
  Changes save automatically. The day's timed schedule is listed at the bottom.
- **Trends**: total output, latest 7-day average, highest day, total pump sessions,
  estimated domperidone remaining (and how long it lasts on the ramp-up), a
  daily output chart (7/14/30 days), logged-vs-scheduled adherence, and recent days.
- **Settings**: start date (Day 1), key dates, domperidone tablet count, times for the
  "morning/evening/nightly" items, reminders, backup export/restore, and clearing logged data.

## Protocol rules

All numbers are in [`lib/models/protocol.dart`](lib/models/protocol.dart). Day 1 is the start date.

| | |
|---|---|
| Build | Days 1–40 |
| Birth | Days 41–42 |
| Lactation | Day 43 onward |
| Domperidone | Days 1–7: 10 mg at 6 AM, noon, 6 PM · Days 8–14: 20 / 10 / 20 mg · Day 15+: 20 mg at 6 AM, noon, 6 PM, midnight |
| Estradiol | 2 mg: Wednesday morning, Friday evening, Sunday morning (ongoing) |
| Progesterone | 300 mg nightly, Days 1–40 |
| Pumping | From Day 41: 6 AM, 9 AM, noon, 3 PM, 6 PM, 9 PM, midnight, 3–4 AM (15–20 min) |
| Power pumping | From Day 56, once each evening: 20 pump / 10 rest / 10 pump / 10 rest / 10 pump |

Domperidone is counted in 10 mg tablets (a 20 mg dose = 2 tablets).

## Reminders

Local notifications on Android and iOS (not on web). Turn them on in Settings.
Doses and pumps due at the same time are combined into one notification. The OS
limits how many notifications can be queued (iOS: 64), so LIT schedules the next
several days (about 6 on iOS, longer on Android) and tops them up whenever the
app is opened or settings change. **Open the app every few days to keep reminders going.**
On Android 12+, allow "Alarms & reminders" (Settings shows a prompt) for on-time delivery.

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
or wipes the real app. Use the **LIT (release) · real app** launch configuration (or
`flutter run --release`) to install or update the real app. If both have reminders on,
you'll get duplicate notifications, so keep reminders off in LIT Dev.

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
