import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:ethesishub/data/repositories/thesis_repository.dart';
import 'package:ethesishub/features/thesis/create_thesis_screen.dart';
import 'package:ethesishub/providers/auth_providers.dart';
import 'package:ethesishub/providers/thesis_providers.dart';

Widget wrap(FakeFirebaseFirestore db, {List<Override> extraOverrides = const []}) =>
    ProviderScope(
      overrides: [
        firestoreProvider.overrideWithValue(db),
        firebaseAuthProvider.overrideWithValue(MockFirebaseAuth(
          signedIn: true,
          mockUser: MockUser(
              uid: 'leader-1',
              email: 'l@isufst.edu.ph',
              isEmailVerified: true),
        )),
        ...extraOverrides,
      ],
      child: MaterialApp.router(
        routerConfig: GoRouter(
          initialLocation: '/thesis/create',
          routes: [
            GoRoute(
              path: '/thesis/create',
              builder: (_, _) => const CreateThesisScreen(),
            ),
            GoRoute(
              path: '/thesis',
              builder: (_, _) => const Scaffold(
                body: Center(child: Text('status screen', key: Key('landedOnStatus'))),
              ),
            ),
          ],
        ),
      ),
    );

/// Rejects every create with permission-denied, as the real security rules
/// would for an unverified email.
class PermissionDeniedThesisRepository extends ThesisRepository {
  PermissionDeniedThesisRepository(super.db);

  @override
  Future<String> createThesis({
    required String leaderUid,
    required String workingTitle,
    required List<String> memberNames,
    required String college,
    required String program,
    required String semester,
    required String academicYear,
  }) {
    throw FirebaseException(
      plugin: 'cloud_firestore',
      code: 'permission-denied',
      message: 'Missing or insufficient permissions.',
    );
  }
}

/// Rejects every create with a generic, non-permission-denied error.
class FailingThesisRepository extends ThesisRepository {
  FailingThesisRepository(super.db);

  @override
  Future<String> createThesis({
    required String leaderUid,
    required String workingTitle,
    required List<String> memberNames,
    required String college,
    required String program,
    required String semester,
    required String academicYear,
  }) {
    throw Exception('boom');
  }
}

/// Creates successfully, but only after an artificial delay — long enough
/// for a double-tap test to land its second tap before the first completes.
class SlowThesisRepository extends ThesisRepository {
  SlowThesisRepository(super.db) : _delegate = ThesisRepository(db);

  final ThesisRepository _delegate;
  int callCount = 0;

  @override
  Future<String> createThesis({
    required String leaderUid,
    required String workingTitle,
    required List<String> memberNames,
    required String college,
    required String program,
    required String semester,
    required String academicYear,
  }) async {
    callCount++;
    await Future.delayed(const Duration(milliseconds: 50));
    return _delegate.createThesis(
      leaderUid: leaderUid,
      workingTitle: workingTitle,
      memberNames: memberNames,
      college: college,
      program: program,
      semester: semester,
      academicYear: academicYear,
    );
  }
}

