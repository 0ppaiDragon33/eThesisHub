import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:ethesishub/features/thesis/thesis_status_screen.dart';
import 'package:ethesishub/providers/auth_providers.dart';

Future<FakeFirebaseFirestore> seeded(
  String status, {
  bool declined = false,
  Map<String, dynamic> extraFields = const {},
}) async {
  final db = FakeFirebaseFirestore();
  await db.collection('users').doc('leader-1').set({
    'fullName': 'Karl Joshua P. Vargas', 'email': 'l@isufst.edu.ph',
    'role': 'student', 'active': true,
  });
  await db.collection('theses').doc('t1').set({
    'leaderUid': 'leader-1', 'status': status, 'panelistUids': ['p1'],
    'adviserUid': 'a1', 'memberNames': ['Bagsain, Karlo June'],
    'workingTitle': 'eThesisHub', 'college': 'CICT', 'program': 'BSIT',
    'semester': 'First', 'academicYear': '2026-2027',
    ...extraFields,
  });
  final noms = db.collection('theses').doc('t1').collection('nominations');
  if (declined) {
    await noms.doc('a1').set({
      'nomineeUid': 'a1',
      'nomineeName': 'Dr. Armada', 'position': 'adviser', 'exOfficio': false,
      'conformeStatus': 'declined', 'respondedAt': null,
      'declineReason': 'At capacity',
    });
  } else {
    await noms.doc('a1').set({
      'nomineeUid': 'a1',
      'nomineeName': 'Dr. Armada', 'position': 'adviser', 'exOfficio': false,
      'conformeStatus': 'accepted', 'respondedAt': null,
      'declineReason': null,
    });
  }
  return db;
}

Widget wrap(FakeFirebaseFirestore db) => ProviderScope(
      overrides: [
        firestoreProvider.overrideWithValue(db),
        firebaseAuthProvider.overrideWithValue(MockFirebaseAuth(
          signedIn: true,
          mockUser: MockUser(
              uid: 'leader-1',
              email: 'l@isufst.edu.ph',
              isEmailVerified: true),
        )),
      ],
      child: MaterialApp.router(
        routerConfig: GoRouter(
          initialLocation: '/thesis',
          routes: [
            GoRoute(
              path: '/thesis',
              builder: (_, _) => const ThesisStatusScreen(),
            ),
            GoRoute(
              path: '/thesis/nominate',
              builder: (context, state) => Scaffold(
                appBar: AppBar(
                  title: Text('Nominate for ${state.uri.queryParameters['id']}'),
                ),
              ),
            ),
          ],
        ),
      ),
    );

