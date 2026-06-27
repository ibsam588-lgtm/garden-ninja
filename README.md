# Garden Ninja

Garden Ninja is a swipe-action Flutter game prototype. Slash hostile weeds, protect friendly flowers, collect bonuses, and spend seeds on tool upgrades.

## Gameplay

- Swipe or tap weeds to build combo and score.
- Avoid protected flowers; hitting them costs hearts.
- Use Sun, Water, and Ice power-ups during a run.
- Earn seeds from level results and spend them in the upgrade screen.

## Project

- Built with Flutter for Android, iOS, and web.
- Generated game art lives in `assets/images/`.
- Runtime sprites are sliced from the source atlas sheets in `assets/images/source/`.

## Run Locally

```bash
flutter pub get
flutter run
```

For web:

```bash
flutter run -d chrome
```

## Checks

```bash
flutter analyze
flutter test
flutter build web
```
