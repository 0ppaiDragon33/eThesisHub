import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:ethesishub/features/forms/editable/editor_services.dart';
import 'package:ethesishub/features/forms/editable/form_copy_editor_screen.dart';
import 'package:ethesishub/providers/auth_providers.dart';

import '../pdf_text.dart';

/// What the editor asked of its preview: each render function it handed
/// over, and how many times the preview was created from scratch (and so
/// lost its zoom and place).
class Previews {
  final builds = <Object>{};
  int created = 0;
}

class _StubPreview extends StatefulWidget {
  const _StubPreview(this.previews);

  final Previews previews;

  @override
  State<_StubPreview> createState() => _StubPreviewState();
}

class _StubPreviewState extends State<_StubPreview> {
  @override
  void initState() {
    super.initState();
    widget.previews.created++;
  }

  @override
  Widget build(BuildContext context) =>
      const Text('preview stub', key: Key('previewStub'));
}

class Shared {
  Uint8List? bytes;
  String? filename;
}

Future<FakeFirebaseFirestore> seedCopy({
  Map<String, String> overrides = const {},
}) async {
  final db = FakeFirebaseFirestore();
  await db.collection('users').doc('u1').set({
    'fullName': 'Test User',
    'email': 't@isufst.edu.ph',
    'role': 'faculty',
    'active': true,
  });
  final at = Timestamp.fromDate(DateTime(2026, 9, 1));
  await db.doc('users/u1/formCopies/c1').set({
    'formId': 'form1',
    'name': 'Group 3 – Santos',
    'overrides': overrides,
    'folderId': null,
    'createdAt': at,
    'updatedAt': at,
  });
  return db;
}

/// Starts on '/forms' and pushes the editor, so leaving it is a real pop,
/// the way the top-bar arrow and the Android back both leave it.
Future<(GoRouter, Previews, Shared)> pumpEditor(
  WidgetTester tester,
  FakeFirebaseFirestore db, {
  String location = '/forms/form1/copies/c1',
  Size size = const Size(1400, 2400),
  MockFirebaseAuth? auth,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final previews = Previews();
  final shared = Shared();
  final router = GoRouter(
    initialLocation: '/forms',
    routes: [
      GoRoute(
        path: '/forms',
        builder: (_, _) =>
            const Scaffold(body: Text('forms home', key: Key('formsHome'))),
      ),
      GoRoute(
        path: '/forms/:formId/copies/:copyId',
        onExit: confirmLeaveFormEditor,
        builder: (_, s) => Scaffold(
          body: FormCopyEditorScreen(
            formId: s.pathParameters['formId']!,
            copyId: s.pathParameters['copyId']!,
          ),
        ),
      ),
    ],
  );
  addTearDown(router.dispose);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        firestoreProvider.overrideWithValue(db),
        firebaseAuthProvider.overrideWithValue(
          auth ??
              MockFirebaseAuth(
                signedIn: true,
                mockUser: MockUser(
                  uid: 'u1',
                  email: 't@isufst.edu.ph',
                  isEmailVerified: true,
                ),
              ),
        ),
        // Rasterising a PDF needs the platform; record each preview instead.
        formPreviewBuilderProvider.overrideWithValue((build) {
          previews.builds.add(build);
          return _StubPreview(previews);
        }),
        pdfSharerProvider.overrideWithValue((bytes, filename) async {
          shared
            ..bytes = bytes
            ..filename = filename;
        }),
      ],
      child: MaterialApp.router(routerConfig: router),
    ),
  );
  await tester.pumpAndSettle();
  router.push(location);
  await tester.pumpAndSettle();
  return (router, previews, shared);
}

String fieldText(WidgetTester tester, String blockId) => tester
    .widget<TextField>(find.byKey(Key('field-$blockId')))
    .controller!
    .text;

