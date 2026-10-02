import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ethesishub/data/models/change_request.dart';
import 'package:ethesishub/features/dashboard/change_request_queue.dart';
import 'package:ethesishub/features/forms/change_request_form.dart';
import 'package:ethesishub/features/forms/editable/editor_services.dart';
import 'package:ethesishub/features/forms/form_viewer.dart';
import 'package:ethesishub/features/nomination/change_request_inbox.dart';
import 'package:ethesishub/features/nomination/nomination_inbox_screen.dart';
import 'package:ethesishub/providers/auth_providers.dart';

import 'pdf_text.dart';

/// What the viewer was asked to show, and what the reader downloaded.
class _Capture {
  Future<Uint8List> Function()? build;
  String? sharedName;
}

List<Override> _overrides(
        FakeFirebaseFirestore db, String uid, _Capture capture) =>
    [
      firestoreProvider.overrideWithValue(db),
      firebaseAuthProvider.overrideWithValue(MockFirebaseAuth(
        signedIn: true,
        mockUser: MockUser(
            uid: uid, email: '$uid@isufst.edu.ph', isEmailVerified: true),
      )),
      // Rasterising a PDF needs the platform; the stand-in keeps the build
      // function so the test can build the very PDF the reader would see.
      formPreviewBuilderProvider.overrideWithValue((build) {
        capture.build = build;
        return const Text('form pages', key: Key('stubPreview'));
      }),
      pdfSharerProvider.overrideWithValue((bytes, filename) async {
        capture.sharedName = filename;
      }),
    ];

