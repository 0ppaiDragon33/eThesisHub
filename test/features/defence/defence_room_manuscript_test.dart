import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ethesishub/features/defence/defence_room_screen.dart';
import 'package:ethesishub/features/defence/manuscript/defence_manuscript_screen.dart';
import 'package:ethesishub/features/defence/manuscript/manuscript_providers.dart';
import 'package:ethesishub/providers/auth_providers.dart';

class FakeRasterizer implements ManuscriptRasterizer {
  FakeRasterizer(this.image);
  final ui.Image image;
  @override
  Future<List<Size>> pageSizes(Uint8List pdf) async =>
      [const Size(210, 297), const Size(210, 297)];
  @override
  Future<ui.Image> renderPage(Uint8List pdf, int index) async => image.clone();
}

Future<FakeFirebaseFirestore> seed({
  String status = 'inProgress',
  bool released = false,
  List<Map<String, dynamic>> highlights = const [],
  Map<String, Map<String, dynamic>> composing = const {},
}) async {
  final db = FakeFirebaseFirestore();
  await db.collection('theses').doc('t1').set({
    'leaderUid': 'l1',
    'adviserUid': 'a1',
    'status': 'titleApproved',
    'panelistUids': ['p1', 'p2'],
    'workingTitle': 'Mangrove Carbon Stocks',
  });
  await db.collection('defenses').doc('d1').set({
    'thesisId': 't1',
    'type': 'preOral',
    'scheduledAt':
        Timestamp.fromDate(DateTime.now().add(const Duration(days: 7))),
    'venue': 'AVR',
    'panelUids': ['p1', 'p2'],
    'adviserUid': 'a1',
    'leaderUid': 'l1',
    'status': status,
    'createdBy': 'c1',
    if (released) 'consolidatedAt': Timestamp.fromDate(DateTime(2026, 9, 1)),
  });
  for (final (uid, name, role) in [
    ('a1', 'Dr. Adviser', 'faculty'),
    ('p1', 'Dr. Panel', 'faculty'),
    ('l1', 'Leader', 'student'),
  ]) {
    await db.collection('users').doc(uid).set({
      'fullName': name,
      'email': '$uid@isufst.edu.ph',
      'role': role,
      'active': true,
    });
  }
  final docs = db.collection('theses/t1/documents');
  await docs
      .doc('chapterI')
      .set({'type': 'chapterI', 'currentVersion': 1, 'status': 'approved'});
  await docs.doc('chapterI').collection('versions').doc('1').set({
    'version': 1,
    'storagePath': 'theses/t1/chapterI/a.pdf',
    'fileUrl': '',
    'uploadedBy': 'l1',
    'mimeType': 'application/pdf',
    'sizeBytes': 4,
  });
  await docs
      .doc('chapterII')
      .set({'type': 'chapterII', 'currentVersion': 1, 'status': 'revise'});
  for (var i = 0; i < highlights.length; i++) {
    await db.collection('defenses/d1/annotations').doc('h$i').set({
      'authorName': 'Someone',
      'authorPosition': 'Panel Member',
      'chapter': 'chapterI',
      'version': 1,
      'page': 0,
      'rect': {'x': 0.1, 'y': 0.1, 'w': 0.5, 'h': 0.05},
      'body': 'Highlight $i',
      'createdAt': Timestamp.fromDate(DateTime(2026, 9, 26, 9, i)),
      ...highlights[i],
    });
  }
  for (final e in composing.entries) {
    await db.doc('defenses/d1/composing/${e.key}').set(e.value);
  }
  return db;
}

Future<void> pumpScreen(
  WidgetTester tester,
  FakeFirebaseFirestore db,
  String uid,
  Widget screen, {
  Size size = const Size(1400, 900),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  final image =
      (await tester.runAsync(() => createTestImage(width: 210, height: 297)))!;
  await tester.pumpWidget(ProviderScope(
    overrides: [
      firestoreProvider.overrideWithValue(db),
      firebaseAuthProvider.overrideWithValue(MockFirebaseAuth(
        signedIn: true,
        mockUser: MockUser(
            uid: uid, email: '$uid@isufst.edu.ph', isEmailVerified: true),
      )),
      chapterFileLoaderProvider.overrideWithValue((path) async => Uint8List(4)),
      manuscriptRasterizerProvider.overrideWithValue(FakeRasterizer(image)),
    ],
    child: MaterialApp(home: Scaffold(body: screen)),
  ));
  await settle(tester);
}

Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 30));
  }
}

