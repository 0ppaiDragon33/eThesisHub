import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ethesishub/data/models/defence.dart';
import 'package:ethesishub/data/services/storage_service.dart';
import 'package:ethesishub/features/defence/manuscript/manuscript_plan.dart';
import 'package:ethesishub/features/defence/manuscript/manuscript_providers.dart';
import 'package:ethesishub/providers/auth_providers.dart';

class _SizesOnly implements ManuscriptRasterizer {
  _SizesOnly(this.count);
  final int count;
  @override
  Future<List<Size>> pageSizes(Uint8List pdf) async =>
      List.filled(count, const Size(210, 297));
  @override
  Future<ui.Image> renderPage(Uint8List pdf, int index) =>
      throw UnimplementedError();
}

ProviderContainer container(FakeFirebaseFirestore db,
    {List<Override> overrides = const []}) {
  final c = ProviderContainer(overrides: [
    firestoreProvider.overrideWithValue(db),
    firebaseAuthProvider.overrideWithValue(MockFirebaseAuth(
      signedIn: true,
      mockUser: MockUser(uid: 'p1', email: 'p1@isufst.edu.ph'),
    )),
    ...overrides,
  ]);
  addTearDown(c.dispose);
  return c;
}

void main() {
  test('reads the approved version of each approved chapter', () async {
    final db = FakeFirebaseFirestore();
    final docs = db.collection('theses/t1/documents');
    await docs.doc('chapterI').set(
        {'type': 'chapterI', 'currentVersion': 2, 'status': 'approved'});
    for (final n in [1, 2]) {
      await docs.doc('chapterI').collection('versions').doc('$n').set({
        'version': n,
        'storagePath': 'theses/t1/chapterI/v$n.pdf',
        'fileUrl': '',
        'uploadedBy': 'l1',
        'uploadedAt': Timestamp.now(),
        'mimeType': 'application/pdf',
        'sizeBytes': 4,
      });
    }
    await docs.doc('chapterII').set(
        {'type': 'chapterII', 'currentVersion': 1, 'status': 'revise'});

    final c = container(db);
    const key = (defenceId: 'd1', thesisId: 't1', type: DefenceType.preOral);
    c.listen(manuscriptPartsProvider(key), (_, _) {});
    List<ManuscriptPart>? parts;
    for (var i = 0; i < 20 && parts == null; i++) {
      await Future<void>.delayed(Duration.zero);
      parts = c.read(manuscriptPartsProvider(key)).valueOrNull;
    }

    expect(parts!.map((p) => p.kind), [
      ManuscriptPartKind.pdf,
      ManuscriptPartKind.notApproved,
      ManuscriptPartKind.missing,
    ]);
    expect(parts.first.version!.storagePath, 'theses/t1/chapterI/v2.pdf');
  });

  test('a chapter reopened after the defence shows the version it marked',
      () async {
    final db = FakeFirebaseFirestore();
    await db.collection('defenses').doc('d1').set({
      'thesisId': 't1',
      'type': 'preOral',
      'panelUids': ['p1'],
      'adviserUid': 'a1',
      'leaderUid': 'l1',
      'status': 'completed',
    });
    final docs = db.collection('theses/t1/documents');
    // Reopened by the adviser: same version, status back to revise.
    await docs.doc('chapterII').set(
        {'type': 'chapterII', 'currentVersion': 2, 'status': 'revise'});
    for (final n in [1, 2]) {
      await docs.doc('chapterII').collection('versions').doc('$n').set({
        'version': n,
        'storagePath': 'theses/t1/chapterII/v$n.pdf',
        'fileUrl': '',
        'uploadedBy': 'l1',
        'uploadedAt': Timestamp.now(),
        'mimeType': 'application/pdf',
        'sizeBytes': 4,
      });
    }
    await docs.doc('chapterIII').set(
        {'type': 'chapterIII', 'currentVersion': 1, 'status': 'revise'});
    await db.collection('defenses/d1/annotations').doc('h1').set({
      'authorUid': 'p1',
      'authorName': 'Dr. Panel',
      'authorPosition': 'Panel Member',
      'chapter': 'chapterII',
      'version': 2,
      'page': 0,
      'rect': {'x': 0.1, 'y': 0.1, 'w': 0.5, 'h': 0.05},
      'body': 'Cite it.',
      'createdAt': Timestamp.now(),
    });

    final c = container(db);
    const key = (defenceId: 'd1', thesisId: 't1', type: DefenceType.preOral);
    c.listen(manuscriptPartsProvider(key), (_, _) {});
    List<ManuscriptPart>? parts;
    for (var i = 0; i < 20 && parts == null; i++) {
      await Future<void>.delayed(Duration.zero);
      parts = c.read(manuscriptPartsProvider(key)).valueOrNull;
    }

    expect(parts!.map((p) => p.kind), [
      ManuscriptPartKind.missing,
      ManuscriptPartKind.pdf,
      ManuscriptPartKind.notApproved, // reopened, but nothing marked on it
    ]);
    expect(parts[1].reopened, isTrue);
    expect(parts[1].version!.storagePath, 'theses/t1/chapterII/v2.pdf');
  });

  test('a chapter PDF is downloaded once and measured', () async {
    var downloads = 0;
    final c = container(FakeFirebaseFirestore(), overrides: [
      chapterFileLoaderProvider.overrideWithValue((path) async {
        downloads++;
        return Uint8List(4);
      }),
      manuscriptRasterizerProvider.overrideWithValue(_SizesOnly(3)),
    ]);
    c.listen(chapterPdfProvider('p.pdf'), (_, _) {});
    final pdf = await c.read(chapterPdfProvider('p.pdf').future);
    await c.read(chapterPdfProvider('p.pdf').future);
    expect(pdf.pageSizes, hasLength(3));
    expect(downloads, 1);
  });

  test('a PDF with no pages is a failure, not an empty chapter', () async {
    final c = container(FakeFirebaseFirestore(), overrides: [
      chapterFileLoaderProvider.overrideWithValue((path) async => Uint8List(4)),
      manuscriptRasterizerProvider.overrideWithValue(_SizesOnly(0)),
    ]);
    c.listen(chapterPdfProvider('p.pdf'), (_, _) {});
    await expectLater(c.read(chapterPdfProvider('p.pdf').future),
        throwsA(isA<StorageFailure>()));
  });
}
