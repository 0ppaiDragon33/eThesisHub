import 'dart:async';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ethesishub/data/models/thesis.dart';
import 'package:ethesishub/features/dashboard/stage_donut.dart';
import 'package:ethesishub/providers/auth_providers.dart';
import 'package:ethesishub/providers/thesis_providers.dart';

Map<String, dynamic> thesisDoc(String title, String status) => {
      'leaderUid': 'l1',
      'adviserUid': 'a1',
      'panelistUids': <String>[],
      'memberNames': <String>[],
      'workingTitle': title,
      'college': 'CICT',
      'program': 'BSIT',
      'semester': 'First',
      'academicYear': '2026-2027',
      'status': status,
    };

Widget wrap(Widget child, {List<Override> overrides = const []}) {
  return ProviderScope(
    overrides: overrides,
    child: MaterialApp(home: Scaffold(body: child)),
  );
}

List<Override> _dbOverrides(FakeFirebaseFirestore db) => [
      firestoreProvider.overrideWithValue(db),
      firebaseAuthProvider.overrideWithValue(MockFirebaseAuth(
        signedIn: true,
        mockUser: MockUser(
          uid: 'coord',
          email: 'coord@isufst.edu.ph',
          isEmailVerified: true,
        ),
      )),
    ];

void main() {
  testWidgets('the legend groups theses by stage with counts', (tester) async {
    final db = FakeFirebaseFirestore();
    // Seeded AGAINST the order the legend renders: fake_cloud_firestore
    // returns insertion order, so seeding in stage order would let a
    // missing sort pass.
    await db.collection('theses').doc('t1').set(thesisDoc('E', 'titleApproved'));
    await db.collection('theses').doc('t2').set(thesisDoc('A', 'draft'));
    await db.collection('theses').doc('t3').set(thesisDoc('C', 'titleApproved'));
    await db.collection('theses').doc('t4').set(thesisDoc('B', 'nominationPendingDean'));

    await tester.pumpWidget(wrap(
      const StageDonut(),
      overrides: _dbOverrides(db),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Chapters'), findsOneWidget);
    expect(find.text('2'), findsOneWidget); // two at titleApproved
  });

  testWidgets('the legend alone renders if the chart is given no space',
      (tester) async {
    // The legend carries the numbers. If fl_chart ever fails to lay out,
    // the panel must still be readable rather than blank.
    final db = FakeFirebaseFirestore();
    await db.collection('theses').doc('t1').set(thesisDoc('A', 'draft'));
    await db.collection('theses').doc('t2').set(thesisDoc('B', 'titleApproved'));

    await tester.pumpWidget(wrap(
      Center(
        child: SizedBox(
          width: 200,
          child: const StageDonut(),
        ),
      ),
      overrides: _dbOverrides(db),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Draft'), findsOneWidget);
    expect(find.text('Chapters'), findsOneWidget);
    expect(find.text('1'), findsNWidgets(2));
  });

  testWidgets('shows an empty state rather than an empty donut',
      (tester) async {
    // A zero-total donut renders as nothing, which reads as a broken panel.
    final db = FakeFirebaseFirestore();

    await tester.pumpWidget(wrap(
      const StageDonut(),
      overrides: _dbOverrides(db),
    ));
    await tester.pumpAndSettle();

    expect(find.text('No theses yet'), findsOneWidget);
    expect(find.byType(PieChart), findsNothing);
  });

  testWidgets('a loading donut is not an empty donut', (tester) async {
    // Single pump against a never-emitting controller.
    final controller = StreamController<List<Thesis>>();
    addTearDown(controller.close);

    await tester.pumpWidget(wrap(
      const StageDonut(),
      overrides: [
        allThesesProvider.overrideWith((ref) => controller.stream),
      ],
    ));
    await tester.pump();

    expect(find.text('No theses yet'), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });
}
