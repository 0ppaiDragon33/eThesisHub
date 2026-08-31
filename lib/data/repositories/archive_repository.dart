import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:ethesishub/data/models/archive_entry.dart';
import 'package:ethesishub/data/models/thesis.dart';
import 'package:ethesishub/data/models/thesis_status.dart';

class ArchiveRepository {
  ArchiveRepository(this._db);

  final FirebaseFirestore _db;

  CollectionReference<Map<String, dynamic>> get _archive =>
      _db.collection('archive');

  DocumentReference<Map<String, dynamic>> _entry(String thesisId) =>
      _archive.doc(thesisId);

  ArchiveEntry _toEntry(String id, Map<String, dynamic> raw) {
    return ArchiveEntry.fromMap(id, {
      ...raw,
      'uploadedAt': (raw['uploadedAt'] as Timestamp?)?.toDate(),
      'archivedAt': (raw['archivedAt'] as Timestamp?)?.toDate(),
    });
  }

  /// Every published thesis, newest first.
  ///
  /// Sorted in Dart rather than with `orderBy` so the query needs no index
  /// beside a `where`, and an entry whose `archivedAt` has not yet
  /// resolved from the server sentinel is not silently dropped from the
  /// list — the same reasoning the defences list already carries.
  Stream<List<ArchiveEntry>> watchArchive() {
    return _archive.snapshots().map((s) {
      final list = s.docs.map((d) => _toEntry(d.id, d.data())).toList();
      list.sort((a, b) {
        final at = a.archivedAt;
        final bt = b.archivedAt;
        if (at == null || bt == null) return a.thesisId.compareTo(b.thesisId);
        final byTime = bt.compareTo(at);
        return byTime != 0 ? byTime : a.thesisId.compareTo(b.thesisId);
      });
      return list;
    });
  }

  Stream<ArchiveEntry?> watchEntry(String thesisId) {
    return _entry(thesisId)
        .snapshots()
        .map((s) => s.exists ? _toEntry(s.id, s.data()!) : null);
  }

  /// Publishes a thesis: writes the entry and moves the thesis to
  /// `archived`, as ONE batch.
  ///
  /// Two writes, because rules evaluate each independently and neither can
  /// require the other. The batch is what keeps them together — without it
  /// a failure between the two would leave the archive and the thesis
  /// disagreeing about whether this work is published.
  ///
  /// [title], [adviserName] and [panelNames] are resolved by the CALLER,
  /// not here: the title lives in a subcollection and the names in the
  /// directory, and a repository that reached into both would be doing the
  /// screen's job. They are snapshotted verbatim (D49).
  Future<void> publish({
    required Thesis thesis,
    required String title,
    required String adviserName,
    required List<String> panelNames,
    required String finalDefenceId,
    required String coordinatorUid,
  }) async {
    if (!thesis.hasManuscript) {
      throw StateError('This thesis has no manuscript to publish yet.');
    }
    if (thesis.status == ThesisStatus.archived) {
      throw StateError('This thesis is already in the archive.');
    }
    final existing = await _entry(thesis.id).get();
    if (existing.exists) {
      throw StateError('This thesis is already in the archive.');
    }

    final batch = _db.batch();
    batch.set(_entry(thesis.id), {
      'title': title,
      'memberNames': thesis.memberNames,
      'abstract': thesis.manuscriptAbstract ?? '',
      'college': thesis.college,
      'program': thesis.program,
      'academicYear': thesis.academicYear,
      'adviserName': adviserName,
      'panelNames': panelNames,
      'manuscriptUrl': thesis.manuscriptUrl,
      'manuscriptPath': thesis.manuscriptPath,
      'finalDefenceId': finalDefenceId,
      'uploadedBy': thesis.leaderUid,
      'uploadedAt': thesis.manuscriptUploadedAt == null
          ? null
          : Timestamp.fromDate(thesis.manuscriptUploadedAt!),
      'archivedBy': coordinatorUid,
      // Pinned to request.time by the rule, so it must be the server's.
      'archivedAt': FieldValue.serverTimestamp(),
    });
    batch.update(_db.collection('theses').doc(thesis.id), {
      'status': ThesisStatus.archived.value,
    });
    await batch.commit();
  }

  /// Corrects display metadata on a published entry (D57).
  ///
  /// Cannot touch the manuscript or the archive stamps — the rules refuse
  /// those, and so does this signature: there is no parameter for them.
  Future<void> correct({
    required String thesisId,
    String? title,
    String? abstract,
  }) async {
    final changes = <String, dynamic>{};
    if (title != null && title.trim().isNotEmpty) {
      changes['title'] = title.trim();
    }
    if (abstract != null && abstract.trim().isNotEmpty) {
      changes['abstract'] = abstract.trim();
    }
    if (changes.isEmpty) {
      throw ArgumentError('Nothing to correct.');
    }
    await _entry(thesisId).update(changes);
  }

  /// Removes a published entry.
  ///
  /// Deliberately possible, unlike almost everything else in this project:
  /// an archive entry is a publication, not an audit record, and a thesis
  /// published in error — someone else's work, made readable to the whole
  /// college — has to be retractable. The thesis keeps its `archived`
  /// status; re-publishing after a retraction is a coordinator decision
  /// this milestone does not build.
  Future<void> retract(String thesisId) => _entry(thesisId).delete();
}
