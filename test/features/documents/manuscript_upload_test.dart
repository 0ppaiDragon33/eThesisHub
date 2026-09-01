import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ethesishub/data/models/thesis.dart';
import 'package:ethesishub/features/documents/manuscript_upload.dart';
import 'package:ethesishub/providers/auth_providers.dart';
import 'package:ethesishub/providers/defence_providers.dart';
import 'package:ethesishub/providers/thesis_providers.dart';

/// A thesis `t1` led by `l1`, with a completed FINAL defence `d1`.
///
/// [verdict] is the only signal that the defence passed — the thesis
/// status stays `titleApproved` throughout, because nothing in M2–M4 ever
/// advances it. Pass `null` for a defence that finished without a verdict
/// recorded yet.
Future<FakeFirebaseFirestore> seed({
  String? verdict = 'pass',
  bool withManuscript = false,
  bool alreadyArchived = false,
  String status = 'titleApproved',
}) async {
  final db = FakeFirebaseFirestore();
  await db.collection('theses').doc('t1').set({
    'leaderUid': 'l1',
    'adviserUid': 'a1',
    'panelistUids': <String>['p1', 'p2'],
    'memberNames': <String>['Santos, J.'],
    'workingTitle': 'Working',
    'college': 'CICT',
    'program': 'BSIT',
    'semester': 'First',
    'academicYear': '2026-2027',
    'status': status,
    'createdAt': Timestamp.fromDate(DateTime(2026, 8, 1)),
    if (withManuscript) ...{
      'manuscriptPath': 'theses/t1/manuscript/abc.pdf',
      'manuscriptUrl': 'https://example.test/abc.pdf',
      'manuscriptAbstract': 'Fish were counted.',
      'manuscriptUploadedAt':
          Timestamp.fromDate(DateTime(2026, 9, 25)),
    },
  });
  await db.collection('defenses').doc('d1').set({
    'thesisId': 't1',
    'type': 'final',
    'scheduledAt': Timestamp.fromDate(DateTime(2026, 9, 23, 9)),
    'venue': 'AVR',
    'panelUids': <String>['p1', 'p2'],
    'adviserUid': 'a1',
    'leaderUid': 'l1',
    'status': 'completed',
    'createdBy': 'c1',
    'evaluationsReleasedAt':
        Timestamp.fromDate(DateTime(2026, 9, 23, 14)),
    if (verdict != null) ...{
      'panelVerdict': verdict,
      'verdictRecordedBy': 'a1',
      'verdictRecordedAt':
          Timestamp.fromDate(DateTime(2026, 9, 23, 15)),
    },
  });
  if (alreadyArchived) {
    await db.collection('archive').doc('t1').set({
      'title': 'A Study of Coastal Fisheries',
      'memberNames': <String>['Santos, J.'],
      'abstract': 'Fish were counted.',
      'college': 'CICT',
      'program': 'BSIT',
      'academicYear': '2026-2027',
      'adviserName': 'Dr. Zamora',
      'panelNames': <String>['Dr. Reyes'],
      'manuscriptUrl': 'https://example.test/abc.pdf',
      'manuscriptPath': 'theses/t1/manuscript/abc.pdf',
      'finalDefenceId': 'd1',
      'uploadedBy': 'l1',
      'archivedBy': 'c1',
      'archivedAt': Timestamp.fromDate(DateTime(2026, 9, 30)),
    });
  }
  return db;
}

/// [myDefencesProvider] resolves which query to run off the signed-in
/// user's OWN role -- a student reaches their defences through
/// `watchForLeader`, everyone else through the adviser/panel fan-in (see
/// `defences_list_test.dart`'s identical `_seedUser`). `seed()` above is
/// shared with Task 10 and deliberately carries no `users` collection, so
/// this suite's own wrapper supplies the leader's profile.
Widget app(FakeFirebaseFirestore db, {List<Override> overrides = const []}) {
  // Fire-and-forget: fake_cloud_firestore's write settles on a microtask,
  // well before `pumpAndSettle` finishes resolving the provider chain
  // below, and every test here calls it before making any assertion.
  db.collection('users').doc('l1').set({
    'fullName': 'Leader One',
    'email': 'l1@isufst.edu.ph',
    'role': 'student',
    'active': true,
  });
  return ProviderScope(
    overrides: [
      firestoreProvider.overrideWithValue(db),
      firebaseAuthProvider.overrideWithValue(
        MockFirebaseAuth(
          signedIn: true,
          mockUser: MockUser(
              uid: 'l1', email: 'l1@isufst.edu.ph', isEmailVerified: true),
        ),
      ),
      ...overrides,
    ],
    child: const MaterialApp(
      home: Scaffold(body: _ThesisLoader()),
    ),
  );
}

