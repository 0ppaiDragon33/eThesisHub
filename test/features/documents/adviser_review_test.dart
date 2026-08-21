import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ethesishub/data/models/chapter.dart';
import 'package:ethesishub/features/documents/chapter_detail_screen.dart';
import 'package:ethesishub/providers/auth_providers.dart';

/// Seeds a thesis with adviser `a1` and leader `l1`, Chapter I already at
/// version 1, and a `users/a1` faculty profile so the adviser's posted
/// feedback carries a real name.
Future<FakeFirebaseFirestore> seed() async {
  final db = FakeFirebaseFirestore();
  await db.collection('theses').doc('t1').set({
    'leaderUid': 'l1', 'adviserUid': 'a1', 'status': 'titleApproved',
    'panelistUids': <String>[], 'memberNames': <String>[],
    'workingTitle': 'T', 'college': 'CICT', 'program': 'BSIT',
    'semester': 'First', 'academicYear': '2026-2027',
  });
  await db.collection('users').doc('a1').set({
    'fullName': 'Dr. Adviser', 'email': 'a@isufst.edu.ph',
    'role': 'faculty', 'active': true,
  });
  // The upload control is gated on `thesis.leaderUid == me.uid`, and `me`
  // comes from the leader's own `users/l1` profile document -- needed for
  // the leader-view portion of "marking approved locks the upload control
  // for the leader" below.
  await db.collection('users').doc('l1').set({
    'fullName': 'Leader One', 'email': 'l1@isufst.edu.ph',
    'role': 'student', 'active': true,
  });
  await db.collection('theses/t1/documents').doc('chapterI').set({
    'type': 'chapterI', 'currentVersion': 1, 'status': 'submitted',
  });
  await db
      .collection('theses/t1/documents/chapterI/versions')
      .doc('1')
      .set({
    'version': 1, 'storagePath': 'p', 'fileUrl': 'https://example.test/v1',
    'uploadedBy': 'l1', 'mimeType': 'application/pdf', 'sizeBytes': 10,
  });
  return db;
}

// Without this, `FirebaseAuth.instance` throws `[core/no-app]` because no
// app is initialised in a widget test, `authStateProvider` settles into
// AsyncError, and any uid read off it is silently null forever. Every other
// screen that reads a uid off `authStateProvider` overrides this the same
// way -- see upload_version_test.dart's `_wrap`.
Widget _wrap(FakeFirebaseFirestore db, {required String uid}) =>
    ProviderScope(
      overrides: [
        firestoreProvider.overrideWithValue(db),
        firebaseAuthProvider.overrideWithValue(MockFirebaseAuth(
          signedIn: true,
          mockUser: MockUser(
              uid: uid, email: '$uid@isufst.edu.ph', isEmailVerified: true),
        )),
      ],
      child: MaterialApp(
        home: ChapterDetailScreen(
          thesisId: 't1',
          chapter: ChapterId.chapterI,
        ),
      ),
    );

/// The review section adds enough height that the default 800x600 test
/// surface clips the mark/approve buttons off-screen, so taps silently miss.
void _useTallSurface(WidgetTester tester) {
  tester.view.physicalSize = const Size(1200, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

void main() {
  testWidgets('the adviser sees the review controls', (tester) async {
    _useTallSurface(tester);
    final db = await seed();
    await tester.pumpWidget(_wrap(db, uid: 'a1'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('feedbackBody')), findsOneWidget);
    expect(find.byKey(const Key('postFeedback')), findsOneWidget);
    expect(find.byKey(const Key('markRevise')), findsOneWidget);
    expect(find.byKey(const Key('markApproved')), findsOneWidget);
  });

  testWidgets('a student does NOT see the review controls', (tester) async {
    _useTallSurface(tester);
    final db = await seed();
    await tester.pumpWidget(_wrap(db, uid: 'l1'));
    await tester.pumpAndSettle();

    // The rules deny the write anyway, but a button that is visible and
    // always fails is worse than no button.
    expect(find.byKey(const Key('markApproved')), findsNothing);
  });

  testWidgets('posting feedback writes it against the current version',
      (tester) async {
    _useTallSurface(tester);
    final db = await seed();
    await tester.pumpWidget(_wrap(db, uid: 'a1'));
    await tester.pumpAndSettle();

    await tester.enterText(
        find.byKey(const Key('feedbackBody')), 'Please expand section 1.2.');
    await tester.tap(find.byKey(const Key('postFeedback')));
    await tester.pumpAndSettle();

    final saved =
        await db.collection('theses/t1/documents/chapterI/feedback').get();
    expect(saved.docs, hasLength(1));
    expect(saved.docs.first.data()['version'], 1,
        reason: 'the chapter is at currentVersion 1');
    expect(saved.docs.first.data()['reviewerUid'], 'a1');
    expect(saved.docs.first.data()['body'], 'Please expand section 1.2.');
  });

  testWidgets('empty feedback is refused without writing', (tester) async {
    _useTallSurface(tester);
    final db = await seed();
    await tester.pumpWidget(_wrap(db, uid: 'a1'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('postFeedback')));
    await tester.pumpAndSettle();

    expect(find.textContaining('Write something first'), findsOneWidget);
    expect(
        (await db
                .collection('theses/t1/documents/chapterI/feedback')
                .get())
            .docs,
        isEmpty);
  });

  testWidgets('the adviser does NOT see an upload control', (tester) async {
    // Gated the same way the review section is gated on `isAdviser`: the
    // upload write is only ever valid from the thesis's leader, so a
    // control the adviser could tap and have denied is worse than none.
    _useTallSurface(tester);
    final db = await seed();
    await tester.pumpWidget(_wrap(db, uid: 'a1'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('uploadVersion')), findsNothing);
  });

  testWidgets('marking approved locks the upload control for the leader',
      (tester) async {
    // The adviser has no upload control at all (see the test above), so
    // this now signs in as the leader -- the one actor who ever sees the
    // button -- to keep testing the behaviour it guards: an approved
    // chapter is locked to the student, and only the adviser can reopen it.
    _useTallSurface(tester);
    final db = await seed();
    await tester.pumpWidget(_wrap(db, uid: 'a1'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('markApproved')));
    await tester.pumpAndSettle();

    await tester.pumpWidget(_wrap(db, uid: 'l1'));
    await tester.pumpAndSettle();

    final uploadButton =
        tester.widget<FilledButton>(find.byKey(const Key('uploadVersion')));
    expect(uploadButton.onPressed, isNull);
    expect(find.textContaining('Only your adviser can reopen it'),
        findsOneWidget);
  });
}
