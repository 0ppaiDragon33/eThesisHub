import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ethesishub/data/models/faculty_directory_entry.dart';
import 'package:ethesishub/data/models/thesis.dart';
import 'package:ethesishub/data/repositories/user_repository.dart';
import 'package:ethesishub/features/admin/users_screen.dart';
import 'package:ethesishub/providers/auth_providers.dart';
import 'package:ethesishub/providers/thesis_providers.dart';

/// Refuses every designation and activation write with `permission-denied`,
/// the way the rules do when a coordinator reaches the self-edit ban through
/// a path the UI did not anticipate -- or when the `users` write lands and
/// the `facultyDirectory` mirror is refused, which
/// [UserRepository.setDesignation] rethrows.
class RefusingUserRepository extends UserRepository {
  RefusingUserRepository(super.db);

  static FirebaseException get _denied => FirebaseException(
        plugin: 'cloud_firestore',
        code: 'permission-denied',
        message: 'Missing or insufficient permissions.',
      );

  @override
  Future<void> setDesignation({
    required String uid,
    required bool adviser,
    required bool panelist,
  }) async =>
      throw _denied;

  @override
  Future<void> setActive(String uid, bool active) async => throw _denied;
}

Widget wrap(
  FakeFirebaseFirestore db, {
  String uid = 'coord-1',
  String email = 'coord@isufst.edu.ph',
  List<Override> extraOverrides = const [],
}) =>
    ProviderScope(
      overrides: [
        firestoreProvider.overrideWithValue(db),
        firebaseAuthProvider.overrideWithValue(MockFirebaseAuth(
          signedIn: true,
          mockUser: MockUser(uid: uid, email: email, isEmailVerified: true),
        )),
        ...extraOverrides,
      ],
      // The app shell supplies the Scaffold in the real app.
      child: const MaterialApp(home: Scaffold(body: UsersScreen())),
    );

Map<String, dynamic> userDoc(
  String fullName, {
  String role = 'faculty',
  bool active = true,
  bool nominableAsAdviser = true,
  bool nominableAsPanelist = true,
  String email = '',
}) =>
    {
      'fullName': fullName,
      'email': email.isEmpty ? '${fullName.toLowerCase()}@isufst.edu.ph' : email,
      'role': role,
      'active': active,
      'createdAt': Timestamp.fromDate(DateTime.utc(2026, 1, 1)),
      'nominableAsAdviser': nominableAsAdviser,
      'nominableAsPanelist': nominableAsPanelist,
    };

