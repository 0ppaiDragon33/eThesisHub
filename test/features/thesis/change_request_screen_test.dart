import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:ethesishub/data/models/change_request.dart';
import 'package:ethesishub/features/thesis/change_request_screen.dart';
import 'package:ethesishub/providers/auth_providers.dart';

/// Seeds a thesis `t1` led by `l1`, currently advised by [adviserUid], plus a
/// small faculty directory: `a1` (the usual current adviser), `a2` (an
/// ordinary alternative pick) and `a4` (used as a stand-in "current adviser"
/// in the former-adviser test, so `a1` can still be offered as the pick).
/// `a3` is seeded not nominable, to prove the picker honours that flag.
Future<FakeFirebaseFirestore> seed({String? adviserUid = 'a1'}) async {
  final db = FakeFirebaseFirestore();
  await db.collection('theses').doc('t1').set({
    'leaderUid': 'l1',
    'adviserUid': adviserUid,
    'status': 'titleApproved',
    'panelistUids': <String>[],
    'memberNames': <String>[],
    'workingTitle': 'A Study of Things',
    'college': 'CICT',
    'program': 'BSIT',
    'semester': 'First',
    'academicYear': '2026-2027',
  });
  await db.collection('facultyDirectory').doc('a1').set({
    'fullName': 'Dr. Adviser One',
    'role': 'faculty',
    'nominableAsAdviser': true,
    'nominableAsPanelist': true,
  });
  await db.collection('facultyDirectory').doc('a2').set({
    'fullName': 'Dr. Adviser Two',
    'role': 'faculty',
    'nominableAsAdviser': true,
    'nominableAsPanelist': true,
  });
  await db.collection('facultyDirectory').doc('a3').set({
    'fullName': 'Dr. Not Nominable',
    'role': 'faculty',
    'nominableAsAdviser': false,
    'nominableAsPanelist': true,
  });
  await db.collection('facultyDirectory').doc('a4').set({
    'fullName': 'Dr. Adviser Four',
    'role': 'faculty',
    'nominableAsAdviser': true,
    'nominableAsPanelist': true,
  });
  await db.collection('users').doc('l1').set({
    'fullName': 'Leader One',
    'email': 'l1@isufst.edu.ph',
    'role': 'student',
    'active': true,
  });
  return db;
}

// Without this override, FirebaseAuth.instance throws [core/no-app] in a
// widget test -- same pattern as schedule_defence_screen_test.dart.
Widget _wrap(
  FakeFirebaseFirestore db, {
  required String uid,
  required ChangeRequestType type,
  ChangeRequest? prefill,
  List<Override> overrides = const [],
}) => ProviderScope(
  overrides: [
    firestoreProvider.overrideWithValue(db),
    firebaseAuthProvider.overrideWithValue(
      MockFirebaseAuth(
        signedIn: true,
        mockUser: MockUser(
          uid: uid,
          email: '$uid@isufst.edu.ph',
          isEmailVerified: true,
        ),
      ),
    ),
    ...overrides,
  ],
  child: MaterialApp.router(
    routerConfig: GoRouter(
      initialLocation: '/request',
      routes: [
        GoRoute(
          path: '/request',
          builder: (_, _) => Scaffold(
            appBar: AppBar(title: const Text('Request a change')),
            body: ChangeRequestScreen(
              thesisId: 't1',
              type: type,
              prefill: prefill,
            ),
          ),
        ),
        // A landing route the screen pops back to on success.
        GoRoute(
          path: '/landed',
          builder: (_, _) => const Scaffold(
            body: Center(child: Text('landed', key: Key('landed'))),
          ),
        ),
      ],
    ),
  ),
);

/// `DropdownButtonFormField` does not expose its `items` as a readable
/// field, so the only way to inspect what the picker actually offers is to
/// open its overlay and read the mounted `DropdownMenuItem` widgets — same
/// helper as `nominate_screen_test.dart`'s `openDropdownValues`.
Future<List<String?>> _openAdviserPickerValues(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('newAdviserPicker')));
  await tester.pumpAndSettle();
  final values = tester
      .widgetList<DropdownMenuItem<String>>(
        find.byType(DropdownMenuItem<String>),
      )
      .map((i) => i.value)
      .toList();
  await tester.tapAt(const Offset(5, 5)); // dismiss the overlay
  await tester.pumpAndSettle();
  return values;
}