/// [ManuscriptUpload] takes a resolved [Thesis], not a thesis id, so the
/// wrapper reads it off [myThesisProvider] itself -- the same provider
/// `thesis_status_screen.dart` reads before ever constructing the widget --
/// rather than reconstructing one from the literal seeded above, which
/// would silently drift from whatever `seed()` actually wrote (in
/// particular `withManuscript`).
class _ThesisLoader extends ConsumerWidget {
  const _ThesisLoader();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final thesis = ref.watch(myThesisProvider).valueOrNull;
    if (thesis == null) return const SizedBox.shrink();
    return ManuscriptUpload(thesis: thesis);
  }
}

/// A tall surface: matches the repo's own idiom, see
/// `defence_grades_screen_test.dart`.
void useTallSurface(WidgetTester tester) {
  tester.view.physicalSize = const Size(1000, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

void main() {
  testWidgets('hidden until the final defence passes', (tester) async {
    useTallSurface(tester);
    // A completed final defence with NO verdict recorded.
    await tester.pumpWidget(app(await seed(verdict: null)));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('manuscriptUpload')), findsNothing);
  });

  testWidgets('hidden when the panel failed the thesis', (tester) async {
    useTallSurface(tester);
    await tester.pumpWidget(app(await seed(verdict: 'fail')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('manuscriptUpload')), findsNothing);
  });

  testWidgets('offered once the panel passed the thesis', (tester) async {
    useTallSurface(tester);
    await tester.pumpWidget(app(await seed(verdict: 'pass')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('manuscriptUpload')), findsOneWidget);
  });

  testWidgets('submit is disabled until both the file and abstract exist',
      (tester) async {
    useTallSurface(tester);
    await tester.pumpWidget(app(await seed(verdict: 'pass')));
    await tester.pumpAndSettle();

    expect(
      tester.widget<FilledButton>(
          find.byKey(const Key('submitManuscript'))).onPressed,
      isNull,
    );
  });

  testWidgets('an uploaded manuscript shows as awaiting the coordinator',
      (tester) async {
    useTallSurface(tester);
    await tester.pumpWidget(
        app(await seed(verdict: 'pass', withManuscript: true)));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('manuscriptSubmitted')), findsOneWidget);
  });

  // "Awaiting the coordinator" is a lie once the coordinator has acted --
  // and it used to persist forever, on the same screen that was already
  // showing this group an Archived chip.
  testWidgets('a published thesis says so instead of awaiting the '
      'coordinator', (tester) async {
    useTallSurface(tester);
    await tester.pumpWidget(app(await seed(
        verdict: 'pass', withManuscript: true, status: 'archived',
        alreadyArchived: true)));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('manuscriptPublished')), findsOneWidget);
    expect(find.byKey(const Key('manuscriptSubmitted')), findsNothing);
    expect(find.byKey(const Key('replaceManuscript')), findsNothing);
  });

  // A failed read is NOT "your defence has not passed". Before this branch
  // existed, `valueOrNull ?? const []` rendered a permission-denied as
  // SizedBox.shrink(): an eligible leader saw no form, no error, no
  // explanation -- exactly what a group whose defence has not passed sees.
  testWidgets('a failed defence read surfaces, and is not silence',
      (tester) async {
    useTallSurface(tester);
    await tester.pumpWidget(app(
      await seed(verdict: 'pass'),
      overrides: [
        myDefencesProvider.overrideWith((ref) => Stream.error(
              FirebaseException(
                plugin: 'cloud_firestore',
                code: 'permission-denied',
              ),
            )),
      ],
    ));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('manuscriptDefenceError')), findsOneWidget);
    // The Firestore code itself, because there are no server-side logs.
    expect(find.byKey(const Key('errorCode')), findsOneWidget);
    expect(find.text('[permission-denied]'), findsOneWidget);
    // ...and NOT the "not eligible" silence this used to render as.
    expect(find.byKey(const Key('manuscriptUpload')), findsNothing);
  });
}
