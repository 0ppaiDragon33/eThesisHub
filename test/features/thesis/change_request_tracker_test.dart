import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:ethesishub/core/design/panel.dart';
import 'package:ethesishub/data/models/thesis.dart';
import 'package:ethesishub/data/models/thesis_status.dart';
import 'package:ethesishub/features/forms/editable/editor_services.dart';
import 'package:ethesishub/features/thesis/change_request_tracker.dart';
import 'package:ethesishub/providers/auth_providers.dart';

Map<String, dynamic> _pendingSignoff() => {
  'status': 'pending',
  'respondedAt': null,
  'reason': null,
};

Map<String, dynamic> _acceptedSignoff() => {
  'status': 'accepted',
  'respondedAt': Timestamp.now(),
  'reason': null,
};

Map<String, dynamic> _declinedSignoff(String reason) => {
  'status': 'declined',
  'respondedAt': Timestamp.now(),
  'reason': reason,
};

final _thesis = Thesis(
  id: 't1',
  leaderUid: 'l1',
  memberNames: const ['Leader One'],
  workingTitle: 'The Working Title',
  college: 'CICS',
  program: 'BSCS',
  semester: '1st',
  academicYear: '2026-2027',
  status: ThesisStatus.titleApproved,
  panelistUids: const [],
  createdAt: DateTime(2026, 1, 1),
);

Widget _wrap(
  FakeFirebaseFirestore db, {
  required String uid,
  PdfSharer? pdfSharer,
}) => ProviderScope(
  overrides: [
    firestoreProvider.overrideWithValue(db),
    firebaseAuthProvider.overrideWithValue(
      MockFirebaseAuth(
        signedIn: true,
        mockUser: MockUser(
          uid: uid,
          email: '$uid@isufst.edu.ph',
          isEmailVerified: true,
        ),
      ),
    ),
    if (pdfSharer != null) pdfSharerProvider.overrideWithValue(pdfSharer),
  ],
  child: MaterialApp.router(
    routerConfig: GoRouter(
      initialLocation: '/tracker',
      routes: [
        GoRoute(
          path: '/tracker',
          builder: (_, _) => Scaffold(
            body: SingleChildScrollView(
              child: ChangeRequestTracker(thesisId: 't1', thesis: _thesis),
            ),
          ),
        ),
        GoRoute(
          path: '/thesis/change-adviser',
          builder: (_, _) => const Scaffold(
            body: Center(
              child: Text('adviser form', key: Key('landedOnAdviserForm')),
            ),
          ),
        ),
        GoRoute(
          path: '/thesis/change-title',
          builder: (_, _) => const Scaffold(
            body: Center(
              child: Text('title form', key: Key('landedOnTitleForm')),
            ),
          ),
        ),
      ],
    ),
  ),
);

