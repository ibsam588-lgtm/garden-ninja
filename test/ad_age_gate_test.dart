import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:garden_ninja/src/ads/ad_age_gate.dart';
import 'package:garden_ninja/src/ads/ad_age_range.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('unknown ages never default to an ad-eligible range', () {
    for (final invalid in [null, '', 'adult', '18', 'true']) {
      expect(AdAgeRange.parse(invalid), isNull);
    }
    expect(AdAgeRange.under13.allowsAds, isFalse);
    expect(AdAgeRange.teens.allowsAds, isFalse);
    expect(AdAgeRange.older.allowsAds, isTrue);
  });

  for (final range in AdAgeRange.values) {
    testWidgets('${range.label}: choice precedes game startup and persists', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({});
      final events = <String>[];
      await tester.pumpWidget(
        MaterialApp(
          home: AdAgeGate(
            enabled: true,
            onResolved: (value) => events.add(value.storageValue),
            child: Builder(
              builder: (_) {
                events.add('game');
                return const Text('Ready to play');
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(events, isEmpty);
      expect(find.text('Ready to play'), findsNothing);
      expect(find.text('Before you play'), findsOneWidget);
      expect(find.byType(OutlinedButton), findsNWidgets(3));
      await tester.tap(find.byKey(ValueKey('age-${range.storageValue}')));
      await tester.pumpAndSettle();
      expect(events, [range.storageValue, 'game']);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(AdAgeGate.preferenceKey), range.storageValue);
      expect(prefs.getKeys(), {AdAgeGate.preferenceKey});
      expect(find.text('Ready to play'), findsOneWidget);
    });

    testWidgets('${range.label}: restores privacy before creating game', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({
        AdAgeGate.preferenceKey: range.storageValue,
      });
      final events = <String>[];
      await tester.pumpWidget(
        MaterialApp(
          home: AdAgeGate(
            enabled: true,
            onResolved: (value) => events.add(value.storageValue),
            child: Builder(
              builder: (_) {
                events.add('game');
                return const Text('Ready to play');
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(events, [range.storageValue, 'game']);
      expect(find.text('Before you play'), findsNothing);
    });
  }

  testWidgets('malformed preference asks again without starting the game', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({AdAgeGate.preferenceKey: 123});
    AdAgeRange? resolved;
    await tester.pumpWidget(
      MaterialApp(
        home: AdAgeGate(
          enabled: true,
          onResolved: (range) => resolved = range,
          child: const Text('Ready to play'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(resolved, isNull);
    expect(find.text('Ready to play'), findsNothing);
    expect(find.text('Before you play'), findsOneWidget);
  });
}
