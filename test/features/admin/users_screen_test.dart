import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ethesishub/features/admin/users_screen.dart';
import 'package:ethesishub/providers/auth_providers.dart';

Widget wrap(FakeFirebaseFirestore db,
        {String uid = 'coord-1', String email = 'coord@isufst.edu.ph'}) =>
    ProviderScope(
      overrides: [
        firestoreProvider.overrideWithValue(db),
        firebaseAuthProvider.overrideWithValue(MockFirebaseAuth(
          signedIn: true,
          mockUser: MockUser(uid: uid, email: email, isEmailVerified: true),
        )),
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
  // Wide enough for the DataTable to lay out without wrapping oddly, and
  // tall enough that the filters and at least a few rows fit without
  // scrolling the whole page out from under a tap.
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
}
