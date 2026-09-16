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

  group('FormRow', () {
    testWidgets('labels its field and renders the field itself', (tester) async {
      await pump(tester, const FormRow(
        label: 'Institutional email',
        child: TextField(key: Key('email')),
      ));

      expect(find.text('INSTITUTIONAL EMAIL'), findsOneWidget);
      expect(find.byKey(const Key('email')), findsOneWidget);
    });

    testWidgets('the overline sits above the field, not inside it', (tester) async {
      // The overline sits ABOVE the input rather than floating inside it —
      // that is the whole point of the treatment, and a labelText would
      // silently reintroduce the old look.
      await pump(tester, const FormRow(
        label: 'Password',
        child: TextField(key: Key('pw')),
      ));

      // Asserting the caller's own TextField has no labelText would prove
      // nothing — the test constructed it that way. What has to be true of
      // FormRow is that the overline it draws sits ABOVE the field.
      final label = tester.getTopLeft(find.text('PASSWORD'));
      final field = tester.getTopLeft(find.byKey(const Key('pw')));
      expect(label.dy, lessThan(field.dy));
    });
  });

  group('KeyFacts', () {
    testWidgets('renders each label and value in order', (tester) async {
      await pump(tester, const KeyFacts([
        (label: 'Program', value: 'BSIT'),
        (label: 'Academic year', value: '2026-2027'),
      ]));

      expect(find.text('Program'), findsOneWidget);
      expect(find.text('BSIT'), findsOneWidget);
      expect(find.text('Academic year'), findsOneWidget);
      expect(find.text('2026-2027'), findsOneWidget);
    });

    testWidgets('an empty list renders nothing rather than throwing',
        (tester) async {
      await pump(tester, const KeyFacts([]));
      expect(tester.takeException(), isNull);
    });
  });
}
