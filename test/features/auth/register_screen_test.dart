import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
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
    await tester.pumpWidget(wrap(const RegisterScreen(),
        db: FakeFirebaseFirestore()));

    expect(find.byType(DropdownButtonFormField<String>), findsNothing);
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
}