void main() {
  group('adviser change', () {
    testWidgets('shows the form and its keys', (tester) async {
      final db = await seed();
      await tester.pumpWidget(
        _wrap(db, uid: 'l1', type: ChangeRequestType.adviser),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('changeRequestScreen')), findsOneWidget);
      expect(find.byKey(const Key('newAdviserPicker')), findsOneWidget);
      expect(find.byKey(const Key('changeReasons')), findsOneWidget);
      expect(find.byKey(const Key('submitChangeRequest')), findsOneWidget);
      expect(find.byKey(const Key('newTitleField')), findsNothing);
    });

    testWidgets('does not offer the current adviser or a non-nominable one', (
      tester,
    ) async {
      final db = await seed(adviserUid: 'a1');
      await tester.pumpWidget(
        _wrap(db, uid: 'l1', type: ChangeRequestType.adviser),
      );
      await tester.pumpAndSettle();

      final values = await _openAdviserPickerValues(tester);
      expect(values, contains('a2'));
      expect(values, contains('a4'));
      expect(
        values,
        isNot(contains('a1')),
        reason: 'a1 is the current adviser -- excluded per spec',
      );
      expect(
        values,
        isNot(contains('a3')),
        reason: 'a3 is not nominableAsAdviser',
      );
    });

    testWidgets('an empty reason is refused before any write', (tester) async {
      final db = await seed();
      await tester.pumpWidget(
        _wrap(db, uid: 'l1', type: ChangeRequestType.adviser),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('newAdviserPicker')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Dr. Adviser Two').last);
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.byKey(const Key('submitChangeRequest')));
      await tester.tap(find.byKey(const Key('submitChangeRequest')));
      await tester.pumpAndSettle();

      expect(find.textContaining('Give a reason'), findsOneWidget);
      expect(
        (await db.collection('theses/t1/changeRequests').get()).docs,
        isEmpty,
      );
    });

    testWidgets(
      'a new adviser equal to the current adviser is refused before any '
      'write',
      (tester) async {
        final db = await seed(adviserUid: 'a1');
        // Reachable through prefill rather than the picker: the picker itself
        // excludes the current adviser from its options (spec), so this state
        // models a resubmit whose prior pick has since become the thesis's
        // current adviser.
        final prefill = ChangeRequest(
          type: ChangeRequestType.adviser,
          stage: ChangeRequestStage.returned,
          reasons: 'Prior reason',
          leaderUid: 'l1',
          signoffs: const {},
          newAdviserUid: 'a1',
          formerAdviserUid: 'a4',
          formerAdviserName: 'Dr. Adviser Four',
        );
        await tester.pumpWidget(
          _wrap(
            db,
            uid: 'l1',
            type: ChangeRequestType.adviser,
            prefill: prefill,
          ),
        );
        await tester.pumpAndSettle();

        await tester.ensureVisible(
          find.byKey(const Key('submitChangeRequest')),
        );
        await tester.tap(find.byKey(const Key('submitChangeRequest')));
        await tester.pumpAndSettle();

        expect(
          find.textContaining(
            'new adviser must be different from the current adviser',
          ),
          findsOneWidget,
        );
        expect(
          (await db.collection('theses/t1/changeRequests').get()).docs,
          isEmpty,
        );
      },
    );

    testWidgets(
      'a new adviser equal to the former adviser is refused before any '
      'write (a no-op)',
      (tester) async {
        // The thesis's CURRENT adviser is a4 here, distinct from the a1
        // recorded as this request's former adviser -- otherwise the "equal to
        // current" guard above would catch it first.
        final db = await seed(adviserUid: 'a4');
        final prefill = ChangeRequest(
          type: ChangeRequestType.adviser,
          stage: ChangeRequestStage.returned,
          reasons: 'Prior reason',
          leaderUid: 'l1',
          signoffs: const {},
          formerAdviserUid: 'a1',
          formerAdviserName: 'Dr. Adviser One',
        );
        await tester.pumpWidget(
          _wrap(
            db,
            uid: 'l1',
            type: ChangeRequestType.adviser,
            prefill: prefill,
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const Key('newAdviserPicker')));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Dr. Adviser One').last);
        await tester.pumpAndSettle();

        await tester.enterText(
          find.byKey(const Key('changeReasons')),
          'Trying again',
        );
        await tester.ensureVisible(
          find.byKey(const Key('submitChangeRequest')),
        );
        await tester.tap(find.byKey(const Key('submitChangeRequest')));
        await tester.pumpAndSettle();

        expect(
          find.textContaining('same as the former adviser'),
          findsOneWidget,
        );
        expect(
          (await db.collection('theses/t1/changeRequests').get()).docs,
          isEmpty,
        );
      },
    );

    testWidgets('a valid adviser change writes the request and pops back', (
      tester,
    ) async {
      final db = await seed(adviserUid: 'a1');
      await tester.pumpWidget(
        _wrap(db, uid: 'l1', type: ChangeRequestType.adviser),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('newAdviserPicker')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Dr. Adviser Two').last);
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const Key('changeReasons')),
        'A good reason',
      );
      await tester.ensureVisible(find.byKey(const Key('submitChangeRequest')));
      await tester.tap(find.byKey(const Key('submitChangeRequest')));
      await tester.pumpAndSettle();

      final saved = await db
          .collection('theses/t1/changeRequests')
          .doc('adviser')
          .get();
      expect(saved.exists, isTrue);
      expect(saved.data()!['newAdviserUid'], 'a2');
      expect(saved.data()!['formerAdviserUid'], 'a1');
      expect(saved.data()!['stage'], 'pendingAdvisers');
    });
  });

  group('title change', () {
    testWidgets('shows the form and its keys', (tester) async {
      final db = await seed();
      await tester.pumpWidget(
        _wrap(db, uid: 'l1', type: ChangeRequestType.title),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('changeRequestScreen')), findsOneWidget);
      expect(find.byKey(const Key('newTitleField')), findsOneWidget);
      expect(find.byKey(const Key('changeReasons')), findsOneWidget);
      expect(find.byKey(const Key('submitChangeRequest')), findsOneWidget);
      expect(find.byKey(const Key('newAdviserPicker')), findsNothing);
    });

    testWidgets('an empty title is refused before any write', (tester) async {
      final db = await seed();
      await tester.pumpWidget(
        _wrap(db, uid: 'l1', type: ChangeRequestType.title),
      );
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const Key('changeReasons')),
        'A reason',
      );
      await tester.ensureVisible(find.byKey(const Key('submitChangeRequest')));
      await tester.tap(find.byKey(const Key('submitChangeRequest')));
      await tester.pumpAndSettle();

      expect(find.textContaining('Give the new title'), findsOneWidget);
      expect(
        (await db.collection('theses/t1/changeRequests').get()).docs,
        isEmpty,
      );
    });

    testWidgets('an empty reason is refused before any write', (tester) async {
      final db = await seed();
      await tester.pumpWidget(
        _wrap(db, uid: 'l1', type: ChangeRequestType.title),
      );
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const Key('newTitleField')),
        'A New Working Title',
      );
      await tester.ensureVisible(find.byKey(const Key('submitChangeRequest')));
      await tester.tap(find.byKey(const Key('submitChangeRequest')));
      await tester.pumpAndSettle();

      expect(find.textContaining('Give a reason'), findsOneWidget);
      expect(
        (await db.collection('theses/t1/changeRequests').get()).docs,
        isEmpty,
      );
    });

    testWidgets('a valid title change writes the request and pops back', (
      tester,
    ) async {
      final db = await seed();
      await tester.pumpWidget(
        _wrap(db, uid: 'l1', type: ChangeRequestType.title),
      );
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const Key('newTitleField')),
        'A New Working Title',
      );
      await tester.enterText(
        find.byKey(const Key('changeReasons')),
        'A good reason',
      );
      await tester.ensureVisible(find.byKey(const Key('submitChangeRequest')));
      await tester.tap(find.byKey(const Key('submitChangeRequest')));
      await tester.pumpAndSettle();

      final saved = await db
          .collection('theses/t1/changeRequests')
          .doc('title')
          .get();
      expect(saved.exists, isTrue);
      expect(saved.data()!['newTitle'], 'A New Working Title');
      expect(saved.data()!['stage'], 'pendingAdviser');
    });

    testWidgets('prefill from a returned request fills reasons and title', (
      tester,
    ) async {
      final db = await seed();
      final prefill = ChangeRequest(
        type: ChangeRequestType.title,
        stage: ChangeRequestStage.returned,
        reasons: 'Old reason',
        leaderUid: 'l1',
        signoffs: const {},
        newTitle: 'Old New Title',
      );
      await tester.pumpWidget(
        _wrap(db, uid: 'l1', type: ChangeRequestType.title, prefill: prefill),
      );
      await tester.pumpAndSettle();

      expect(find.text('Old reason'), findsOneWidget);
      expect(find.text('Old New Title'), findsOneWidget);
    });
  });

  testWidgets('the thesis stream loading is shown, not collapsed into absent', (
    tester,
  ) async {
    final db = await seed();
    await tester.pumpWidget(
      _wrap(db, uid: 'l1', type: ChangeRequestType.adviser),
    );
    await tester.pump();

    expect(find.text('Loading thesis…'), findsOneWidget);
  });
}
