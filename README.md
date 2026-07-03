# Garden Ninja

Garden Ninja is a swipe-action Flutter game prototype. Slash hostile weeds, protect friendly flowers, collect bonuses, and spend seeds on tool upgrades.

## Gameplay

- Swipe or tap weeds to build combo and score.
- Tougher weeds take 2-3 cuts and shed pieces in the direction of the slash.
- Avoid protected flowers; hitting them costs hearts.
- Use Sun, Water, and Ice power-ups during a run.
- Earn seeds from level results and spend them in the upgrade screen.
- Playfield backgrounds rotate across garden variants as levels advance.

### My Garden

- Tend a persistent garden: plant, water, and harvest on real-world timers.
- A daily visit streak grows milestone gifts (days 3/7/14/30), with a grace
  day so missing one day never resets it.
- Water everything and clear weeds to stamp the day "tended" - a tended
  garden means the ninja leaves a gift by a plot the next morning.
- A forecast line always shows the next thing worth coming back for.
- Expanding the garden unlocks two real meadow plots at levels 2 and 3.
- The garden follows your clock (dawn, day, dusk, night tints) and switches
  to the calm music track while you tend.
- Returning after 6+ hours shows a gentle recap of what grew while away.
- Optional local notifications (asked after your first planting/watering)
  ping you when a plant is ready, when the morning gift arrives, and once
  if the garden has been quiet for three days.

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
