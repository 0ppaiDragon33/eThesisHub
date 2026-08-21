import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:ethesishub/data/models/chapter.dart';
import 'package:ethesishub/data/models/thesis_status.dart';

class DocumentRepository {
  DocumentRepository(this._db);

  final FirebaseFirestore _db;

  DocumentReference<Map<String, dynamic>> _thesis(String id) =>
      _db.collection('theses').doc(id);

  CollectionReference<Map<String, dynamic>> _documents(String thesisId) =>
      _thesis(thesisId).collection('documents');

  DocumentReference<Map<String, dynamic>> _chapter(
          String thesisId, ChapterId chapter) =>
      _documents(thesisId).doc(chapter.value);

  /// The chapters that exist, in reading order.
  ///
  /// Sorted in Dart on the enum's index, not by document id: `chapterII`
  /// sorts before `chapterIII` lexically but `chapterIV` and `chapterV` do
  /// not reliably follow, and the set is five documents so ordering it
  /// costs nothing and needs no index.
  Stream<List<ThesisChapter>> watchChapters(String thesisId) {
    return _documents(thesisId).snapshots().map((s) {
      final chapters = s.docs
          .where((d) => ChapterId.fromString(d.id) != null)
          .map((d) => ThesisChapter.fromMap(d.id, {
                ...d.data(),
                'updatedAt': (d.data()['updatedAt'] as Timestamp?)?.toDate(),
              }))
          .toList();
      chapters.sort((a, b) => a.id.index.compareTo(b.id.index));
      return chapters;
    });
  }

  /// Newest version first — what a reviewer opens is the current draft.
  Stream<List<ChapterVersion>> watchVersions(
      String thesisId, ChapterId chapter) {
    return _chapter(thesisId, chapter).collection('versions').snapshots().map(
      (s) {
        final versions = s.docs
            .map((d) => ChapterVersion.fromMap({
                  ...d.data(),
                  'uploadedAt':
                      (d.data()['uploadedAt'] as Timestamp?)?.toDate(),
                }))
            .toList();
        versions.sort((a, b) => b.version.compareTo(a.version));
        return versions;
      },
    );
  }

  /// Oldest first — feedback reads as a conversation.
  Stream<List<ChapterFeedback>> watchFeedback(
      String thesisId, ChapterId chapter) {
    return _chapter(thesisId, chapter).collection('feedback').snapshots().map(
      (s) {
        final items = s.docs
            .map((d) => ChapterFeedback.fromMap(d.id, {
                  ...d.data(),
                  'createdAt': (d.data()['createdAt'] as Timestamp?)?.toDate(),
                }))
            .toList();
        // Tie-break on snapshot order, not document id. Two calls close
        // enough together can land on the same millisecond -- clock
        // resolution, not a race -- and Firestore's auto-ids are random, so
        // breaking ties by id would shuffle same-millisecond feedback into
        // an order no one typed it in. The snapshot itself preserves write
        // order, so indexing into it before sorting keeps that order stable.
        final order = List<int>.generate(items.length, (i) => i)
          ..sort((ia, ib) {
            final at = items[ia].createdAt;
            final bt = items[ib].createdAt;
            if (at == null || bt == null) return ia.compareTo(ib);
            final byTime = at.compareTo(bt);
            return byTime != 0 ? byTime : ia.compareTo(ib);
          });
        return [for (final i in order) items[i]];
      },
    );
  }

  /// Adds a version and bumps the chapter, in one batch.
  ///
  /// Batched because the two must not be separable: a version without the
  /// bump is invisible, and a bump without the version points at nothing.
  /// The rules judge each write against the PRE-batch state, which is why
  /// the version rule reads `currentVersion + 1`.
  Future<void> addVersion({
    required String thesisId,
    required ChapterId chapter,
    required String storagePath,
    required String fileUrl,
    required String mimeType,
    required int sizeBytes,
    required String uploadedBy,
  }) async {
    final thesisSnap = await _thesis(thesisId).get();
    if (!thesisSnap.exists) throw StateError('That thesis no longer exists.');
    final status =
        ThesisStatus.fromString(thesisSnap.data()!['status'] as String?);
    if (status != ThesisStatus.titleApproved) {
      throw StateError(
          'Chapters can be uploaded once the title has been approved.');
    }

    final chapterRef = _chapter(thesisId, chapter);
    final chapterSnap = await chapterRef.get();
    final batch = _db.batch();

    final int version;
    if (!chapterSnap.exists) {
      version = 1;
      batch.set(chapterRef, {
        'type': chapter.value,
        'currentVersion': 1,
        'status': ChapterStatus.submitted.value,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } else {
      final chapterData = chapterSnap.data()!;
      final current = ThesisChapter.fromMap(chapterSnap.id, {
        ...chapterData,
        'updatedAt': (chapterData['updatedAt'] as Timestamp?)?.toDate(),
      });
      if (current.status == ChapterStatus.approved) {
        throw StateError(
            'This chapter is approved. Ask your adviser to reopen it before '
            'uploading again.');
      }
      version = current.currentVersion + 1;
      batch.update(chapterRef, {
        'currentVersion': version,
        'status': ChapterStatus.submitted.value,
        'type': chapter.value,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    }

    batch.set(chapterRef.collection('versions').doc('$version'), {
      'version': version,
      'storagePath': storagePath,
      'fileUrl': fileUrl,
      'uploadedBy': uploadedBy,
      'uploadedAt': FieldValue.serverTimestamp(),
      'mimeType': mimeType,
      'sizeBytes': sizeBytes,
    });

    await batch.commit();
  }

  /// The adviser's half of the status: `revise` or `approved` only.
  Future<void> setChapterStatus({
    required String thesisId,
    required ChapterId chapter,
    required ChapterStatus status,
  }) async {
    if (status == ChapterStatus.submitted) {
      throw ArgumentError(
          'Only uploading a version can mark a chapter submitted.');
    }
    await _chapter(thesisId, chapter).update({
      'status': status.value,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> addFeedback({
    required String thesisId,
    required ChapterId chapter,
    required int version,
    required String reviewerUid,
    required String reviewerName,
    required String reviewerRole,
    required String body,
  }) async {
    final text = body.trim();
    if (text.isEmpty) throw ArgumentError('Write something first.');
    await _chapter(thesisId, chapter).collection('feedback').add({
      'version': version,
      'reviewerUid': reviewerUid,
      'reviewerName': reviewerName,
      'reviewerRole': reviewerRole,
      'body': text,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }
}