const room = DefenceRoomScreen(defenceId: 'd1');

void main() {
  testWidgets('a wide room puts the manuscript beside the side column',
      (tester) async {
    await pumpScreen(tester, await seed(), 'p1', room);
    expect(find.byKey(const Key('manuscriptPane')), findsOneWidget);
    expect(find.byKey(const Key('roomSideColumn')), findsOneWidget);
    expect(find.byKey(const Key('pageTile-chapterI-1-0')), findsOneWidget);
    // The pages are a lazy list, and at this width Chapter I's two pages
    // fill well past the viewport, so scroll Chapter II's note into view.
    await tester.scrollUntilVisible(
        find.text('Chapter II is not approved yet.'), 300,
        scrollable: find.descendant(
            of: find.byKey(const Key('manuscriptPages')),
            matching: find.byType(Scrollable)));
    await settle(tester);
    expect(find.text('Chapter II is not approved yet.'), findsOneWidget);
  });

  testWidgets('before the defence opens, highlighting is closed',
      (tester) async {
    await pumpScreen(tester, await seed(status: 'scheduled'), 'p1', room);
    expect(find.byKey(const Key('highlightTool')), findsNothing);
    expect(find.text('Highlighting opens when the defence starts.'),
        findsOneWidget);
  });

  testWidgets('after it closes, the tool is gone without a reason',
      (tester) async {
    await pumpScreen(tester, await seed(status: 'completed'), 'p1', room);
    expect(find.byKey(const Key('highlightTool')), findsNothing);
    expect(find.byKey(const Key('highlightClosed')), findsNothing);
  });

  testWidgets('a panel member draws a highlight and writes its comment',
      (tester) async {
    final db = await seed();
    await pumpScreen(tester, db, 'p1', room);

    await tester.tap(find.byKey(const Key('highlightTool')));
    await tester.pump();
    final surface = find.byKey(const Key('drawSurface-chapterI-0'));
    await tester.dragFrom(
        tester.getTopLeft(surface) + const Offset(40, 60),
        const Offset(220, 30));
    await settle(tester);

    await tester.enterText(
        find.byKey(const Key('highlightBody')), 'Cite the 2024 data.');
    await tester.pump();
    expect((await db.doc('defenses/d1/composing/p1').get()).data()!['target'],
        'manuscript');
    await tester.tap(find.byKey(const Key('saveHighlight')));
    await settle(tester);

    final saved = (await db.collection('defenses/d1/annotations').get()).docs;
    expect(saved, hasLength(1));
    expect(saved.single.data()['authorUid'], 'p1');
    expect(saved.single.data()['authorPosition'], 'Panel Member');
    expect(saved.single.data()['chapter'], 'chapterI');
    expect(saved.single.data()['version'], 1);
    expect(saved.single.data()['page'], 0);
    expect(find.text('Highlights (1)'), findsOneWidget);
    expect((await db.doc('defenses/d1/composing/p1').get()).exists, isFalse);
  });

  testWidgets('you delete your own highlight after confirming',
      (tester) async {
    final db = await seed(highlights: [
      {'authorUid': 'p1'},
      {'authorUid': 'a1'},
    ]);
    await pumpScreen(tester, db, 'p1', room);
    await tester.ensureVisible(find.byKey(const Key('tabHighlights')));
    await tester.tap(find.byKey(const Key('tabHighlights')));
    await settle(tester);

    expect(find.byKey(const Key('deleteHighlight-h1')), findsNothing);
    await tester.ensureVisible(find.byKey(const Key('deleteHighlight-h0')));
    await tester.tap(find.byKey(const Key('deleteHighlight-h0')));
    await settle(tester);
    await tester.tap(find.byKey(const Key('confirmDeleteHighlight')));
    await settle(tester);
    expect((await db.doc('defenses/d1/annotations/h0').get()).exists, isFalse);
    expect((await db.doc('defenses/d1/annotations/h1').get()).exists, isTrue);
  });

  testWidgets('typing in the room box shows up for others, and clears',
      (tester) async {
    final db = await seed(composing: {
      'a1': {
        'name': 'Dr. Adviser',
        'position': 'Adviser',
        'target': 'room',
        'updatedAt': Timestamp.fromDate(DateTime.now()),
      },
    });
    await pumpScreen(tester, db, 'p1', room);
    expect(find.text('Dr. Adviser is typing…'), findsOneWidget);

    await tester.ensureVisible(find.byKey(const Key('commentBody')));
    await tester.enterText(find.byKey(const Key('commentBody')), 'Why?');
    await tester.pump();
    expect((await db.doc('defenses/d1/composing/p1').get()).data()!['target'],
        'room');
    await tester.enterText(find.byKey(const Key('commentBody')), '');
    await tester.pump();
    expect((await db.doc('defenses/d1/composing/p1').get()).exists, isFalse);
  });

  testWidgets('on a phone the tabs sit in a sheet over the manuscript',
      (tester) async {
    await pumpScreen(tester, await seed(), 'p1', room,
        size: const Size(400, 860));
    expect(find.byKey(const Key('roomSheet')), findsOneWidget);
    expect(find.byKey(const Key('manuscriptPane')), findsOneWidget);
    expect(find.byKey(const Key('tabHighlights')), findsOneWidget);
  });

  testWidgets('the leader has no View manuscript before release',
      (tester) async {
    await pumpScreen(tester, await seed(status: 'completed'), 'l1', room);
    expect(find.byKey(const Key('goToManuscript')), findsNothing);
  });

  testWidgets('the leader gets View manuscript once released',
      (tester) async {
    await pumpScreen(
        tester, await seed(status: 'completed', released: true), 'l1', room);
    expect(find.byKey(const Key('goToManuscript')), findsOneWidget);
  });

  testWidgets('the leader sees nothing before release', (tester) async {
    await pumpScreen(tester, await seed(status: 'completed'), 'l1',
        const DefenceManuscriptScreen(defenceId: 'd1'));
    expect(find.text('Available once your adviser releases the comments.'),
        findsOneWidget);
    expect(find.byKey(const Key('manuscriptPane')), findsNothing);
  });

  testWidgets('a chapter reopened after release still shows what was marked',
      (tester) async {
    final db = await seed(
        status: 'completed',
        released: true,
        highlights: [
          {'authorUid': 'p1', 'chapter': 'chapterII', 'version': 1},
        ]);
    // Chapter II was approved for the defence, then reopened: its status is
    // back to revise, on the same version.
    await db
        .collection('theses/t1/documents/chapterII/versions')
        .doc('1')
        .set({
      'version': 1,
      'storagePath': 'theses/t1/chapterII/a.pdf',
      'fileUrl': '',
      'uploadedBy': 'l1',
      'mimeType': 'application/pdf',
      'sizeBytes': 4,
    });
    await pumpScreen(
        tester, db, 'l1', const DefenceManuscriptScreen(defenceId: 'd1'));

    expect(find.byKey(const Key('highlightStale-h0')), findsNothing);
    await tester.scrollUntilVisible(
        find.byKey(const Key('chapterReopened-chapterII')), 300,
        scrollable: find.descendant(
            of: find.byKey(const Key('manuscriptPages')),
            matching: find.byType(Scrollable)));
    await settle(tester);
    expect(
        find.text('Chapter II has been reopened for revision. Showing the '
            'version the panel marked.'),
        findsOneWidget);
    expect(find.text('Chapter II is not approved yet.'), findsNothing);
    expect(find.byKey(const Key('pageTile-chapterII-1-0')), findsOneWidget);
    expect(find.byKey(const Key('highlightBox-h0')), findsOneWidget);
  });

  testWidgets('after release the leader reads pages and highlights only',
      (tester) async {
    await pumpScreen(
        tester,
        await seed(
            status: 'completed',
            released: true,
            highlights: [
              {'authorUid': 'p1'},
            ]),
        'l1',
        const DefenceManuscriptScreen(defenceId: 'd1'));
    expect(find.byKey(const Key('manuscriptPane')), findsOneWidget);
    expect(find.byKey(const Key('highlightBox-h0')), findsOneWidget);
    expect(find.text('Highlight 0'), findsOneWidget);
    expect(find.byKey(const Key('highlightTool')), findsNothing);
    expect(find.byKey(const Key('deleteHighlight-h0')), findsNothing);
  });
}
