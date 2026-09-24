import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:firebase_core/firebase_core.dart';

import 'package:ethesishub/data/repositories/title_defence_repository.dart';
import 'package:ethesishub/data/services/storage_service.dart';
import 'package:ethesishub/features/titles/title_defence_screen.dart';
import 'package:ethesishub/providers/auth_providers.dart';
import 'package:ethesishub/providers/service_providers.dart';
import 'package:ethesishub/providers/title_providers.dart';

/// [withPreviousRound] seeds a SUPERSEDED candidate from the round before,
/// which is the only way the screen's round filter can be tested at all.
/// Without it the fixture held one round on a `titleRound: 1` thesis, so
/// deleting the filter outright left all nine tests green.
Future<FakeFirebaseFirestore> seeded({
  String viewerRole = 'faculty',
  bool withPreviousRound = false,
}) async {
  final round = withPreviousRound ? 2 : 1;
  final db = FakeFirebaseFirestore();
  await db.collection('users').doc('viewer').set({
    'fullName': 'Dr. Viewer', 'email': 'v@isufst.edu.ph',
    'role': viewerRole, 'active': true,
  });
  await db.collection('theses').doc('t1').set({
    'leaderUid': 'l1', 'status': 'titlePendingDefence',
    'panelistUids': <String>['viewer'], 'adviserUid': 'a1',
    'memberNames': <String>[], 'workingTitle': 'T', 'college': 'CICT',
    'program': 'BSIT', 'semester': 'First', 'academicYear': '2026-2027',
    'titleRound': round,
    'presentationPath': 'theses/t1/presentation/uuid.pptx',
    'presentationUrl': 'https://example.test/presentation.pptx',
  });
  if (withPreviousRound) {
    await db.collection('theses/t1/candidateTitles').doc('old1').set({
      'titleText': 'Candidate old1',
      'justificationPath': 'theses/t1/old1/uuid.pdf',
      'justificationUrl': 'https://example.test/old1.pdf', 'round': 1,
    });
  }
  for (final id in ['ct1', 'ct2', 'ct3']) {
    await db.collection('theses/t1/candidateTitles').doc(id).set({
      'titleText': 'Candidate $id',
      'justificationPath': 'theses/t1/$id/uuid.pdf',
      'justificationUrl': 'https://example.test/$id.pdf', 'round': round,
    });
  }
  return db;
}

/// The bucket is private, so the screen opens a document by asking the
/// storage service for a signed URL from its PATH. This stands in for the
/// `document-url` round trip: a URL derived from the path, so a test can
/// assert which document was opened without a live Supabase.
class _FakeStorage implements StorageService {
  @override
  Future<String> signedUrl(String path) async => 'https://signed.test/$path';

  @override
  Future<StoredFile> upload({
    required List<int> bytes,
    required String path,
    required String contentType,
  }) async =>
      throw UnimplementedError();

  @override
  Future<void> delete(String path) async => throw UnimplementedError();
}

Widget wrap(
  FakeFirebaseFirestore db, {
  UrlOpener? openUrl,
  TitleDefenceRepository? repository,
}) =>
    ProviderScope(
      overrides: [
        firestoreProvider.overrideWithValue(db),
        if (repository != null)
          titleDefenceRepositoryProvider.overrideWithValue(repository),
        storageServiceProvider.overrideWithValue(_FakeStorage()),
        firebaseAuthProvider.overrideWithValue(MockFirebaseAuth(
          signedIn: true,
          mockUser: MockUser(
              uid: 'viewer', email: 'v@isufst.edu.ph',
              isEmailVerified: true),
        )),
      ],
      child: MaterialApp.router(
        routerConfig: GoRouter(
          initialLocation: '/defence',
          routes: [
            GoRoute(
              path: '/defence',
              // The app shell supplies the Scaffold in the real app.
              builder: (_, _) => Scaffold(
                body: TitleDefenceScreen(thesisId: 't1', openUrl: openUrl),
              ),
            ),
            GoRoute(
              path: '/faculty',
              builder: (_, _) => const Scaffold(
                body: Center(child: Text('home', key: Key('landedHome'))),
              ),
            ),
          ],
        ),
      ),
    );

