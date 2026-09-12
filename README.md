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

- Plan crops in a stone courtyard, then start a 60-second harvest challenge.
- Swipe through matching ripe plants and release to gather a chain. Green fruit
  or a different crop ends the valid chain. Tapping individual crops also works.
- Complete market orders for coins; crops regrow during play and every new round
  starts ready to play. Planting and building are untimed.
- Build a greenhouse for rare crops or a terrace for two additional beds.
  Improve individual beds for double yield. Both landmarks visibly transform
  at every garden level and can be tapped directly after they are built.
- A looping in-game demo shows the harvest gesture, and larger touch targets
  make the plants easier to collect without changing their natural size.
- Greenhouse levels expand the crop roster from strawberries and tomatoes to
  blueberries, pumpkins, eggplants and golden peppers.
- Progress through six garden tiers. Upgrade both landmarks, improve the four
  main beds, and complete the tier's orders to begin the next garden.
- A new tier resets bed improvements and planting work while retaining coins,
  crop unlocks, landmarks and lifetime records. Higher tiers have larger orders,
  new seasonal lighting and more valuable upgrades.
- Progress saves locally, retaining existing player balances and legacy garden
  data. The retired watering/gift reminders are cancelled.

See [the garden implementation notes](docs/harvest-garden.md) for progression,
save compatibility and the approved mockup.

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
