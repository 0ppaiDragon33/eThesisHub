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

    // Exactly four TextField widgets: fullName, email, program, password
    expect(find.byType(TextField), findsNWidgets(4));

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
    await tester.tap(find.byKey(const Key('submit')));
    await tester.pumpAndSettle();

    // Verify error message appears and submit button is re-enabled
    expect(find.textContaining('Could not complete registration'), findsOneWidget);
    expect(
      tester.widget<FilledButton>(find.byKey(const Key('submit'))).onPressed,
      isNotNull,
    );
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
