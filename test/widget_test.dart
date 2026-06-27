import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:garden_ninja/src/app.dart';

void main() {
  testWidgets('Garden Ninja shows home and can start play', (tester) async {
    await tester.pumpWidget(const GardenNinjaApp());

    expect(find.text('Garden'), findsAtLeastNWidgets(1));
    expect(find.text('Ninja'), findsOneWidget);
    expect(find.text('PLAY'), findsOneWidget);

    await tester.tap(find.text('PLAY'));
    await tester.pump(const Duration(milliseconds: 64));

    expect(find.text('SCORE'), findsOneWidget);
    expect(find.byIcon(Icons.pause_rounded), findsOneWidget);

    final weed = find.byWidgetPredicate(
      (widget) =>
          widget is Image &&
          widget.image is AssetImage &&
          (widget.image as AssetImage).assetName ==
              'assets/images/sprites/weed_spike.png',
    );
    expect(weed, findsOneWidget);

    await tester.tap(weed);
    await tester.pump(const Duration(milliseconds: 64));

    expect(find.text('112'), findsOneWidget);
  });
}