void main() {
  testWidgets('shows a declined slot with its reason', (tester) async {
    await tester.pumpWidget(
        wrap(await seeded('nominationPendingConforme', declined: true)));
    await tester.pumpAndSettle();

    expect(find.textContaining('Dr. Armada'), findsOneWidget);
    expect(find.textContaining('Declined'), findsOneWidget);
    expect(find.textContaining('At capacity'), findsOneWidget);
  });

  testWidgets('Form 1 download appears only once approved', (tester) async {
    await tester.pumpWidget(
        wrap(await seeded('nominationPendingConforme', declined: true)));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('downloadForm1')), findsNothing);

    await tester.pumpWidget(wrap(await seeded('nominationApproved')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('downloadForm1')), findsOneWidget);
  });

  testWidgets(
      'a draft thesis offers the nominate action, and reaching it works',
      (tester) async {
    await tester.pumpWidget(wrap(await seeded('draft')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('nominateAction')), findsOneWidget);

    await tester.tap(find.byKey(const Key('nominateAction')));
    await tester.pumpAndSettle();

    expect(find.text('Nominate for t1'), findsOneWidget);
  });

  testWidgets('a non-draft thesis with no decline offers no nominate action',
      (tester) async {
    await tester.pumpWidget(
        wrap(await seeded('nominationPendingConforme', declined: false)));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('nominateAction')), findsNothing);
  });

  testWidgets(
      'a declined nominee stalls the thesis: no working re-nominate button '
      'is offered, and the leader is told to contact their coordinator',
      (tester) async {
    await tester.pumpWidget(
        wrap(await seeded('nominationPendingConforme', declined: true)));
    await tester.pumpAndSettle();

    // The security rules only allow nomination create/delete while the
    // thesis is `draft` (see firestore.rules, mayCreateNomination()/the
    // nominations delete rule), and there is no rule path that lets the
    // leader move the thesis itself back to `draft` from
    // `nominationPendingConforme`. Shipping a re-nominate action here would
    // therefore fail with permission-denied for every real user, so the
    // screen must not offer one — it must only explain the gap.
    expect(find.byKey(const Key('nominateAction')), findsNothing);
    expect(find.byKey(const Key('reNominationGap')), findsOneWidget);
    expect(find.textContaining('Research Coordinator'), findsOneWidget);
  });

  testWidgets(
      'a rejected title set offers resubmit, and the remark reads before it '
      'so the student knows what to fix', (tester) async {
    await tester.pumpWidget(wrap(await seeded('titleRejected', extraFields: {
      'titleRejectionRemark': 'Scope is too broad for one semester.',
      'titleDecidedAt': Timestamp.fromDate(DateTime.utc(2026, 5, 1)),
      'titleDecidedBy': 'dean-1',
      'titleRound': 1,
    })));
    await tester.pumpAndSettle();

    final resubmit = find.byKey(const Key('goToSubmitTitles'));
    expect(resubmit, findsOneWidget);
    expect(find.text('Resubmit candidate titles'), findsOneWidget);

    final remark = find.textContaining('Scope is too broad for one semester.');
    expect(remark, findsOneWidget);

    // The remark must read above the resubmit action in the same scrolling
    // list — a lower y-position means it appears first.
    final remarkY = tester.getTopLeft(remark).dy;
    final resubmitY = tester.getTopLeft(resubmit).dy;
    expect(remarkY, lessThan(resubmitY));
  });

  testWidgets(
      'consolidated panel comments appear once titleDecidedAt is set, '
      'grouped per commenter under each candidate, filtered to the current '
      'round', (tester) async {
    final db = await seeded('titleApproved', extraFields: {
      'titleDecidedAt': Timestamp.fromDate(DateTime.utc(2026, 5, 1)),
      'titleDecidedBy': 'dean-1',
      'approvedTitleId': 'ct-round2',
      'titleRound': 2,
    });

    final theses = db.collection('theses').doc('t1');
    // Round 1 (superseded) candidate + comment — must not appear.
    await theses.collection('candidateTitles').doc('ct-round1').set({
      'titleText': 'Old round title',
      'justificationPath': 'p1',
      'justificationUrl': 'u1',
      'round': 1,
    });
    await theses.collection('titleComments').add({
      'candidateTitleId': 'ct-round1',
      'authorUid': 'p1',
      'authorName': 'Old Round Commenter',
      'authorRole': 'Panel Member',
      'body': 'This should never render.',
      'createdAt': Timestamp.fromDate(DateTime.utc(2026, 4, 1)),
    });
    // Round 2 (current) candidate + two comments from two authors.
    await theses.collection('candidateTitles').doc('ct-round2').set({
      'titleText': 'Current round title',
      'justificationPath': 'p2',
      'justificationUrl': 'u2',
      'round': 2,
    });
    await theses.collection('titleComments').add({
      'candidateTitleId': 'ct-round2',
      'authorUid': 'a1',
      'authorName': 'Dr. Noel A. Armada',
      'authorRole': 'Adviser',
      'body': 'Narrow the respondents to one college.',
      'createdAt': Timestamp.fromDate(DateTime.utc(2026, 4, 20)),
    });
    await theses.collection('titleComments').add({
      'candidateTitleId': 'ct-round2',
      'authorUid': 'p1',
      'authorName': 'Dr. Test Panelist',
      'authorRole': 'Panel Member',
      'body': 'Good direction overall.',
      'createdAt': Timestamp.fromDate(DateTime.utc(2026, 4, 21)),
    });

    await tester.pumpWidget(wrap(db));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('consolidatedComments')), findsOneWidget);
    expect(find.text('Current round title'), findsOneWidget);
    expect(find.text('[Dr. Noel A. Armada — Adviser]'), findsOneWidget);
    expect(find.text('[Dr. Test Panelist — Panel Member]'), findsOneWidget);
    expect(find.text('Narrow the respondents to one college.'), findsOneWidget);
    expect(find.text('Good direction overall.'), findsOneWidget);

    // Filtered out: the superseded round's title and its comment.
    expect(find.text('Old round title'), findsNothing);
    expect(find.text('This should never render.'), findsNothing);
    expect(find.textContaining('Old Round Commenter'), findsNothing);
  });
}
