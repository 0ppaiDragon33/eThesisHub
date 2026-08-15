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
}
