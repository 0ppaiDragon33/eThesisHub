// test/core/components/document_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ethesishub/core/components/document.dart';

void main() {
  Future<void> pump(WidgetTester tester, Widget child) {
    return tester.pumpWidget(MaterialApp(
      home: Scaffold(body: ListView(children: [child])),
    ));
  }

  group('SectionRule', () {
    testWidgets('renders its label and its trailing slot', (tester) async {
      await pump(tester, const SectionRule('Waiting on you',
          trailing: Text('3')));

      // The primitive owns the overline treatment, so callers pass natural
      // case and twelve screens do not each have to remember to shout.
      expect(find.text('WAITING ON YOU'), findsOneWidget);
      expect(find.text('Waiting on you'), findsNothing);
      expect(find.text('3'), findsOneWidget);
    });

    testWidgets('renders without a trailing slot', (tester) async {
      await pump(tester, const SectionRule('Decided'));

      expect(find.text('DECIDED'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('RecordRow', () {
    testWidgets('renders title, subtitle, leading and trailing', (tester) async {
      await pump(tester, const RecordRow(
        title: 'Coastal Fisheries Yield',
        subtitle: 'BSIT · First · 2026-2027',
        leading: Icon(Icons.circle, size: 10),
        trailing: Text('Approve'),
      ));

      expect(find.text('Coastal Fisheries Yield'), findsOneWidget);
      expect(find.text('BSIT · First · 2026-2027'), findsOneWidget);
      expect(find.byIcon(Icons.circle), findsOneWidget);
      expect(find.text('Approve'), findsOneWidget);
    });

    testWidgets('a row with no subtitle still renders', (tester) async {
      await pump(tester, const RecordRow(title: 'Only a title'));

      expect(find.text('Only a title'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('is tappable only when given onTap', (tester) async {
      var taps = 0;
      await pump(tester, RecordRow(title: 'Tap me', onTap: () => taps++));
      await tester.tap(find.text('Tap me'));
      expect(taps, 1);

      await pump(tester, const RecordRow(title: 'Not tappable'));
      // No InkWell means nothing to tap: a row that looks interactive but
      // does nothing is worse than one that plainly is not.
      expect(find.byType(InkWell), findsNothing);
    });
  });
}
