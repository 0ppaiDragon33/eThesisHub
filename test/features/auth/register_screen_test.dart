import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ethesishub/data/repositories/user_repository.dart';
import 'package:ethesishub/features/auth/register_screen.dart';
import 'package:ethesishub/providers/auth_providers.dart';

Widget wrap(Widget child, {required FakeFirebaseFirestore db}) {
  return ProviderScope(
    overrides: [
      firestoreProvider.overrideWithValue(db),
      firebaseAuthProvider.overrideWithValue(MockFirebaseAuth()),
    ],
    child: MaterialApp(home: child),
  );
}

void main() {
  testWidgets('has no role selector anywhere on the form', (tester) async {
    // Self-registration must never offer a way to choose a role, because role
    // is assigned server-side and elevation happens only through invites.
    // This test guards against adding any control that could bypass that path.
    await tester.pumpWidget(wrap(const RegisterScreen(),
        db: FakeFirebaseFirestore()));

    // fullName, email, program, password, confirm password
    expect(find.byType(TextField), findsNWidgets(5));

    // No role-selection widgets of any kind
    expect(find.byType(DropdownButton), findsNothing);
    expect(find.byType(DropdownButtonFormField), findsNothing);
    expect(find.byType(RadioListTile), findsNothing);
    expect(find.byType(Radio), findsNothing);
    expect(find.byType(SegmentedButton), findsNothing);
    expect(find.byType(Checkbox), findsNothing);
    expect(find.byType(Switch), findsNothing);

    // No role-related text
    expect(find.textContaining('Role'), findsNothing);
    expect(find.textContaining('Faculty'), findsNothing);
  });

  testWidgets('rejects a non-institutional email', (tester) async {
    await tester.pumpWidget(wrap(const RegisterScreen(),
        db: FakeFirebaseFirestore()));

    await tester.enterText(find.byKey(const Key('fullName')), 'Someone');
    await tester.enterText(find.byKey(const Key('email')), 'someone@gmail.com');
    await tester.enterText(find.byKey(const Key('password')), 'Str0ngPass!');
    await tester.enterText(
        find.byKey(const Key('confirmPassword')), 'Str0ngPass!');
    // The form grew past the default 800x600 surface when the confirm field
    // and strength meter arrived, so the button needs scrolling to before a
    // tap will land on it.
    await tester.ensureVisible(find.byKey(const Key('submit')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('submit')));
    await tester.pumpAndSettle();

    expect(find.textContaining('isufst.edu.ph'), findsOneWidget);
  });

  testWidgets('creates a student profile on success', (tester) async {
    final db = FakeFirebaseFirestore();
    await tester.pumpWidget(wrap(const RegisterScreen(), db: db));

    await tester.enterText(find.byKey(const Key('fullName')), 'Karl Vargas');
    await tester.enterText(
        find.byKey(const Key('email')), 'kjvargas@isufst.edu.ph');
    await tester.enterText(find.byKey(const Key('password')), 'Str0ngPass!');
    await tester.enterText(
        find.byKey(const Key('confirmPassword')), 'Str0ngPass!');
    // The form grew past the default 800x600 surface when the confirm field
    // and strength meter arrived, so the button needs scrolling to before a
    // tap will land on it.
    await tester.ensureVisible(find.byKey(const Key('submit')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('submit')));
    await tester.pumpAndSettle();

    final users = await db.collection('users').get();
    expect(users.docs, hasLength(1));
    expect(users.docs.first.data()['role'], 'student');
  });

  testWidgets('returns error when profile write fails', (tester) async {
    final failingRepository = _FailingUserRepository();
    final db = FakeFirebaseFirestore();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          firestoreProvider.overrideWithValue(db),
          firebaseAuthProvider.overrideWithValue(MockFirebaseAuth()),
          userRepositoryProvider.overrideWithValue(failingRepository),
        ],
        child: const MaterialApp(home: RegisterScreen()),
      ),
    );

    await tester.enterText(find.byKey(const Key('fullName')), 'Karl Vargas');
    await tester.enterText(
        find.byKey(const Key('email')), 'kjvargas@isufst.edu.ph');
    await tester.enterText(find.byKey(const Key('password')), 'Str0ngPass!');
    await tester.enterText(
        find.byKey(const Key('confirmPassword')), 'Str0ngPass!');
    // The form grew past the default 800x600 surface when the confirm field
    // and strength meter arrived, so the button needs scrolling to before a
    // tap will land on it.
    await tester.ensureVisible(find.byKey(const Key('submit')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('submit')));
    await tester.pumpAndSettle();

    // Verify error message appears and submit button is re-enabled
    expect(find.textContaining('Could not complete registration'), findsOneWidget);
    expect(
      tester.widget<FilledButton>(find.byKey(const Key('submit'))).onPressed,
      isNotNull,
    );
  });

  testWidgets('a mismatched confirmation never reaches Firebase',
      (tester) async {
    tester.view.physicalSize = const Size(1000, 1800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final db = FakeFirebaseFirestore();
    await tester.pumpWidget(wrap(const RegisterScreen(), db: db));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('fullName')), 'Dr. Armada');
    await tester.enterText(
        find.byKey(const Key('email')), 'armada@isufst.edu.ph');
    await tester.enterText(
        find.byKey(const Key('password')), 'a decent long passphrase');
    await tester.enterText(
        find.byKey(const Key('confirmPassword')), 'a different passphrase');
    await tester.tap(find.byKey(const Key('submit')));
    await tester.pumpAndSettle();

    expect(find.text('The two passwords do not match.'), findsOneWidget);
    // The account must not have been created: the profile write is the only
    // observable side effect here, so its absence is the proof.
    expect((await db.collection('users').get()).docs, isEmpty);
  });

  testWidgets('a well-known password is refused with a usable reason',
      (tester) async {
    tester.view.physicalSize = const Size(1000, 1800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final db = FakeFirebaseFirestore();
    await tester.pumpWidget(wrap(const RegisterScreen(), db: db));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('fullName')), 'Dr. Armada');
    await tester.enterText(
        find.byKey(const Key('email')), 'armada@isufst.edu.ph');
    await tester.enterText(find.byKey(const Key('password')), 'password123');
    await tester.enterText(
        find.byKey(const Key('confirmPassword')), 'password123');
    await tester.tap(find.byKey(const Key('submit')));
    await tester.pumpAndSettle();

    // It is long enough to pass the length floor, so only the well-known
    // check can be refusing it — and the message must say what to do, not
    // recite a rule.
    expect(find.textContaining('too easy to guess'), findsOneWidget);
    expect((await db.collection('users').get()).docs, isEmpty);
  });

  testWidgets('the strength meter appears as you type and rates a passphrase '
      'above a short complex password', (tester) async {
    tester.view.physicalSize = const Size(1000, 1800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
        wrap(const RegisterScreen(), db: FakeFirebaseFirestore()));
    await tester.pumpAndSettle();

    // Nothing before anything is typed — the form should not open with a red
    // bar already showing.
    expect(find.byKey(const Key('passwordStrength')), findsNothing);

    await tester.enterText(find.byKey(const Key('password')), 'Xy7!aB2#');
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('passwordStrength')), findsOneWidget);
    expect(find.text('Fair'), findsOneWidget);

    await tester.enterText(
        find.byKey(const Key('password')), 'four word pass phrase');
    await tester.pumpAndSettle();
    expect(find.text('Strong'), findsOneWidget);
  });
}

/// Fake UserRepository that throws when createStudentProfile is called.
class _FailingUserRepository extends UserRepository {
  _FailingUserRepository()
      : super(FakeFirebaseFirestore()); // provide a dummy db

  @override
  Future<void> createStudentProfile({
    required String uid,
    required String fullName,
    required String email,
    String? college,
    String? program,
  }) async {
    throw Exception('Simulated profile write failure');
  }
}
