import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ethesishub/features/admin/faculty_invites_screen.dart';
import 'package:ethesishub/providers/auth_providers.dart';

Widget wrap(FakeFirebaseFirestore db,
        {String email = 'coord@isufst.edu.ph'}) =>
    ProviderScope(
      overrides: [
        firestoreProvider.overrideWithValue(db),
        firebaseAuthProvider.overrideWithValue(MockFirebaseAuth(
          signedIn: true,
          mockUser: MockUser(
              uid: 'coord-1', email: email, isEmailVerified: true),
        )),
      ],
      // the app shell supplies the Scaffold in the real app.
      child: const MaterialApp(
        home: Scaffold(body: FacultyInvitesScreen()),
      ),
    );

/// The form plus the invite list exceeds the default 800x600 test surface.
void useTallSurface(WidgetTester tester) {
  tester.view.physicalSize = const Size(1000, 2000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

void main() {
  testWidgets('issuing an invite writes the role, college and specialization',
      (tester) async {
    useTallSurface(tester);
    final db = FakeFirebaseFirestore();
    await tester.pumpWidget(wrap(db));
    await tester.pumpAndSettle();

    await tester.enterText(
        find.byKey(const Key('inviteEmail')), 'Armada@ISUFST.edu.ph');
    await tester.enterText(find.byKey(const Key('inviteSpecialization')),
        'Software Engineering');
    await tester.tap(find.byKey(const Key('sendInvite')));
    await tester.pumpAndSettle();

    // The document id is the LOWERCASED address — promotion looks the invite
    // up by the signed-in user's lowercased email, so a mixed-case id would
    // never be found and the promotion would silently never happen.
    final doc =
        await db.collection('facultyInvites').doc('armada@isufst.edu.ph').get();
    expect(doc.exists, isTrue);
    expect(doc.data()!['role'], 'faculty');
    expect(doc.data()!['college'], 'CICT');
    expect(doc.data()!['specialization'], 'Software Engineering');
    expect(doc.data()!['invitedBy'], 'coord-1',
        reason: 'the rules pin invitedBy to the caller uid');
    expect(doc.data()!['consumedAt'], isNull);
  });

  testWidgets('a coordinator cannot invite themselves', (tester) async {
    // The rules refuse this too — this is the client half, so the coordinator
    // gets a reason instead of a permission denial. It is the guard that
    // closes the self-elevation path: without it a coordinator could invite
    // themselves as dean and claim it on their next sign-in.
    useTallSurface(tester);
    final db = FakeFirebaseFirestore();
    await tester.pumpWidget(wrap(db, email: 'coord@isufst.edu.ph'));
    await tester.pumpAndSettle();

    await tester.enterText(
        find.byKey(const Key('inviteEmail')), 'COORD@isufst.edu.ph');
    await tester.tap(find.byKey(const Key('sendInvite')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('error')), findsOneWidget);
    final error = tester.widget<Text>(find.byKey(const Key('error')));
    expect(error.data, contains('cannot invite yourself'));

    final all = await db.collection('facultyInvites').get();
    expect(all.docs, isEmpty,
        reason: 'a self-invite must never reach the repository');
  });

  testWidgets('a malformed address is rejected before any write',
      (tester) async {
    useTallSurface(tester);
    final db = FakeFirebaseFirestore();
    await tester.pumpWidget(wrap(db));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('inviteEmail')), 'not-an-email');
    await tester.tap(find.byKey(const Key('sendInvite')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('error')), findsOneWidget);
    expect((await db.collection('facultyInvites').get()).docs, isEmpty);
  });

  testWidgets('the dean role can be issued, not just faculty', (tester) async {
    // The owner chose to allow all three invitable roles so a second
    // coordinator or a new dean can be onboarded without the Console.
    useTallSurface(tester);
    final db = FakeFirebaseFirestore();
    await tester.pumpWidget(wrap(db));
    await tester.pumpAndSettle();

    await tester.enterText(
        find.byKey(const Key('inviteEmail')), 'siason@isufst.edu.ph');
    await tester.tap(find.byKey(const Key('inviteRole')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('dean').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('sendInvite')));
    await tester.pumpAndSettle();

    final doc =
        await db.collection('facultyInvites').doc('siason@isufst.edu.ph').get();
    expect(doc.data()!['role'], 'dean');
  });

  testWidgets('an open invite can be retracted, a claimed one cannot',
      (tester) async {
    // A consumed invite is the permanent record of a promotion that actually
    // happened; offering "Retract" on it would erase evidence rather than
    // cancel anything.
    useTallSurface(tester);
    final db = FakeFirebaseFirestore();
    await db.collection('facultyInvites').doc('open@isufst.edu.ph').set({
      'role': 'faculty', 'invitedBy': 'coord-1', 'consumedAt': null,
    });
    await db.collection('facultyInvites').doc('claimed@isufst.edu.ph').set({
      'role': 'faculty', 'invitedBy': 'coord-1',
      'consumedAt': Timestamp.fromDate(DateTime.utc(2026, 3, 1)),
    });

    await tester.pumpWidget(wrap(db));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('retract_open@isufst.edu.ph')), findsOneWidget);
    expect(find.byKey(const Key('retract_claimed@isufst.edu.ph')), findsNothing);
    expect(find.text('Claimed'), findsOneWidget);

    await tester.tap(find.byKey(const Key('retract_open@isufst.edu.ph')));
    await tester.pumpAndSettle();

    expect(
        (await db.collection('facultyInvites').doc('open@isufst.edu.ph').get())
            .exists,
        isFalse);
    expect(
        (await db
                .collection('facultyInvites')
                .doc('claimed@isufst.edu.ph')
                .get())
            .exists,
        isTrue);
  });
}
