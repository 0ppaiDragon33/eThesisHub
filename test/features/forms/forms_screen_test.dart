import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ethesishub/features/forms/forms_screen.dart';
import 'package:ethesishub/providers/auth_providers.dart';

/// Every widget test that touches auth-backed providers must seed a
/// `users/{uid}` profile and await the write before pumping, or the tree
/// silently exercises whatever branch an unresolved profile falls into.
Future<FakeFirebaseFirestore> seedUser(
  String uid, {
  String role = 'student',
}) async {
  final db = FakeFirebaseFirestore();
  await db.collection('users').doc(uid).set({
    'fullName': 'Test User',
    'email': 't@isufst.edu.ph',
    'role': role,
    'active': true,
  });
  return db;
}

Widget app(FakeFirebaseFirestore db, String uid) {
  return ProviderScope(
    overrides: [
      firestoreProvider.overrideWithValue(db),
      firebaseAuthProvider.overrideWithValue(
        MockFirebaseAuth(signedIn: true, mockUser: MockUser(uid: uid)),
      ),
    ],
    child: const MaterialApp(home: Scaffold(body: FormsScreen())),
  );
}

void useTallSurface(WidgetTester tester) {
  tester.view.physicalSize = const Size(1000, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

void main() {
  // Requirement test 1, and THE test that proves this feature solves the
  // reported problem: a reader went looking for "the forms" and there was
  // nowhere to look. On a completely empty database -- no thesis, no
  // defence, no evaluation, no archive entry -- all three forms must
  // still be listed, and every Blank template button must be enabled.
  testWidgets(
    'lists all eight forms on a completely empty database, with every '
    'Blank template button enabled',
    (tester) async {
      useTallSurface(tester);
      final db = await seedUser('s1');
      await tester.pumpWidget(app(db, 's1'));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('forms')), findsOneWidget);
      expect(find.byKey(const Key('form1Card')), findsOneWidget);
      expect(find.byKey(const Key('form5cCard')), findsOneWidget);
      expect(find.byKey(const Key('form8Card')), findsOneWidget);
      expect(find.byKey(const Key('form3Card')), findsOneWidget);
      expect(find.byKey(const Key('form4aCard')), findsOneWidget);
      expect(find.byKey(const Key('form4bCard')), findsOneWidget);
      expect(find.byKey(const Key('form5aCard')), findsOneWidget);
      expect(find.byKey(const Key('form5bCard')), findsOneWidget);

      final form5cButton = tester.widget<OutlinedButton>(
        find.byKey(const Key('form5cBlankButton')),
      );
      expect(form5cButton.onPressed, isNotNull);

      final form8Button = tester.widget<OutlinedButton>(
        find.byKey(const Key('form8BlankButton')),
      );
      expect(form8Button.onPressed, isNotNull);

      for (final key in [
        'form3BlankButton',
        'form4aBlankButton',
        'form4bBlankButton',
        'form5aBlankButton',
        'form5bBlankButton',
      ]) {
        final button = tester.widget<OutlinedButton>(find.byKey(Key(key)));
        expect(button.onPressed, isNotNull, reason: key);
      }
    },
  );

  // Form 1 deliberately has no blank template button (Form1Data requires a
  // whole Thesis) -- confirm the screen does not fabricate one.
  testWidgets('Form 1 has no blank template button', (tester) async {
    useTallSurface(tester);
    final db = await seedUser('s1');
    await tester.pumpWidget(app(db, 's1'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('form1BlankButton')), findsNothing);
  });

  // A student with no thesis of their own must not get a dead "Open my
  // thesis" link -- the empty-database case again, this time for Form 1's
  // convenience link specifically.
  testWidgets('a student with no thesis gets no "Open my thesis" link', (
    tester,
  ) async {
    useTallSurface(tester);
    final db = await seedUser('s1');
    await tester.pumpWidget(app(db, 's1'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('form1OpenThesis')), findsNothing);
  });

  // A student who does have a thesis gets the convenience link to it.
  testWidgets('a student with a thesis gets an "Open my thesis" link', (
    tester,
  ) async {
    useTallSurface(tester);
    final db = await seedUser('s1');
    await db.collection('theses').doc('t1').set({
      'leaderUid': 's1',
      'memberNames': <String>['Santos, J.'],
      'workingTitle': 'Working title',
      'college': 'CICT',
      'program': 'BSIT',
      'semester': 'First',
      'academicYear': '2026-2027',
      'status': 'titleApproved',
      'panelistUids': <String>[],
    });
    await tester.pumpWidget(app(db, 's1'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('form1OpenThesis')), findsOneWidget);
  });

  // A non-coordinator must never see the archived-theses list under Form
  // 8, even when entries exist -- issuing Form 8 is the coordinator's act.
  testWidgets(
    'a non-coordinator with archived theses gets the blank but no list',
    (tester) async {
      useTallSurface(tester);
      final db = await seedUser('f1', role: 'faculty');
      await db.collection('archive').doc('t1').set({
        'title': 'A Study of Coastal Fisheries',
        'memberNames': <String>['Santos, J.'],
        'abstract': 'Fish were counted.',
        'college': 'CICT',
        'program': 'BSIT',
        'academicYear': '2026-2027',
        'adviserName': 'Dr. Zamora',
        'panelNames': <String>['Dr. Reyes'],
        'manuscriptUrl': 'https://example.test/m.pdf',
        'manuscriptPath': 'p/m.pdf',
        'finalDefenceId': 'd9',
        'uploadedBy': 'l1',
        'archivedBy': 'c1',
        'archivedAt': Timestamp.fromDate(DateTime(2026, 9, 30)),
      });
      await tester.pumpWidget(app(db, 'f1'));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('form8BlankButton')), findsOneWidget);
      expect(find.byKey(const Key('form8Download-t1')), findsNothing);
    },
  );

  // A coordinator with an archived thesis gets both the blank and the
  // filled convenience link.
  testWidgets('a coordinator with an archived thesis gets a download row', (
    tester,
  ) async {
    useTallSurface(tester);
    final db = await seedUser('c1', role: 'coordinator');
    await db.collection('archive').doc('t1').set({
      'title': 'A Study of Coastal Fisheries',
      'memberNames': <String>['Santos, J.'],
      'abstract': 'Fish were counted.',
      'college': 'CICT',
      'program': 'BSIT',
      'academicYear': '2026-2027',
      'adviserName': 'Dr. Zamora',
      'panelNames': <String>['Dr. Reyes'],
      'manuscriptUrl': 'https://example.test/m.pdf',
      'manuscriptPath': 'p/m.pdf',
      'finalDefenceId': 'd9',
      'uploadedBy': 'l1',
      'archivedBy': 'c1',
      'archivedAt': Timestamp.fromDate(DateTime(2026, 9, 30)),
    });
    await tester.pumpWidget(app(db, 'c1'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('form8BlankButton')), findsOneWidget);
    expect(find.byKey(const Key('form8Download-t1')), findsOneWidget);
  });
}