void useWideSurface(WidgetTester tester) {
  // Wide enough for the hand-rolled flex row layout to lay out without
  // wrapping oddly, and tall enough that the filters and at least a few
  // rows fit without scrolling the whole page out from under a tap.
  tester.view.physicalSize = const Size(1400, 1400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

void main() {
  testWidgets('lists every seeded account', (tester) async {
    useWideSurface(tester);
    final db = FakeFirebaseFirestore();
    await db.collection('users').doc('u1').set(userDoc('Alma Cruz'));
    await db.collection('users').doc('u2').set(userDoc('Ben Reyes', role: 'dean'));

    await tester.pumpWidget(wrap(db));
    await tester.pumpAndSettle();

    expect(find.text('Alma Cruz'), findsOneWidget);
    expect(find.text('alma cruz@isufst.edu.ph'), findsOneWidget);
    expect(find.text('Ben Reyes'), findsOneWidget);
  });

  testWidgets(
      "the coordinator's own row renders its controls disabled with a "
      'reason', (tester) async {
    useWideSurface(tester);
    final db = FakeFirebaseFirestore();
    await db
        .collection('users')
        .doc('coord-1')
        .set(userDoc('The Coordinator', role: 'coordinator'));

    await tester.pumpWidget(wrap(db));
    await tester.pumpAndSettle();

    final activeSwitch = tester
        .widget<Switch>(find.byKey(const Key('activeSwitch-coord-1')));
    expect(activeSwitch.onChanged, isNull,
        reason: 'the rules refuse request.auth.uid == uid');
    expect(find.byKey(const Key('ownRowReason-coord-1')), findsOneWidget);
  });

  testWidgets('role renders as text with no control anywhere', (tester) async {
    useWideSurface(tester);
    final db = FakeFirebaseFirestore();
    await db.collection('users').doc('u1').set(userDoc('Alma Cruz'));

    await tester.pumpWidget(wrap(db));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('roleText-u1')), findsOneWidget);
    final roleText = tester.widget<Text>(find.byKey(const Key('roleText-u1')));
    expect(roleText.data, 'faculty');

    // The only two DropdownButtons on the whole screen are the role and
    // active FILTERS -- never one per row.
    expect(find.byWidgetPredicate((w) => w is DropdownButton),
        findsNWidgets(2));
  });

  testWidgets('there is no delete control anywhere', (tester) async {
    useWideSurface(tester);
    final db = FakeFirebaseFirestore();
    await db.collection('users').doc('u1').set(userDoc('Alma Cruz'));
    await db
        .collection('users')
        .doc('u2')
        .set(userDoc('Zed Santos', role: 'dean'));

    await tester.pumpWidget(wrap(db));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.delete), findsNothing);
    expect(find.byIcon(Icons.delete_outline), findsNothing);
    expect(find.textContaining('Delete'), findsNothing);
  });

  testWidgets('toggling active calls through to the repository',
      (tester) async {
    useWideSurface(tester);
    final db = FakeFirebaseFirestore();
    await db.collection('users').doc('u1').set(userDoc('Alma Cruz'));

    await tester.pumpWidget(wrap(db));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.byKey(const Key('activeSwitch-u1')));
    await tester.tap(find.byKey(const Key('activeSwitch-u1')));
    await tester.pumpAndSettle();

    final doc = await db.collection('users').doc('u1').get();
    expect(doc.data()!['active'], isFalse);
  });

  testWidgets('setting a designation calls through to the repository',
      (tester) async {
    useWideSurface(tester);
    final db = FakeFirebaseFirestore();
    await db.collection('users').doc('u1').set(userDoc('Alma Cruz'));

    await tester.pumpWidget(wrap(db));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.byKey(const Key('adviserCheckbox-u1')));
    await tester.tap(find.byKey(const Key('adviserCheckbox-u1')));
    await tester.pumpAndSettle();

    final doc = await db.collection('users').doc('u1').get();
    expect(doc.data()!['nominableAsAdviser'], isFalse);
    // Panelist untouched by the adviser write.
    expect(doc.data()!['nominableAsPanelist'], isTrue);
  });

  testWidgets('the filter narrows by role', (tester) async {
    useWideSurface(tester);
    final db = FakeFirebaseFirestore();
    await db.collection('users').doc('u1').set(userDoc('Alma Faculty'));
    await db
        .collection('users')
        .doc('u2')
        .set(userDoc('Ben Dean', role: 'dean'));

    await tester.pumpWidget(wrap(db));
    await tester.pumpAndSettle();

    expect(find.text('Alma Faculty'), findsOneWidget);
    expect(find.text('Ben Dean'), findsOneWidget);

    await tester.tap(find.byKey(const Key('roleFilter')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('dean').last);
    await tester.pumpAndSettle();

    expect(find.text('Alma Faculty'), findsNothing);
    expect(find.text('Ben Dean'), findsOneWidget);
  });

  testWidgets('the filter narrows by active state', (tester) async {
    useWideSurface(tester);
    final db = FakeFirebaseFirestore();
    await db.collection('users').doc('u1').set(userDoc('Active Faculty'));
    await db
        .collection('users')
        .doc('u2')
        .set(userDoc('Inactive Faculty', active: false));

    await tester.pumpWidget(wrap(db));
    await tester.pumpAndSettle();

    // Defaults to active accounts only.
    expect(find.text('Active Faculty'), findsOneWidget);
    expect(find.text('Inactive Faculty'), findsNothing);

    await tester.tap(find.byKey(const Key('activeFilter')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('All').last);
    await tester.pumpAndSettle();

    expect(find.text('Active Faculty'), findsOneWidget);
    expect(find.text('Inactive Faculty'), findsOneWidget);
  });

  testWidgets('students are hidden by default and appear when unfiltered',
      (tester) async {
    useWideSurface(tester);
    final db = FakeFirebaseFirestore();
    await db.collection('users').doc('u1').set(userDoc('Alma Faculty'));
    await db
        .collection('users')
        .doc('s1')
        .set(userDoc('Stu Dent', role: 'student'));

    await tester.pumpWidget(wrap(db));
    await tester.pumpAndSettle();

    expect(find.text('Stu Dent'), findsNothing,
        reason: 'otherwise nothing anywhere can deactivate a graduated '
            'student without wading through every account');

    await tester.tap(find.byKey(const Key('showStudentsToggle')));
    await tester.pumpAndSettle();

    expect(find.text('Stu Dent'), findsOneWidget);
    // No designation control for a role that can never be nominated.
    expect(find.byKey(const Key('adviserCheckbox-s1')), findsNothing);
    expect(find.byKey(const Key('panelistCheckbox-s1')), findsNothing);
    // But the active control IS present -- deactivation must still work.
    expect(find.byKey(const Key('activeSwitch-s1')), findsOneWidget);
  });

  testWidgets(
      'an account with no directory entry is marked not yet signed in',
      (tester) async {
    useWideSurface(tester);
    final db = FakeFirebaseFirestore();
    // u1 has never signed in -- invited and designated, but no
    // facultyDirectory entry exists yet (spec §4.2.1).
    await db.collection('users').doc('u1').set(userDoc('Never Signed In'));
    // u2 has signed in at least once.
    await db.collection('users').doc('u2').set(userDoc('Has Signed In'));
    await db.collection('facultyDirectory').doc('u2').set({
      'fullName': 'Has Signed In',
      'role': 'faculty',
    });

    await tester.pumpWidget(wrap(db));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('notSignedIn-u1')), findsOneWidget);
    expect(find.byKey(const Key('notSignedIn-u2')), findsNothing);
  });

  testWidgets(
      "the coordinator's own DESIGNATION controls are disabled with a "
      'reason, not only the active switch', (tester) async {
    // The `users` coordinator arm carries `request.auth.uid != uid` for ALL
    // seven writable fields, not only `active`, so tapping your own Adviser
    // or Panelist box is always refused. Spec §5.2 asks for "controls
    // disabled and the reason stated" -- plural.
    useWideSurface(tester);
    final db = FakeFirebaseFirestore();
    await db
        .collection('users')
        .doc('coord-1')
        .set(userDoc('The Coordinator', role: 'coordinator'));
    await db.collection('users').doc('u2').set(userDoc('Someone Else'));

    await tester.pumpWidget(wrap(db));
    await tester.pumpAndSettle();

    final adviser = tester
        .widget<Checkbox>(find.byKey(const Key('adviserCheckbox-coord-1')));
    final panelist = tester
        .widget<Checkbox>(find.byKey(const Key('panelistCheckbox-coord-1')));
    expect(adviser.onChanged, isNull,
        reason: 'the rules refuse request.auth.uid == uid on '
            'nominableAsAdviser too, not only on active');
    expect(panelist.onChanged, isNull);
    expect(find.byKey(const Key('ownRowDesignationReason-coord-1')),
        findsOneWidget);

    // Another account's controls are still live -- the ban is about the
    // reader's own row, not about designation generally.
    expect(
        tester
            .widget<Checkbox>(find.byKey(const Key('adviserCheckbox-u2')))
            .onChanged,
        isNotNull);
  });

  testWidgets('a refused designation write is shown, with its Firestore code',
      (tester) async {
    // Spec §7: a refused write says WHICH write was refused. The write was
    // neither awaited nor caught, so a refusal became an unhandled Future
    // error and the checkbox silently snapped back -- which also hid the
    // real case where the `users` write succeeds and the facultyDirectory
    // mirror is refused, leaving authority and mirror divergent with
    // nothing on screen saying so.
    useWideSurface(tester);
    final db = FakeFirebaseFirestore();
    await db.collection('users').doc('u1').set(userDoc('Alma Cruz'));

    await tester.pumpWidget(wrap(db, extraOverrides: [
      userRepositoryProvider.overrideWithValue(RefusingUserRepository(db)),
    ]));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.byKey(const Key('adviserCheckbox-u1')));
    await tester.tap(find.byKey(const Key('adviserCheckbox-u1')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('designationWriteError-u1')), findsOneWidget);
    expect(find.textContaining('Alma Cruz'), findsWidgets);
    expect(find.byKey(const Key('errorCode')), findsOneWidget);
    expect(
        tester.widget<Text>(find.byKey(const Key('errorCode'))).data,
        '[permission-denied]');
  });

  testWidgets('a refused active write is shown, with its Firestore code',
      (tester) async {
    useWideSurface(tester);
    final db = FakeFirebaseFirestore();
    await db.collection('users').doc('u1').set(userDoc('Alma Cruz'));

    await tester.pumpWidget(wrap(db, extraOverrides: [
      userRepositoryProvider.overrideWithValue(RefusingUserRepository(db)),
    ]));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.byKey(const Key('activeSwitch-u1')));
    await tester.tap(find.byKey(const Key('activeSwitch-u1')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('activeWriteError-u1')), findsOneWidget);
    expect(
        tester.widget<Text>(find.byKey(const Key('errorCode'))).data,
        '[permission-denied]');
  });

  testWidgets('the Positions column counts advisees and panel seats apart',
      (tester) async {
    // The one column the spec argues for on its own merits (§5.1, because
    // of D30) and the only row element that can silently show a wrong
    // number. The two counts differ (2 vs 3) precisely so a fold that read
    // the wrong field, or added the two together, fails here rather than
    // agreeing by coincidence.
    useWideSurface(tester);
    final db = FakeFirebaseFirestore();
    for (final f in ['Adv Isor', 'Pan Elist', 'Idle Faculty']) {
      await db
          .collection('users')
          .doc(f.split(' ').first.toLowerCase())
          .set(userDoc(f));
    }

    Future<void> thesis(String id, String adviser, List<String> panel) =>
        db.collection('theses').doc(id).set({
          'leaderUid': 'l-$id',
          'status': 'draft',
          'adviserUid': adviser,
          'panelistUids': panel,
          'memberNames': <String>[],
          'workingTitle': 'T',
          'college': 'CICT',
          'program': 'BSIT',
          'semester': 'First',
          'academicYear': '2026-2027',
        });

    // 'adv' advises two groups and sits on three panels.
    await thesis('t1', 'adv', ['pan']);
    await thesis('t2', 'adv', ['pan']);
    await thesis('t3', 'other', ['adv', 'pan']);
    await thesis('t4', 'other', ['adv']);
    await thesis('t5', 'other', ['adv']);

    await tester.pumpWidget(wrap(db));
    await tester.pumpAndSettle();

    expect(tester.widget<Text>(find.byKey(const Key('positions-adv'))).data,
        '2 advising · 3 panel');
    // Advises nothing, but sits on three panels -- exactly the D30 case
    // the column exists to put in front of the coordinator.
    expect(tester.widget<Text>(find.byKey(const Key('positions-pan'))).data,
        '0 advising · 3 panel');
    // Genuinely holds nothing.
    expect(find.byKey(const Key('positions-idle')), findsNothing);
  });

  testWidgets(
      'a failed theses query says so instead of rendering as "holds '
      'nothing"', (tester) async {
    // Spec §7: "the row shows what it knows and says what it could not
    // load". Rendering "—" for every row would be indistinguishable from
    // holding nothing -- the exact misreading §5.1 built this column to
    // prevent.
    useWideSurface(tester);
    final db = FakeFirebaseFirestore();
    await db.collection('users').doc('u1').set(userDoc('Alma Cruz'));

    await tester.pumpWidget(wrap(db, extraOverrides: [
      allThesesProvider.overrideWith((ref) => Stream<List<Thesis>>.error(
            FirebaseException(
                plugin: 'cloud_firestore', code: 'permission-denied'),
          )),
    ]));
    await tester.pumpAndSettle();

    // The account list itself still renders -- a failed positions query
    // must not blank it.
    expect(find.text('Alma Cruz'), findsOneWidget);
    expect(find.byKey(const Key('positionsUnavailable')), findsOneWidget);
    expect(find.byKey(const Key('positionsUnknown-u1')), findsOneWidget);
    expect(find.byKey(const Key('positions-u1')), findsNothing);
  });

  testWidgets('a failed directory query says so instead of going quiet',
      (tester) async {
    // A failed directory read silently withdrew every "not yet signed in"
    // marker: the screen looked exactly as it does when every account has
    // an entry.
    useWideSurface(tester);
    final db = FakeFirebaseFirestore();
    await db.collection('users').doc('u1').set(userDoc('Alma Cruz'));

    await tester.pumpWidget(wrap(db, extraOverrides: [
      allDirectoryProvider
          .overrideWith((ref) => Stream<List<FacultyDirectoryEntry>>.error(
                FirebaseException(
                    plugin: 'cloud_firestore', code: 'permission-denied'),
              )),
    ]));
    await tester.pumpAndSettle();

    expect(find.text('Alma Cruz'), findsOneWidget);
    expect(find.byKey(const Key('directoryUnavailable')), findsOneWidget);
    // And the marker is NOT claimed either way, since nothing is known.
    expect(find.byKey(const Key('notSignedIn-u1')), findsNothing);
  });
}
