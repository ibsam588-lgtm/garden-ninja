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

    final weed = find.byKey(const ValueKey('target-1'));
    expect(weed, findsOneWidget);

    await tester.tap(weed);
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('58'), findsOneWidget);
    expect(weed, findsOneWidget);
    expect(find.text('1 cuts'), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (widget) => widget is ClipPath && widget.clipper is SliceHalfClipper,
      ),
      findsAtLeastNWidgets(2),
    );

    final flower = find.byKey(const ValueKey('target-2'));
    expect(flower, findsOneWidget);

    await tester.tap(flower);
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byIcon(Icons.pause_rounded), findsOneWidget);
    expect(find.text('Garden Saved'), findsNothing);
  });
}
