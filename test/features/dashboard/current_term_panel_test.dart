import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ethesishub/features/dashboard/current_term_panel.dart';
import 'package:ethesishub/providers/auth_providers.dart';

Future<void> pump(WidgetTester tester, FakeFirebaseFirestore db) async {
  await tester.pumpWidget(ProviderScope(
    overrides: [
      firestoreProvider.overrideWithValue(db),
      firebaseAuthProvider.overrideWithValue(MockFirebaseAuth(
        signedIn: true,
        mockUser: MockUser(
            uid: 'c1', email: 'c1@isufst.edu.ph', isEmailVerified: true),
      )),
    ],
    child: const MaterialApp(home: Scaffold(body: CurrentTermPanel())),
  ));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('not set yet says so and offers Set term', (tester) async {
    await pump(tester, FakeFirebaseFirestore());
    expect(find.textContaining('Not set yet'), findsOneWidget);
    expect(find.text('Set term'), findsOneWidget);
  });

  testWidgets('shows the current term', (tester) async {
    final db = FakeFirebaseFirestore();
    await db.doc('settings/academicTerm').set({
      'semester': 'Second',
      'academicYear': '2026-2027',
      'updatedBy': 'c1',
      'updatedAt': Timestamp.now(),
    });
    await pump(tester, db);
    expect(find.text('Second semester, AY 2026-2027'), findsOneWidget);
    expect(find.text('Change'), findsOneWidget);
  });

  testWidgets('Change opens on the next semester and saves it', (tester) async {
    final db = FakeFirebaseFirestore();
    await db.doc('settings/academicTerm').set({
      'semester': 'Second',
      'academicYear': '2026-2027',
      'updatedBy': 'c1',
      'updatedAt': Timestamp.now(),
    });
    await pump(tester, db);

    await tester.tap(find.byKey(const Key('setCurrentTerm')));
    await tester.pumpAndSettle();
    // Second sem 2026–27 is followed by First sem 2027–28.
    expect(find.text('First semester'), findsOneWidget);
    expect(find.text('2027-2028'), findsOneWidget);

    await tester.tap(find.byKey(const Key('saveTerm')));
    await tester.pumpAndSettle();

    final saved = (await db.doc('settings/academicTerm').get()).data()!;
    expect(saved['semester'], 'First');
    expect(saved['academicYear'], '2027-2028');
    expect(saved['updatedBy'], 'c1');
    expect(find.text('First semester, AY 2027-2028'), findsOneWidget);
  });
}
