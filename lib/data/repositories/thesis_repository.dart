import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:ethesishub/data/models/faculty_directory_entry.dart';
import 'package:ethesishub/data/models/nomination.dart';
import 'package:ethesishub/data/models/thesis.dart';
import 'package:ethesishub/data/models/thesis_status.dart';

class ThesisRepository {
  ThesisRepository(this._db);

  final FirebaseFirestore _db;

  CollectionReference<Map<String, dynamic>> get _theses =>
      _db.collection('theses');

  CollectionReference<Map<String, dynamic>> _nominations(String thesisId) =>
      _theses.doc(thesisId).collection('nominations');

  static DateTime? _date(Object? v) =>
      v is Timestamp ? v.toDate() : (v is DateTime ? v : null);

  Thesis _toThesis(String id, Map<String, dynamic> data) {
    final raw = Map<String, dynamic>.from(data);
    raw['createdAt'] = _date(raw['createdAt']) ?? DateTime.now().toUtc();
    raw['coordinatorRecommendedAt'] = _date(raw['coordinatorRecommendedAt']);
    raw['deanApprovedAt'] = _date(raw['deanApprovedAt']);
    return Thesis.fromMap(id, raw);
  }

  Nomination _toNomination(String uid, Map<String, dynamic> data) {
    final raw = Map<String, dynamic>.from(data);
    raw['respondedAt'] = _date(raw['respondedAt']);
    return Nomination.fromMap(uid, raw);
  }

  Future<String> createThesis({
    required String leaderUid,
    required String workingTitle,
    required List<String> memberNames,
    required String college,
    required String program,
    required String semester,
    required String academicYear,
  }) async {
    final doc = _theses.doc();
    await doc.set({
      'leaderUid': leaderUid,
      'workingTitle': workingTitle.trim(),
      'memberNames': memberNames,
      'college': college,
      'program': program,
      'semester': semester,
      'academicYear': academicYear,
      'status': ThesisStatus.draft.value,
      'adviserUid': null,
      'panelistUids': <String>[],
      'coordinatorRecommendedAt': null,
      'coordinatorRecommendedBy': null,
      'deanApprovedAt': null,
      'deanApprovedBy': null,
      'createdAt': FieldValue.serverTimestamp(),
    });
    return doc.id;
  }

  Stream<Thesis?> watchThesis(String thesisId) {
    return _theses.doc(thesisId).snapshots().map(
        (s) => s.exists ? _toThesis(s.id, s.data()!) : null);
  }

  Stream<Thesis?> watchThesisForLeader(String leaderUid) {
    return _theses
        .where('leaderUid', isEqualTo: leaderUid)
        .limit(1)
        .snapshots()
        .map((s) => s.docs.isEmpty
            ? null
            : _toThesis(s.docs.first.id, s.docs.first.data()));
  }

  Stream<List<Nomination>> watchNominations(String thesisId) {
    return _nominations(thesisId).snapshots().map((s) =>
        s.docs.map((d) => _toNomination(d.id, d.data())).toList());
  }

  Map<String, dynamic> _nominationMap({
    required String name,
    required NominationPosition position,
    required bool exOfficio,
    required ConformeStatus conformeStatus,
  }) => {
        'nomineeName': name,
        'position': position.value,
        'exOfficio': exOfficio,
        'conformeStatus': conformeStatus.value,
        'respondedAt': null,
        'declineReason': null,
      };