Future<void> _pump(WidgetTester tester, FakeFirebaseFirestore db, String uid,
    _Capture capture, Widget body) async {
  tester.view.physicalSize = const Size(1200, 2000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(ProviderScope(
    overrides: _overrides(db, uid, capture),
    child: MaterialApp(
      home: Scaffold(body: SingleChildScrollView(child: body)),
    ),
  ));
  await tester.pumpAndSettle();
}

Map<String, dynamic> _signoffs(List<String> roles) => {
      for (final r in roles)
        r: {'status': 'pending', 'respondedAt': null, 'reason': null},
    };

Future<void> _seedTitleRequest(FakeFirebaseFirestore db,
    {required String stage, required List<String> awaiting}) async {
  await db.doc('theses/t1').set({
    'leaderUid': 'l1',
    'adviserUid': 'a1',
    'status': 'titleApproved',
    'panelistUids': <String>[],
    'memberNames': <String>[],
    'workingTitle': 'eThesisHub',
    'college': 'CICT',
    'program': 'BSIT',
    'semester': 'First',
    'academicYear': '2026-2027',
  });
  await db.doc('theses/t1/changeRequests/title').set({
    'type': 'title',
    'stage': stage,
    'reasons': 'The scope narrowed.',
    'leaderUid': 'l1',
    'newTitle': 'Teachers Instructional Practices',
    'oldTitle': 'eThesisHub',
    'signoffs': _signoffs(['adviser', 'coordinator', 'dean']),
    'awaitingUids': awaiting,
  });
}

void main() {
  testWidgets('a nominee opens Form 1 from the request, in the app',
      (tester) async {
    final db = FakeFirebaseFirestore();
    await db.doc('theses/t1').set({
      'leaderUid': 'l1',
      'leaderName': 'Karlo June Bagsain',
      'status': 'nominationPendingConforme',
      'panelistUids': <String>[],
      'adviserUid': null,
      'memberNames': <String>[],
      'workingTitle': 'eThesisHub',
      'college': 'CICT',
      'program': 'BSIT',
      'semester': 'First',
      'academicYear': '2026-2027',
    });
    await db.doc('theses/t1/nominations/fac-1').set({
      'nomineeUid': 'fac-1',
      'nomineeName': 'Dr. Armada',
      'position': 'adviser',
      'exOfficio': false,
      'conformeStatus': 'pending',
      'respondedAt': null,
      'declineReason': null,
    });
    final capture = _Capture();
    await _pump(tester, db, 'fac-1', capture, const NominationInboxScreen());

    await tester.tap(find.byKey(const Key('viewForm1-t1')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('formViewer')), findsOneWidget);
    expect(find.byKey(const Key('stubPreview')), findsOneWidget);

    // The form the nominee reads names the group's leader (which a nominee
    // can only get from the thesis's leaderName) and the nominee. Form 1
    // prints the signatory names in capitals.
    final text = extractPdfText((await tester.runAsync(capture.build!))!);
    expect(text, contains('KARLO JUNE BAGSAIN'));
    expect(text, contains('Dr. Armada'));

    // Downloading is the reader's choice, from the viewer.
    expect(capture.sharedName, isNull);
    await tester.tap(find.byKey(const Key('downloadForm')));
    await tester.pump();
    // The PDF was built on the real event loop (runAsync above), so the
    // download's await on it resumes there too, not on the test's fake
    // clock.
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)));
    await tester.pumpAndSettle();
    expect(capture.sharedName, 'Form1-t1.pdf');

    await tester.tap(find.byKey(const Key('closeFormViewer')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('formViewer')), findsNothing);
  });

  testWidgets('the adviser opens Form 4b from a change-of-title request',
      (tester) async {
    final db = FakeFirebaseFirestore();
    await _seedTitleRequest(db, stage: 'pendingAdviser', awaiting: ['a1']);
    final capture = _Capture();
    await _pump(tester, db, 'a1', capture, const ChangeRequestInbox());

    await tester
        .tap(find.byKey(const Key('viewChangeRequestForm-t1-adviser')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('formViewer')), findsOneWidget);
    expect(find.text('Form 4b · Change of Undergraduate Thesis Title'),
        findsOneWidget);

    final text = extractPdfText((await tester.runAsync(capture.build!))!);
    expect(text, contains('Teachers Instructional Practices'));
    expect(text, contains('eThesisHub'));
  });

  testWidgets('the Coordinator opens Form 4b from the queue', (tester) async {
    final db = FakeFirebaseFirestore();
    await db.doc('users/c1').set({
      'fullName': 'Coordinator One',
      'email': 'c1@isufst.edu.ph',
      'role': 'coordinator',
      'active': true,
    });
    await _seedTitleRequest(db,
        stage: 'pendingCoordinator', awaiting: <String>[]);
    final capture = _Capture();
    await _pump(tester, db, 'c1', capture,
        const ChangeRequestQueue(asDean: false));

    await tester.tap(find.byKey(const Key('viewChangeRequestForm-t1-title')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('formViewer')), findsOneWidget);
  });

  test('Form 4a/4b builds without the thesis, for a signer not yet on it',
      () async {
    // A proposed new adviser may not read the thesis; the form needs only
    // the request.
    final request = ChangeRequest.fromMap('adviser', {
      'type': 'adviser',
      'stage': 'pendingAdvisers',
      'reasons': 'The adviser moved campus.',
      'leaderUid': 'l1',
      'newAdviserUid': 'a2',
      'newAdviserName': 'Dr. New',
      'formerAdviserUid': 'a1',
      'formerAdviserName': 'Dr. Old',
      'signoffs': _signoffs(['newAdviser', 'formerAdviser']),
    });
    final text = extractPdfText(await buildChangeRequestPdf(request));
    expect(text, contains('Dr. New'));
    expect(text, contains('Dr. Old'));
  });

  group('the attached Form 1 copy', () {
    Future<void> seedAttachment(FakeFirebaseFirestore db) =>
        db.doc('theses/t1/attachments/form1').set({
          'formId': 'form1',
          'copyName': 'Group 3 – Santos',
          'overrides': {'salutation': 'Respected Sir/Madam:'},
          'attachedBy': 'l1',
          'attachedAt': Timestamp.fromDate(DateTime(2026, 9, 20)),
        });

    testWidgets('shows nothing when none was attached', (tester) async {
      final db = FakeFirebaseFirestore();
      await _pump(tester, db, 'a1', _Capture(),
          const ViewForm1CopyButton(thesisId: 't1'));
      expect(find.text('View attached copy'), findsNothing);
    });

    testWidgets('opens the copy with the text the leader edited',
        (tester) async {
      final db = FakeFirebaseFirestore();
      await seedAttachment(db);
      final capture = _Capture();
      await _pump(tester, db, 'a1', capture,
          const ViewForm1CopyButton(thesisId: 't1'));

      await tester.tap(find.text('View attached copy'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('formViewer')), findsOneWidget);
      expect(find.text('Group 3 – Santos'), findsWidgets);

      final text = extractPdfText(await capture.build!());
      expect(text, contains('Respected Sir/Madam:'));
    });
  });
}