void useTallSurface(WidgetTester tester) {
  tester.view.physicalSize = const Size(1200, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

void main() {
  testWidgets('shows every candidate of the current round, and only those',
      (tester) async {
    // Two rounds on the record. The previous round's candidate is history
    // the panel must not be asked to judge — and it is the only thing that
    // makes this test about the ROUND. With a single-round fixture the
    // round filter could be deleted outright and all nine tests still
    // passed; this seeds the superseded candidate and asserts its absence.
    useTallSurface(tester);
    await tester.pumpWidget(wrap(await seeded(withPreviousRound: true)));
    await tester.pumpAndSettle();

    expect(find.text('Candidate ct1'), findsOneWidget);
    expect(find.text('Candidate ct2'), findsOneWidget);
    expect(find.text('Candidate ct3'), findsOneWidget);
    expect(find.text('Candidate old1'), findsNothing,
        reason: 'round 1 was superseded by the resubmission');
    // Its comment box would be a way to remark on a withdrawn title.
    expect(find.byKey(const Key('commentBox-old1')), findsNothing);
  });

  testWidgets('the panel can open a candidate justification', (tester) async {
    // The URLs were written on submission and rendered nowhere: the panel
    // saw three title strings and could not read a single justification.
    useTallSurface(tester);
    final opened = <Uri>[];
    await tester.pumpWidget(wrap(await seeded(), openUrl: (uri) async {
      opened.add(uri);
      return true;
    }));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('openJustification-ct2')));
    await tester.pumpAndSettle();

    expect(opened.map((u) => u.toString()),
        ['https://signed.test/theses/t1/ct2/uuid.pdf'],
        reason: 'the link must open THAT candidate, not the first one');
  });

  testWidgets('the panel can open the presentation', (tester) async {
    useTallSurface(tester);
    final opened = <Uri>[];
    await tester.pumpWidget(wrap(await seeded(), openUrl: (uri) async {
      opened.add(uri);
      return true;
    }));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('openPresentation')));
    await tester.pumpAndSettle();

    expect(opened.map((u) => u.toString()),
        ['https://signed.test/theses/t1/presentation/uuid.pptx']);
  });

  testWidgets('a document that will not open says so rather than failing '
      'silently', (tester) async {
    useTallSurface(tester);
    await tester.pumpWidget(
        wrap(await seeded(), openUrl: (_) async => false));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('openJustification-ct1')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('error')), findsOneWidget);
    expect(find.textContaining('Could not open the justification'),
        findsOneWidget);
  });

  testWidgets('a panel member can post a comment on one candidate',
      (tester) async {
    useTallSurface(tester);
    final db = await seeded();
    await tester.pumpWidget(wrap(db));
    await tester.pumpAndSettle();

    await tester.enterText(
        find.byKey(const Key('commentBox-ct2')), 'Scope is too broad.');
    await tester.tap(find.byKey(const Key('postComment-ct2')));
    await tester.pumpAndSettle();

    final saved = await db.collection('theses/t1/titleComments').get();
    expect(saved.docs, hasLength(1));
    expect(saved.docs.first.data()['candidateTitleId'], 'ct2');
    expect(saved.docs.first.data()['authorUid'], 'viewer');
    expect(saved.docs.first.data()['authorRole'], isNotEmpty,
        reason: 'the role held at the time is part of the record');
  });

  testWidgets('an empty comment is refused', (tester) async {
    useTallSurface(tester);
    final db = await seeded();
    await tester.pumpWidget(wrap(db));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('postComment-ct1')));
    await tester.pumpAndSettle();

    expect((await db.collection('theses/t1/titleComments').get()).docs,
        isEmpty);
  });

  testWidgets('someone else composing is announced', (tester) async {
    useTallSurface(tester);
    final db = await seeded();
    await db.collection('theses/t1/titleComposing').doc('other').set({
      'name': 'Dr. Diamante', 'role': 'Panel Member',
      'candidateTitleId': 'ct1', 'updatedAt': DateTime.now(),
    });

    await tester.pumpWidget(wrap(db));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('composingBanner')), findsOneWidget);
    expect(find.textContaining('Dr. Diamante'), findsWidgets);
  });

  testWidgets('a stale composing indicator is not announced', (tester) async {
    // No Cloud Functions sweep these, so the reader has to expire them.
    useTallSurface(tester);
    final db = await seeded();
    await db.collection('theses/t1/titleComposing').doc('other').set({
      'name': 'Dr. Diamante', 'role': 'Panel Member',
      'candidateTitleId': 'ct1',
      'updatedAt': DateTime.now().subtract(const Duration(minutes: 5)),
    });

    await tester.pumpWidget(wrap(db));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('composingBanner')), findsNothing);
  });

  testWidgets('your own composing marker is not announced back to you',
      (tester) async {
    useTallSurface(tester);
    final db = await seeded();
    await db.collection('theses/t1/titleComposing').doc('viewer').set({
      'name': 'Dr. Viewer', 'role': 'Panel Member',
      'candidateTitleId': 'ct1', 'updatedAt': DateTime.now(),
    });

    await tester.pumpWidget(wrap(db));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('composingBanner')), findsNothing);
  });

  testWidgets('a panel member sees no decision controls', (tester) async {
    useTallSurface(tester);
    await tester.pumpWidget(wrap(await seeded()));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('approve-ct1')), findsNothing);
    expect(find.byKey(const Key('rejectSet')), findsNothing);
  });

  testWidgets('the Dean can approve one candidate', (tester) async {
    useTallSurface(tester);
    final db = await seeded(viewerRole: 'dean');
    await tester.pumpWidget(wrap(db));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('approve-ct2')));
    await tester.pumpAndSettle();

    final t = (await db.collection('theses').doc('t1').get()).data()!;
    expect(t['status'], 'titleApproved');
    expect(t['approvedTitleId'], 'ct2');
    expect(t['titleDecidedBy'], 'viewer');
  });

  testWidgets('the Dean cannot reject without a remark', (tester) async {
    useTallSurface(tester);
    final db = await seeded(viewerRole: 'dean');
    await tester.pumpWidget(wrap(db));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('rejectSet')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('confirmReject')));
    await tester.pumpAndSettle();

    final t = (await db.collection('theses').doc('t1').get()).data()!;
    expect(t['status'], 'titlePendingDefence',
        reason: 'nothing should have been recorded');
    expect(find.byKey(const Key('error')), findsOneWidget);
  });

  // The "is writing" marker is decoration, and the rules refuse it outright
  // to anyone who is not on the panel: `titleComposing` allows create only
  // for isOnPanel(), while get/list also allows the Coordinator and the
  // Dean. So a Dean or Coordinator reading this screen is shown a comment
  // box, focuses it, and the marker write is denied — once on focus and then
  // again every five seconds by the heartbeat.
  //
  // Nothing awaits those writes, so each refusal escaped as an uncaught
  // rejection: "Uncaught (in promise) [cloud_firestore/permission-denied]".
  // Presence failing costs a reader nothing and must stay silent.
  testWidgets('a refused composing marker does not surface as an error',
      (tester) async {
    final db = await seeded(viewerRole: 'dean');

    await tester.pumpWidget(
      wrap(db, repository: _RefusingComposingRepository(db)),
    );
    await tester.pumpAndSettle();

    // Focus rather than tap: the box sits below the fold, so a tap never
    // reaches it and the focus listener would never run.
    await tester.showKeyboard(find.byKey(const Key('commentBox-ct1')));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });
}

/// Stands in for a panel-only `titleComposing` rule refusing a reader who may
/// watch the screen but not write to it.
class _RefusingComposingRepository extends TitleDefenceRepository {
  _RefusingComposingRepository(super.db);

  static final _denied = FirebaseException(
    plugin: 'cloud_firestore',
    code: 'permission-denied',
    message: 'Missing or insufficient permissions.',
  );

  @override
  Future<void> markComposing({
    required String thesisId,
    required String uid,
    required String name,
    required String role,
    required String candidateTitleId,
  }) =>
      Future.error(_denied);

  @override
  Future<void> clearComposing({
    required String thesisId,
    required String uid,
  }) =>
      Future.error(_denied);
}