  /// Writes every nomination and advances the thesis in one batch, so a
  /// half-submitted nomination cannot exist.
  ///
  /// A nominee's uid can collide across roles — the Dean or a Research
  /// Coordinator may also be nominated by name as adviser or panelist "for
  /// the sake of records". Precedence is resolved explicitly here, by
  /// building one map of uid -> nomination doc before writing anything, so
  /// the result never depends on write/batch ordering:
  ///
  ///   adviser  >  ex officio  >  panelist
  ///
  /// - A panelist nomination that collides with an ex-officio seat collapses
  ///   into that single ex-officio entry (`exOfficio: true`, no Conforme
  ///   asked) — sitting on the panel already follows from holding the
  ///   office.
  /// - An adviser nomination always wins, even over an ex-officio seat:
  ///   supervising a specific thesis is a personal commitment distinct from
  ///   an office-holder's panel seat, and Form 1 prints them on the Conforme
  ///   line as Thesis Adviser, so they must accept (`exOfficio: false`,
  ///   `conformeStatus: pending`).
  Future<void> submitNominations({
    required String thesisId,
    required FacultyDirectoryEntry adviser,
    required List<FacultyDirectoryEntry> panelists,
    required List<FacultyDirectoryEntry> exOfficio,
  }) async {
    if (panelists.length < 3) {
      throw ArgumentError('At least three panel members are required.');
    }

    final batch = _db.batch();
    final noms = _nominations(thesisId);

    // Lowest precedence first, each later pass deliberately overwriting the
    // uid's entry so the final map reflects `adviser > ex officio > panelist`
    // regardless of what order the input lists happen to be in.
    final writes = <String, Map<String, dynamic>>{};

    for (final p in panelists) {
      writes[p.uid] = _nominationMap(
        name: p.fullName,
        position: NominationPosition.panelist,
        exOfficio: false,
        conformeStatus: ConformeStatus.pending,
      );
    }

    for (final e in exOfficio) {
      writes[e.uid] = _nominationMap(
        name: e.fullName,
        position: e.role == 'dean'
            ? NominationPosition.dean
            : NominationPosition.coordinator,
        exOfficio: true,
        conformeStatus: ConformeStatus.exOfficio,
      );
    }

    writes[adviser.uid] = _nominationMap(
      name: adviser.fullName,
      position: NominationPosition.adviser,
      exOfficio: false,
      conformeStatus: ConformeStatus.pending,
    );

    for (final entry in writes.entries) {
      batch.set(noms.doc(entry.key), entry.value);
    }

    batch.update(_theses.doc(thesisId), {
      'status': ThesisStatus.nominationPendingConforme.value,
    });

    await batch.commit();
  }

  Stream<List<Thesis>> watchByStatus(ThesisStatus status) {
    return _theses
        .where('status', isEqualTo: status.value)
        .snapshots()
        .map((s) => s.docs.map((d) => _toThesis(d.id, d.data())).toList());
  }

  /// The current set of nomination doc ids for a thesis. Nominations are
  /// created exactly once, atomically, by `submitNominations`' batch and are
  /// never added to or removed afterward — only their fields (conformeStatus
  /// etc.) mutate. That invariant is what makes it safe to enumerate ids
  /// with a plain, non-transactional query *before* opening a transaction
  /// below: the transaction never trusts this query's field values, only
  /// the id list, and every field value the transaction decides on is
  /// re-read fresh, per-document, with `transaction.get()`, before any
  /// write commits.
  ///
  /// This split exists because `Transaction.get()` in `cloud_firestore`
  /// (verified against 6.8.0, the version pinned here) only accepts a
  /// `DocumentReference` — there is no `Transaction.get(Query)` overload, so
  /// a collection query cannot run inside a transaction at all. The same is
  /// true of `fake_cloud_firestore` 4.2.0's `_DummyTransaction`. This is a
  /// hard SDK limitation, not a choice made here.
  Future<List<String>> _nominationIds(String thesisId) async {
    final snap = await _nominations(thesisId).get();
    return snap.docs.map((d) => d.id).toList();
  }

