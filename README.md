# Plainday

Simple day control — profiles, one-tap logging, mutual pause between activities.

- **Site:** https://plainday.hexatech.rs  
- **Bundle ID:** `rs.hexatech.plainday`

## Run

```bash
flutter pub get
flutter run
```

## Done so far

### P0 — Foundation
- Generic `Profile` model (presets are configs only)
- Work preset seeded on first launch
- Start/End day
- Task / Meeting / Break with one active timer + resume previous
- Today report
- Local persistence

### P1 — Day control
- Local scheduled notifications from profile config
- Notification actions + permission banner
- Contextual break suggestions + snooze
- Android home-screen widget

### P2 — Presets & reports
- Profiles screen: activate, edit, duplicate, delete
- Profile editor: schedule, days, rules, buttons, breaks, reminders
- Blank + all presets as add sources
- Reports: Today / This week + daily bars
- CSV export/share

## Next (P3+)
- Onboarding polish
- iOS Widget Extension (Xcode)
- Live Activity (later)

## Android widget
Long-press home screen → Widgets → **Plainday**