/// The form has more fields than fit in the default 800x600 test surface,
/// which would otherwise leave the submit button off-screen and unable to
/// receive a tap. Every test that submits needs this.
void useTallSurface(WidgetTester tester) {
  tester.view.physicalSize = const Size(1000, 1600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

void main() {
  testWidgets('fixed sets are dropdowns, not text fields', (tester) async {
    await tester.pumpWidget(wrap(FakeFirebaseFirestore()));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('college')), findsOneWidget);
    expect(find.byKey(const Key('program')), findsOneWidget);
    expect(find.byKey(const Key('semester')), findsOneWidget);
    expect(find.byKey(const Key('academicYear')), findsOneWidget);
    expect(find.byType(DropdownButtonFormField<String>), findsNWidgets(4));
  });

  testWidgets('requires a working title', (tester) async {
    useTallSurface(tester);
    await tester.pumpWidget(wrap(FakeFirebaseFirestore()));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('submit')));
    await tester.pumpAndSettle();

    // Assert on the error Text's own Key, not on text content: the label
    // 'Working title' sits on screen at all times (it's the TextField's
    // labelText), so matching on it would pass even if validation never
    // ran. The distinct error message, found by its Key, can only appear
    // if the empty-title branch in _submit actually fired.
    expect(find.byKey(const Key('error')), findsOneWidget);
    final errorText = tester.widget<Text>(find.byKey(const Key('error')));
    expect(errorText.data, contains('is required'));
  });

  testWidgets('creates a draft thesis owned by the signed-in leader',
      (tester) async {
    useTallSurface(tester);
    final db = FakeFirebaseFirestore();
    await tester.pumpWidget(wrap(db));
    await tester.pumpAndSettle();

    await tester.enterText(
        find.byKey(const Key('workingTitle')), 'eThesisHub');
    await tester.tap(find.byKey(const Key('submit')));
    await tester.pumpAndSettle();

    final docs = await db.collection('theses').get();
    expect(docs.docs, hasLength(1));
    expect(docs.docs.first.data()['leaderUid'], 'leader-1');
    expect(docs.docs.first.data()['status'], 'draft');
  });

  testWidgets('a blank working title never reaches the repository',
      (tester) async {
    useTallSurface(tester);
    // Falsifiability guard: if the empty-title short-circuit in _submit were
    // deleted, this would fail because a doc would land in the fake store
    // even though the field was left blank.
    final db = FakeFirebaseFirestore();
    await tester.pumpWidget(wrap(db));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('submit')));
    await tester.pumpAndSettle();

    final docs = await db.collection('theses').get();
    expect(docs.docs, isEmpty);
  });

  testWidgets('member names typed by the leader are stored as plain text',
      (tester) async {
    useTallSurface(tester);
    final db = FakeFirebaseFirestore();
    await tester.pumpWidget(wrap(db));
    await tester.pumpAndSettle();

    await tester.enterText(
        find.byKey(const Key('workingTitle')), 'eThesisHub');
    await tester.enterText(
        find.byKey(const Key('member0')), 'Dela Cruz, Juan');
    await tester.tap(find.byKey(const Key('addMember')));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const Key('member1')), 'Santos, Maria');
    await tester.tap(find.byKey(const Key('submit')));
    await tester.pumpAndSettle();

    final docs = await db.collection('theses').get();
    expect(docs.docs.first.data()['memberNames'],
        ['Dela Cruz, Juan', 'Santos, Maria']);
  });

  testWidgets('handles permission-denied gracefully', (tester) async {
    useTallSurface(tester);
    final db = FakeFirebaseFirestore();
    await tester.pumpWidget(wrap(
      db,
      extraOverrides: [
        thesisRepositoryProvider
            .overrideWithValue(PermissionDeniedThesisRepository(db)),
      ],
    ));
    await tester.pumpAndSettle();

    await tester.enterText(
        find.byKey(const Key('workingTitle')), 'eThesisHub');
    await tester.tap(find.byKey(const Key('submit')));
    await tester.pumpAndSettle();

    // No raw exception text; a friendly, permission-specific message
    // instead — distinct from the generic failure message so a reader can
    // tell what went wrong.
    expect(find.textContaining('permission-denied'), findsNothing);
    expect(find.textContaining('FirebaseException'), findsNothing);
    expect(find.textContaining('verified'), findsOneWidget);

    // The finally block must have cleared the busy flag.
    final submitButton =
        tester.widget<FilledButton>(find.byKey(const Key('submit')));
    expect(submitButton.onPressed, isNotNull,
        reason: 'finally must reset the busy flag so the button is usable '
            'again');

    final docs = await db.collection('theses').get();
    expect(docs.docs, isEmpty);
  });

  testWidgets('shows an error and re-enables the button on a generic failure',
      (tester) async {
    useTallSurface(tester);
    final db = FakeFirebaseFirestore();
    await tester.pumpWidget(wrap(
      db,
      extraOverrides: [
        thesisRepositoryProvider
            .overrideWithValue(FailingThesisRepository(db)),
      ],
    ));
    await tester.pumpAndSettle();

    await tester.enterText(
        find.byKey(const Key('workingTitle')), 'eThesisHub');
    await tester.tap(find.byKey(const Key('submit')));
    await tester.pumpAndSettle();

    final submitButton =
        tester.widget<FilledButton>(find.byKey(const Key('submit')));
    expect(submitButton.onPressed, isNotNull,
        reason: 'finally must reset the busy flag so the button is usable '
            'again');
  });

  testWidgets('a double tap on submit creates only one thesis',
      (tester) async {
    useTallSurface(tester);
    final db = FakeFirebaseFirestore();
    final repo = SlowThesisRepository(db);
    await tester.pumpWidget(wrap(
      db,
      extraOverrides: [thesisRepositoryProvider.overrideWithValue(repo)],
    ));
    await tester.pumpAndSettle();

    await tester.enterText(
        find.byKey(const Key('workingTitle')), 'eThesisHub');

    // Fire two taps back to back, before the first create resolves.
    await tester.tap(find.byKey(const Key('submit')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('submit')));
    await tester.pumpAndSettle(const Duration(milliseconds: 100));

    expect(repo.callCount, 1);
    final docs = await db.collection('theses').get();
    expect(docs.docs, hasLength(1));
  });

  testWidgets(
      'a successful create navigates to the thesis status screen, not an '
      'in-place message', (tester) async {
    useTallSurface(tester);
    final db = FakeFirebaseFirestore();
    await tester.pumpWidget(wrap(db));
    await tester.pumpAndSettle();

    await tester.enterText(
        find.byKey(const Key('workingTitle')), 'eThesisHub');
    await tester.tap(find.byKey(const Key('submit')));
    await tester.pumpAndSettle();

    // Falsifiability: if the navigation call were deleted, the create-thesis
    // form (and its 'submit' key) would still be on screen and this
    // wouldn't fire.
    expect(find.byKey(const Key('landedOnStatus')), findsOneWidget);
    expect(find.byKey(const Key('submit')), findsNothing);
  });
}