  /// Yields one extra microtask turn after `runTransaction` resolves.
  ///
  /// Observed, not assumed: `fake_cloud_firestore` 4.2.0's `_DummyTransaction`
  /// (`fake_cloud_firestore_instance.dart`) issues each `Transaction.update`/
  /// `.set` as `documentReference.update(data)` **without awaiting it** —
  /// by design, since real `Transaction.update()` also returns
  /// synchronously (writes are staged and committed as a batch by the real
  /// SDK when the handler returns). But the fake does not defer/batch: it
  /// fires the real, awaitable `MockDocumentReference.update()` and drops
  /// the Future. That method's first line is `await
  /// _firestore.maybeThrowSecurityException(...)`, itself one `await
  /// Future.value()` — so the fake's actual write to its backing map lands
  /// exactly one microtask turn *after* `runTransaction()` can have already
  /// resolved. Confirmed empirically: immediately after `await
  /// _db.runTransaction(...)`, a plain `watchThesis(id).first` (which reads
  /// via `snapshots().startWith(_getSync())`, i.e. synchronously at
  /// subscription time) could observe the pre-write value, while an
  /// awaited `.get()` call — which itself yields once internally — always
  /// observed the post-write value. A single extra microtask hop closes
  /// that gap without any wall-clock delay. This has no effect against the
  /// real `cloud_firestore` SDK, where `runTransaction()` never resolves
  /// before the commit is confirmed.
  Future<void> _settleAfterTransaction() => Future<void>.value();

  /// Records a nominee's Conforme and, once every nomination that actually
  /// needs one has been accepted, advances the thesis — atomically with the
  /// read that decides it, and only while the thesis is still awaiting
  /// Conforme.
  ///
  /// Ex-officio seats (`needsConforme == false`) are never asked and must
  /// never gate this — see `Nomination.needsConforme`.
  ///
  /// Guarded on the thesis's *current persisted* status, read fresh inside
  /// the transaction, the same way `recommend`/`approve` guard themselves —
  /// never on anything the caller supplies. A response that arrives after
  /// the thesis has already left `nominationPendingConforme` (a duplicate
  /// tap, a retried write, a stale client, or an honest late click after
  /// the dean has already approved) is rejected with a `StateError` instead
  /// of being silently recorded: recording it anyway would let conforme
  /// data exist for a stage the thesis has already passed, and a silent
  /// no-op would hide exactly the class of bug this guard exists to catch.
  /// This matches `recommend`/`approve`'s behaviour, and guarantees the
  /// thesis status can never move backwards under any input.
  Future<void> respondToNomination({
    required String thesisId,
    required String nomineeUid,
    required bool accept,
    String? declineReason,
  }) async {
    final ids = await _nominationIds(thesisId);

    await _db.runTransaction((tx) async {
      // --- reads first, all of them, before any write ---
      final thesisRef = _theses.doc(thesisId);
      final thesisSnap = await tx.get(thesisRef);
      if (!thesisSnap.exists) {
        throw StateError('Thesis $thesisId does not exist.');
      }
      final status = _toThesis(thesisSnap.id, thesisSnap.data()!).status;

      final noms = <String, Nomination>{};
      for (final nomId in ids) {
        final snap = await tx.get(_nominations(thesisId).doc(nomId));
        if (snap.exists) {
          noms[nomId] = _toNomination(snap.id, snap.data()!);
        }
      }

      if (status != ThesisStatus.nominationPendingConforme) {
        throw StateError(
            'Cannot respond to a nomination: this thesis is no longer '
            'awaiting Conforme (current status: ${status.value}).');
      }

      // --- then writes ---
      tx.update(_nominations(thesisId).doc(nomineeUid), {
        'conformeStatus': (accept ? ConformeStatus.accepted : ConformeStatus.declined)
            .value,
        'respondedAt': FieldValue.serverTimestamp(),
        'declineReason': accept ? null : declineReason,
      });

      if (!accept) return;

      // nomineeUid is excluded rather than trusted from the (pre-write)
      // fresh read above, since this write is what makes it accepted.
      final outstanding = noms.values
          .where((n) => n.nomineeUid != nomineeUid)
          .where((n) => n.needsConforme)
          .where((n) => n.conformeStatus != ConformeStatus.accepted);

      if (outstanding.isEmpty) {
        tx.update(thesisRef, {
          'status': ThesisStatus.nominationPendingCoordinator.value,
        });
      }
    });
    await _settleAfterTransaction();
  }