/// Fake Firestore writes and PDF font loading finish on the real event
/// loop, not the test's fake clock. With [done], polls until it holds (up
/// to 5 s); without it, gives the loop a short real-time turn.
Future<void> settleReal(WidgetTester tester, [bool Function()? done]) async {
  await tester.runAsync(() async {
    for (var i = 0; i < 50; i++) {
      if (done == null ? i >= 3 : done()) break;
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
  });
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('opens a copy with its saved edits in the fields', (
    tester,
  ) async {
    final db = await seedCopy(overrides: {'salutation': 'Dear Dean Reyes:'});
    await pumpEditor(tester, db);

    expect(fieldText(tester, 'salutation'), 'Dear Dean Reyes:');
    expect(
      fieldText(tester, 'addressee'),
      'The Dean',
      reason: 'an unedited block shows the form\'s own wording',
    );
    expect(find.text('Group 3 – Santos'), findsOneWidget);
    expect(find.text('All changes saved'), findsOneWidget);
  });

  testWidgets('Save stays off until something changes', (tester) async {
    await pumpEditor(tester, await seedCopy());
    final save = tester.widget<ButtonStyleButton>(
      find.byKey(const Key('saveCopy')),
    );
    expect(save.onPressed, isNull);
  });

  testWidgets('saving stores only the blocks that were changed', (
    tester,
  ) async {
    final db = await seedCopy();
    await pumpEditor(tester, db);

    await tester.enterText(
      find.byKey(const Key('field-salutation')),
      'Dear Dean:',
    );
    await tester.pump();
    expect(find.text('Unsaved changes'), findsOneWidget);

    await tester.tap(find.byKey(const Key('saveCopy')));
    await settleReal(tester);

    final data = (await db.doc('users/u1/formCopies/c1').get()).data()!;
    expect(data['overrides'], {'salutation': 'Dear Dean:'});
    expect(find.text('All changes saved'), findsOneWidget);
  });

  testWidgets('resetting a field puts back the form\'s wording, and saving '
      'then stores nothing for it', (tester) async {
    final db = await seedCopy(overrides: {'salutation': 'Dear Dean:'});
    await pumpEditor(tester, db);

    await tester.tap(find.byKey(const Key('resetField-salutation')));
    await tester.pump();
    expect(fieldText(tester, 'salutation'), 'Sir/Madam:');

    await tester.tap(find.byKey(const Key('saveCopy')));
    await settleReal(tester);
    final data = (await db.doc('users/u1/formCopies/c1').get()).data()!;
    expect(data['overrides'], isEmpty);
  });

  testWidgets('Reset all asks first, then puts every field back', (
    tester,
  ) async {
    await pumpEditor(
      tester,
      await seedCopy(overrides: {'salutation': 'Dear Dean:', 'closing': 'x'}),
    );

    await tester.tap(find.byKey(const Key('resetAllCopy')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('confirmResetAll')));
    await tester.pumpAndSettle();

    expect(fieldText(tester, 'salutation'), 'Sir/Madam:');
    expect(
      fieldText(tester, 'closing'),
      'Your approval on this matter is highly appreciated.',
    );
  });

  testWidgets('the preview is rebuilt only once typing pauses', (tester) async {
    final (_, previews, _) = await pumpEditor(tester, await seedCopy());
    expect(previews.builds, hasLength(1));

    await tester.enterText(find.byKey(const Key('field-salutation')), 'D');
    await tester.pump(const Duration(milliseconds: 100));
    await tester.enterText(find.byKey(const Key('field-salutation')), 'De');
    await tester.pump(const Duration(milliseconds: 100));
    expect(previews.builds, hasLength(1), reason: 'still typing');

    await tester.pump(kPreviewDebounce + const Duration(milliseconds: 50));
    expect(
      previews.builds,
      hasLength(2),
      reason: 'one rebuild after the pause',
    );
    expect(
      previews.created,
      1,
      reason: 'the same preview re-renders, keeping its zoom and place',
    );
  });

  testWidgets('Download PDF shares the form as it is on screen, unsaved '
      'edits included', (tester) async {
    final (_, _, shared) = await pumpEditor(tester, await seedCopy());

    await tester.enterText(
      find.byKey(const Key('field-researcher.1')),
      'MARIA SANTOS',
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('downloadCopy')));
    await settleReal(tester, () => shared.bytes != null);

    expect(shared.filename, 'Group 3 _ Santos.pdf');
    expect(extractPdfText(shared.bytes!), contains('MARIA SANTOS'));
  });

  testWidgets('leaving with unsaved edits asks first', (tester) async {
    final (router, _, _) = await pumpEditor(tester, await seedCopy());
    await tester.enterText(
      find.byKey(const Key('field-salutation')),
      'Dear Dean:',
    );
    await tester.pump();

    router.pop();
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('confirmLeaveEditor')), findsOneWidget);

    await tester.tap(find.text('Keep editing'));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('field-salutation')),
      findsOneWidget,
      reason: 'Keep editing stays on the copy',
    );

    router.pop();
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('confirmLeaveEditor')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('formsHome')), findsOneWidget);
  });

  testWidgets('going to another page with unsaved edits asks too', (
    tester,
  ) async {
    final (router, _, _) = await pumpEditor(tester, await seedCopy());
    await tester.enterText(
      find.byKey(const Key('field-salutation')),
      'Dear Dean:',
    );
    await tester.pump();

    router.go('/forms');
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('confirmLeaveEditor')), findsOneWidget);
  });

  testWidgets('leaving with nothing unsaved does not ask', (tester) async {
    final (router, _, _) = await pumpEditor(tester, await seedCopy());
    router.pop();
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('confirmLeaveEditor')), findsNothing);
    expect(find.byKey(const Key('formsHome')), findsOneWidget);
  });

  testWidgets('a wide screen shows the fields and the preview side by side', (
    tester,
  ) async {
    await pumpEditor(tester, await seedCopy());
    expect(find.byKey(const Key('editorFields')), findsOneWidget);
    expect(find.byKey(const Key('previewStub')), findsOneWidget);
    expect(find.byKey(const Key('editorPaneSwitch')), findsNothing);
  });

  testWidgets('a phone switches between Edit and Preview', (tester) async {
    await pumpEditor(tester, await seedCopy(), size: const Size(400, 2400));
    expect(find.byKey(const Key('editorPaneSwitch')), findsOneWidget);
    expect(find.byKey(const Key('editorFields')), findsOneWidget);
    expect(find.byKey(const Key('previewStub')), findsNothing);

    await tester.tap(find.text('Preview'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('previewStub')), findsOneWidget);
    expect(find.byKey(const Key('editorFields')), findsNothing);
  });

  testWidgets('a form that cannot be edited says so instead of crashing', (
    tester,
  ) async {
    await pumpEditor(
      tester,
      await seedCopy(),
      location: '/forms/form99/copies/c1',
    );
    expect(find.byKey(const Key('formUnavailable')), findsOneWidget);
  });

  testWidgets('a deleted copy says so', (tester) async {
    await pumpEditor(
      tester,
      await seedCopy(),
      location: '/forms/form1/copies/gone',
    );
    expect(find.byKey(const Key('copyMissing')), findsOneWidget);
  });

  testWidgets(
    'typing during a save is not silently lost when the save completes',
    (tester) async {
      final db = await seedCopy();
      await pumpEditor(tester, db);

      await tester.enterText(
        find.byKey(const Key('field-salutation')),
        'Dear Dean:',
      );
      await tester.pump();

      await tester.tap(find.byKey(const Key('saveCopy')));
      // A pump alone advances the fake clock, not the real one the fake
      // Firestore transaction resolves on -- so the save has started but not
      // finished when the next keystroke below lands.
      await tester.pump();
      await tester.enterText(
        find.byKey(const Key('field-salutation')),
        'Dear Dean Reyes:',
      );
      await tester.pump();

      await settleReal(tester);

      expect(
        find.text('Unsaved changes'),
        findsOneWidget,
        reason:
            'the keystroke made during the save must still count as '
            'unsaved',
      );
      final data = (await db.doc('users/u1/formCopies/c1').get()).data()!;
      expect(
        data['overrides'],
        {'salutation': 'Dear Dean:'},
        reason: 'only the snapshot taken at Save time was written',
      );
    },
  );

  testWidgets(
    'signing out with unsaved edits leaves the editor without asking',
    (tester) async {
      final auth = MockFirebaseAuth(
        signedIn: true,
        mockUser: MockUser(
          uid: 'u1',
          email: 't@isufst.edu.ph',
          isEmailVerified: true,
        ),
      );
      final (router, _, _) = await pumpEditor(
        tester,
        await seedCopy(),
        auth: auth,
      );
      await tester.enterText(
        find.byKey(const Key('field-salutation')),
        'Dear Dean:',
      );
      await tester.pump();

      await auth.signOut();
      router.go('/forms');
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('confirmLeaveEditor')), findsNothing);
      expect(find.byKey(const Key('formsHome')), findsOneWidget);
    },
  );

  testWidgets('on a phone, switching panes keeps each where it was', (
    tester,
  ) async {
    final (_, previews, _) = await pumpEditor(
      tester,
      await seedCopy(),
      size: const Size(400, 800),
    );
    final fieldsScroll = find.byKey(const Key('editorFieldsScroll'));
    await tester.drag(fieldsScroll, const Offset(0, -600));
    await tester.pumpAndSettle();
    double offset() => tester
        .state<ScrollableState>(
          // The first is the pane's own; the text fields have theirs too.
          find
              .descendant(of: fieldsScroll, matching: find.byType(Scrollable))
              .first,
        )
        .position
        .pixels;
    final scrolledTo = offset();
    expect(scrolledTo, greaterThan(0));

    await tester.tap(find.text('Preview').first);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('previewStub')), findsOneWidget);

    await tester.tap(find.text('Edit').last);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('editorFields')), findsOneWidget);
    expect(offset(), scrolledTo, reason: 'the fields stay where they were');
    expect(
      previews.created,
      1,
      reason:
          'the preview is never rebuilt from scratch, so it keeps '
          'its zoom and the part of the page in view',
    );
  });

  testWidgets('on a wide screen the header stays while the fields scroll', (
    tester,
  ) async {
    await pumpEditor(tester, await seedCopy(), size: const Size(1400, 900));
    final save = find.byKey(const Key('saveCopy'));
    final before = tester.getTopLeft(save);

    await tester.drag(
      find.byKey(const Key('editorFieldsScroll')),
      const Offset(0, -500),
    );
    await tester.pumpAndSettle();

    expect(tester.getTopLeft(save), before);
    expect(find.byKey(const Key('previewStub')), findsOneWidget);
  });
}
