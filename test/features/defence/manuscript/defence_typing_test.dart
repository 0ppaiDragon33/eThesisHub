import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ethesishub/data/models/defence_composing.dart';
import 'package:ethesishub/data/repositories/defence_repository.dart';
import 'package:ethesishub/features/defence/manuscript/defence_typing.dart';

DefenceComposing marker(String uid, String name,
        {ComposingTarget target = ComposingTarget.room, DateTime? at}) =>
    DefenceComposing(
      uid: uid,
      name: name,
      position: 'Panel Member',
      target: target,
      updatedAt: at ?? DateTime(2026, 9, 26, 9),
    );

void main() {
  test('typingText', () {
    expect(typingText([]), isNull);
    expect(typingText(['Dr. Santos']), 'Dr. Santos is typing…');
    expect(typingText(['Dr. Santos', 'Prof. Cruz']),
        'Dr. Santos and Prof. Cruz are typing…');
    expect(typingText(['A', 'B', 'C', 'D']), 'A, B and 2 more are typing…');
  });

  group('DefenceTyping', () {
    late FakeFirebaseFirestore db;
    late DefenceTyping typing;

    setUp(() {
      db = FakeFirebaseFirestore();
      typing = DefenceTyping(
        repo: DefenceRepository(db),
        defenceId: 'd1',
        uid: 'p1',
        name: 'Dr. Panel',
        position: 'Panel Member',
      );
    });

    Future<Map<String, dynamic>?> read() async =>
        (await db.doc('defenses/d1/composing/p1').get()).data();

    test('writes a marker when typing starts and clears it when it stops',
        () async {
      typing.typing(ComposingTarget.room, active: true);
      await pumpEventQueue();
      expect((await read())!['target'], 'room');
      expect(typing.isTyping, isTrue);

      typing.typing(ComposingTarget.room, active: false);
      await pumpEventQueue();
      expect(await read(), isNull);
      expect(typing.isTyping, isFalse);
      typing.dispose();
    });

    test('moving to the highlight box rewrites the target', () async {
      typing.typing(ComposingTarget.room, active: true);
      typing.typing(ComposingTarget.manuscript, active: true);
      await pumpEventQueue();
      expect((await read())!['target'], 'manuscript');
      // Stopping the room box does not stop the highlight box.
      typing.typing(ComposingTarget.room, active: false);
      await pumpEventQueue();
      expect(await read(), isNotNull);
      typing.dispose();
    });

    test('dispose clears the marker', () async {
      typing.typing(ComposingTarget.room, active: true);
      await pumpEventQueue();
      typing.dispose();
      await pumpEventQueue();
      expect(await read(), isNull);
    });
  });

  group('TypingLine', () {
    final now = DateTime(2026, 9, 26, 9, 0, 5);

    Future<void> pump(WidgetTester tester, List<DefenceComposing> markers,
            {ComposingTarget target = ComposingTarget.room}) =>
        tester.pumpWidget(MaterialApp(
          home: Scaffold(
            body: TypingLine(
              markers: markers,
              target: target,
              myUid: 'me',
              now: () => now,
            ),
          ),
        ));

    testWidgets('names others typing in this box', (tester) async {
      await pump(tester, [
        marker('a1', 'Dr. Santos'),
        marker('p2', 'Prof. Cruz'),
      ]);
      expect(find.text('Dr. Santos and Prof. Cruz are typing…'),
          findsOneWidget);
      expect(find.byKey(const Key('typingLine-room')), findsOneWidget);
    });

    testWidgets('never shows yourself, a stale marker, or the other box',
        (tester) async {
      await pump(tester, [
        marker('me', 'Me'),
        marker('a1', 'Dr. Santos', at: DateTime(2026, 9, 26, 8, 59, 40)),
        marker('p2', 'Prof. Cruz', target: ComposingTarget.manuscript),
      ]);
      expect(find.byKey(const Key('typingLine-room')), findsNothing);
    });
  });
}