  /// A Research Coordinator recommends the thesis to the Dean. Only valid
  /// while the thesis is awaiting coordinator action.
  Future<void> recommend({
    required String thesisId,
    required String coordinatorUid,
  }) async {
    final thesis = await watchThesis(thesisId).first;
    if (thesis == null ||
        thesis.status != ThesisStatus.nominationPendingCoordinator) {
      throw StateError(
          'Cannot recommend a thesis that is not pending coordinator review.');
    }
    await _theses.doc(thesisId).update({
      'status': ThesisStatus.nominationPendingDean.value,
      'coordinatorRecommendedAt': FieldValue.serverTimestamp(),
      'coordinatorRecommendedBy': coordinatorUid,
    });
  }

  /// The Dean approves. Fixes `adviserUid` and `panelistUids` from the
  /// accepted nominations, so the stored panel can never disagree with what
  /// the nominees actually accepted.
  ///
  /// Per spec §4.0a: ex-officio members and the adviser must never appear in
  /// `panelistUids[]` — the adviser lives in `adviserUid` instead — and
  /// declined nominees must never appear in either.
  ///
  /// The status guard, the nomination reads that derive `adviserUid`/
  /// `panelistUids`, and the write that commits them all happen inside one
  /// `runTransaction` — see `_nominationIds` for why the id list itself is
  /// fetched outside it. A decline landing after the id list is fetched but
  /// before this method would previously have committed can no longer slip
  /// through: `transaction.get()` re-reads each nomination's actual
  /// `conformeStatus` fresh, immediately before the write, inside the same
  /// transaction.
  Future<void> approve({
    required String thesisId,
    required String deanUid,
  }) async {
    final ids = await _nominationIds(thesisId);

    await _db.runTransaction((tx) async {
      // --- reads first, all of them, before any write ---
      final thesisRef = _theses.doc(thesisId);
      final thesisSnap = await tx.get(thesisRef);
      final status = thesisSnap.exists
          ? _toThesis(thesisSnap.id, thesisSnap.data()!).status
          : null;

      final all = <Nomination>[];
      for (final nomId in ids) {
        final snap = await tx.get(_nominations(thesisId).doc(nomId));
        if (snap.exists) {
          all.add(_toNomination(snap.id, snap.data()!));
        }
      }

      if (status != ThesisStatus.nominationPendingDean) {
        throw StateError(
            'Cannot approve a thesis that is not pending dean review.');
      }

      final accepted =
          all.where((n) => n.conformeStatus == ConformeStatus.accepted);

      final adviser = accepted
          .where((n) => n.position == NominationPosition.adviser)
          .toList();
      final panelists = accepted
          .where((n) =>
              n.position == NominationPosition.panelist && !n.exOfficio)
          .map((n) => n.nomineeUid)
          .toList();

      if (adviser.isEmpty) {
        throw StateError('Cannot approve without an accepted adviser.');
      }
      if (panelists.length < 3) {
        throw StateError('Cannot approve with fewer than three panel members.');
      }

      // --- then the write ---
      tx.update(thesisRef, {
        'status': ThesisStatus.nominationApproved.value,
        'adviserUid': adviser.first.nomineeUid,
        'panelistUids': panelists,
        'deanApprovedAt': FieldValue.serverTimestamp(),
        'deanApprovedBy': deanUid,
      });
    });
    await _settleAfterTransaction();
  }

  /// Every nomination addressed to this user that still needs their
  /// Conforme, across all theses, paired with the id of the thesis it
  /// belongs to (the inbox cannot act on a nomination without knowing its
  /// parent thesis). Requires the collection-group rule on `nominations`.
  Stream<List<({String thesisId, Nomination nomination})>>
      watchMyPendingNominations(String uid) {
    return _db
        .collectionGroup('nominations')
        .where(FieldPath.documentId, isEqualTo: uid)
        .snapshots()
        .map((s) => s.docs
            .map((d) => (
                  thesisId: d.reference.parent.parent!.id,
                  nomination: _toNomination(d.id, d.data()),
                ))
            .where((r) => r.nomination.conformeStatus == ConformeStatus.pending)
            .toList());
  }
}
