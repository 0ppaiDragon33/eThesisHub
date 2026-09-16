// test/core/components/brand_emblem_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ethesishub/core/components/brand.dart';
import 'package:ethesishub/core/theme/app_tokens.dart';

void main() {
  Future<void> pump(WidgetTester tester, Widget child,
      {Brightness brightness = Brightness.light}) {
    return tester.pumpWidget(MaterialApp(
      theme: ThemeData(brightness: brightness),
      home: Scaffold(body: Center(child: child)),
    ));
  }

  testWidgets('draws a mortarboard, not an image asset', (tester) async {
    await pump(tester, const BrandEmblem());
    // Drawn in code (D81): there is a glyph and no Image to ship or lose.
    expect(find.byIcon(Icons.school), findsOneWidget);
    expect(find.byType(Image), findsNothing);
  });

  testWidgets('defaults to seal, and to the dark seal in dark mode', (tester) async {
    await pump(tester, const BrandEmblem());
    final light = tester.widget<Container>(find.byType(Container));
    expect((light.decoration as BoxDecoration).color, AppTokens.seal);

    await pump(tester, const BrandEmblem(), brightness: Brightness.dark);
    final dark = tester.widget<Container>(find.byType(Container));
    expect((dark.decoration as BoxDecoration).color, AppTokens.sealDark);
  });

  testWidgets('honours an explicit background, and scales with size', (tester) async {
    await pump(tester, const BrandEmblem(size: 26, background: Color(0xFF123456)));
    final box = tester.widget<Container>(find.byType(Container));
    expect((box.decoration as BoxDecoration).color, const Color(0xFF123456));
    // The mark appears at 56/40/26 across the app; the glyph must scale with it
    // rather than sit at a fixed size inside a shrinking square.
    expect(tester.widget<Icon>(find.byIcon(Icons.school)).size, lessThan(26));
  });
}