void main() {
  testWidgets('renders nothing when there is no open or returned request', (
    tester,
  ) async {
    final db = FakeFirebaseFirestore();
    await tester.pumpWidget(_wrap(db, uid: 'l1'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('changeRequestTracker')), findsNothing);
  });

  testWidgets(
    'an approved request shows a Download form button that shares the '
    'filled PDF',
    (tester) async {
      final db = FakeFirebaseFirestore();
      await db.collection('theses/t1/changeRequests').doc('title').set({
        'type': 'title',
        'stage': 'approved',
        'reasons': 'Better fit',
        'leaderUid': 'l1',
        'newTitle': 'A New Title',
        'signoffs': {
          'adviser': _acceptedSignoff(),
          'coordinator': _acceptedSignoff(),
          'dean': _acceptedSignoff(),
        },
        'createdAt': Timestamp.now(),
        'updatedAt': Timestamp.now(),
      });

      Uint8List? sharedBytes;
      String? sharedFilename;
      await tester.pumpWidget(
        _wrap(
          db,
          uid: 'l1',
          pdfSharer: (bytes, filename) async {
            sharedBytes = bytes;
            sharedFilename = filename;
          },
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('changeRequestTracker')), findsOneWidget);
      final download = find.byKey(
        const Key('downloadChangeRequestForm-title'),
      );
      expect(download, findsOneWidget);

      await tester.ensureVisible(download);
      await tester.tap(download);
      await tester.pumpAndSettle();

      expect(sharedBytes, isNotNull);
      expect(sharedBytes, isNotEmpty);
      expect(sharedFilename, 'Form4b-t1.pdf');
    },
  );

  testWidgets(
    'an open adviser request shows its stage and each sign-off state',
    (tester) async {
      final db = FakeFirebaseFirestore();
      await db.collection('theses/t1/changeRequests').doc('adviser').set({
        'type': 'adviser',
        'stage': 'pendingAdvisers',
        'reasons': 'Scheduling conflicts',
        'leaderUid': 'l1',
        'newAdviserUid': 'a2',
        'newAdviserName': 'Dr. Adviser Two',
        'formerAdviserUid': 'a1',
        'formerAdviserName': 'Dr. Adviser One',
        'signoffs': {
          'newAdviser': _acceptedSignoff(),
          'formerAdviser': _pendingSignoff(),
          'coordinator': _pendingSignoff(),
          'dean': _pendingSignoff(),
        },
        'createdAt': Timestamp.now(),
        'updatedAt': Timestamp.now(),
      });

      await tester.pumpWidget(_wrap(db, uid: 'l1'));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('changeRequestTracker')), findsOneWidget);
      expect(find.text('Awaiting the new and former adviser'), findsOneWidget);
      expect(
        find.byKey(const Key('signoff-adviser-newAdviser')),
        findsOneWidget,
      );
      expect(
        tester
            .widget<ToneBadge>(
              find.byKey(const Key('signoff-adviser-newAdviser')),
            )
            .label,
        'Accepted',
      );
      expect(
        tester
            .widget<ToneBadge>(
              find.byKey(const Key('signoff-adviser-formerAdviser')),
            )
            .label,
        'Pending',
      );
      // Still open: no resubmit button.
      expect(find.byKey(const Key('resubmitChangeRequest')), findsNothing);
    },
  );

  testWidgets(
    'a returned title request shows the decline reason and a resubmit '
    'button that routes back to the screen prefilled',
    (tester) async {
      final db = FakeFirebaseFirestore();
      await db.collection('theses/t1/changeRequests').doc('title').set({
        'type': 'title',
        'stage': 'returned',
        'reasons': 'Better fit',
        'leaderUid': 'l1',
        'newTitle': 'A Returned Title',
        'signoffs': {
          'adviser': _declinedSignoff('Too similar to another group\'s title'),
          'coordinator': _pendingSignoff(),
          'dean': _pendingSignoff(),
        },
        'createdAt': Timestamp.now(),
        'updatedAt': Timestamp.now(),
      });

      await tester.pumpWidget(_wrap(db, uid: 'l1'));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('changeRequestTracker')), findsOneWidget);
      expect(find.text('Returned'), findsOneWidget);
      expect(
        find.textContaining('Declined: Too similar to another group\'s title'),
        findsOneWidget,
      );

      final resubmit = find.byKey(const Key('resubmitChangeRequest'));
      expect(resubmit, findsOneWidget);
      await tester.ensureVisible(resubmit);
      await tester.tap(resubmit);
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('landedOnTitleForm')), findsOneWidget);
    },
  );

  testWidgets('a returned adviser request resubmits to the adviser route', (
    tester,
  ) async {
    final db = FakeFirebaseFirestore();
    await db.collection('theses/t1/changeRequests').doc('adviser').set({
      'type': 'adviser',
      'stage': 'returned',
      'reasons': 'Scheduling conflicts',
      'leaderUid': 'l1',
      'newAdviserUid': 'a2',
      'newAdviserName': 'Dr. Adviser Two',
      'formerAdviserUid': 'a1',
      'formerAdviserName': 'Dr. Adviser One',
      'signoffs': {
        'newAdviser': _declinedSignoff('Not available'),
        'formerAdviser': _pendingSignoff(),
        'coordinator': _pendingSignoff(),
        'dean': _pendingSignoff(),
      },
      'createdAt': Timestamp.now(),
      'updatedAt': Timestamp.now(),
    });

    await tester.pumpWidget(_wrap(db, uid: 'l1'));
    await tester.pumpAndSettle();

    final resubmit = find.byKey(const Key('resubmitChangeRequest'));
    await tester.ensureVisible(resubmit);
    await tester.tap(resubmit);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('landedOnAdviserForm')), findsOneWidget);
  });

  testWidgets('two open requests each get their own card', (tester) async {
    final db = FakeFirebaseFirestore();
    await db.collection('theses/t1/changeRequests').doc('adviser').set({
      'type': 'adviser',
      'stage': 'pendingAdvisers',
      'reasons': 'r1',
      'leaderUid': 'l1',
      'newAdviserUid': 'a2',
      'formerAdviserUid': 'a1',
      'signoffs': {
        'newAdviser': _pendingSignoff(),
        'formerAdviser': _pendingSignoff(),
        'coordinator': _pendingSignoff(),
        'dean': _pendingSignoff(),
      },
      'createdAt': Timestamp.now(),
      'updatedAt': Timestamp.now(),
    });
    await db.collection('theses/t1/changeRequests').doc('title').set({
      'type': 'title',
      'stage': 'pendingAdviser',
      'reasons': 'r2',
      'leaderUid': 'l1',
      'newTitle': 'A New Title',
      'signoffs': {
        'adviser': _pendingSignoff(),
        'coordinator': _pendingSignoff(),
        'dean': _pendingSignoff(),
      },
      'createdAt': Timestamp.now(),
      'updatedAt': Timestamp.now(),
    });

    await tester.pumpWidget(_wrap(db, uid: 'l1'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('changeRequest-adviser')), findsOneWidget);
    expect(find.byKey(const Key('changeRequest-title')), findsOneWidget);
  });
}
