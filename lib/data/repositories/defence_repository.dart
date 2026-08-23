import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:ethesishub/data/models/defence.dart';

class DefenceRepository {
  DefenceRepository(this._db);

  final FirebaseFirestore _db;

  CollectionReference<Map<String, dynamic>> get _defences =>
      _db.collection('defenses');

  DocumentReference<Map<String, dynamic>> _defence(String id) =>
      _defences.doc(id);

  Defence _toDefence(String id, Map<String, dynamic> raw) {
    return Defence.fromMap(id, {
      ...raw,
      'scheduledAt': (raw['scheduledAt'] as Timestamp?)?.toDate(),
      'createdAt': (raw['createdAt'] as Timestamp?)?.toDate(),
      'consolidatedAt': (raw['consolidatedAt'] as Timestamp?)?.toDate(),
    });
  }

  List<Defence> _map(QuerySnapshot<Map<String, dynamic>> s) {
    final list = s.docs.map((d) => _toDefence(d.id, d.data())).toList();
    // Soonest first. Sorted in Dart rather than with orderBy so the query
    // needs no composite index alongside its where clause, and a document
    // missing scheduledAt is not silently dropped from the list.
    list.sort((a, b) {
      final at = a.scheduledAt;
      final bt = b.scheduledAt;
      if (at == null || bt == null) return a.id.compareTo(b.id);
      final byTime = at.compareTo(bt);
      return byTime != 0 ? byTime : a.id.compareTo(b.id);
    });
    return list;
  }

  Future<String> schedule({
    required String thesisId,
    required DefenceType type,
    required DateTime scheduledAt,
    required String venue,
    required List<String> panelUids,
    required String adviserUid,
    required String leaderUid,
    required String createdBy,
  }) async {
    if (venue.trim().isEmpty) throw ArgumentError('Give the defence a venue.');

    final ref = await _defences.add({
      'thesisId': thesisId,
      'type': type.value,
      'scheduledAt': Timestamp.fromDate(scheduledAt),
      'venue': venue.trim(),
      'panelUids': panelUids,
      'adviserUid': adviserUid,
      'leaderUid': leaderUid,
      'status': DefenceStatus.scheduled.value,
      'createdBy': createdBy,
      // The rule pins createdAt to request.time. A client-generated
      // Timestamp.now() can never equal the server's commit timestamp, so
      // every create would be denied in production while every Dart test
      // here (fake_cloud_firestore enforces no rules) would keep passing.
      'createdAt': FieldValue.serverTimestamp(),
    });
    return ref.id;
  }

  Stream<Defence?> watchDefence(String defenceId) {
    return _defence(defenceId).snapshots().map(
        (s) => s.exists ? _toDefence(s.id, s.data()!) : null);
  }

  // Filters on leaderUid rather than thesisId: probed against the emulator,
  // Firestore denies a list query that does not filter on the field the
  // matching rule arm reads, and adding a composite index on thesisId
  // changed nothing. leaderUid is the field the leader's rule arm checks.
  Stream<List<Defence>> watchForLeader(String uid) => _defences
      .where('leaderUid', isEqualTo: uid)
      .snapshots()
      .map(_map);

  Stream<List<Defence>> watchForAdviser(String uid) => _defences
      .where('adviserUid', isEqualTo: uid)
      .snapshots()
      .map(_map);

  Stream<List<Defence>> watchForPanelist(String uid) => _defences
      .where('panelUids', arrayContains: uid)
      .snapshots()
      .map(_map);

  Stream<List<Defence>> watchAll() => _defences.snapshots().map(_map);

  /// Oldest first — the log reads as a transcript.
  Stream<List<DefenceComment>> watchComments(String defenceId) {
    return _defence(defenceId).collection('comments').snapshots().map((s) {
      final list = s.docs
          .map((d) => DefenceComment.fromMap(d.id, {
                ...d.data(),
                'createdAt': (d.data()['createdAt'] as Timestamp?)?.toDate(),
              }))
          .toList();
      list.sort((a, b) {
        final at = a.createdAt;
        final bt = b.createdAt;
        if (at == null || bt == null) return a.id.compareTo(b.id);
        final byTime = at.compareTo(bt);
        return byTime != 0 ? byTime : a.id.compareTo(b.id);
      });
      return list;
    });
  }

  /// Forward one step only.
  ///
  /// The rules enforce this too, but `fake_cloud_firestore` enforces none of
  /// them, so without the check here every Dart test would pass against a
  /// transition no real user could make.
  Future<void> setStatus({
    required String defenceId,
    required DefenceStatus status,
  }) async {
    final snap = await _defence(defenceId).get();
    if (!snap.exists) throw StateError('That defence no longer exists.');
    final current = DefenceStatus.fromString(snap.data()!['status'] as String?);

    final legal = (current == DefenceStatus.scheduled &&
            status == DefenceStatus.inProgress) ||
        (current == DefenceStatus.inProgress &&
            status == DefenceStatus.completed);
    if (!legal) {
      throw StateError(
          'A defence goes scheduled, then in progress, then completed. It '
          'cannot skip a step or go back.');
    }

    await _defence(defenceId).update({'status': status.value});
  }

  Future<void> addComment({
    required String defenceId,
    required String authorUid,
    required String authorName,
    required String authorPosition,
    required String body,
  }) async {
    final text = body.trim();
    if (text.isEmpty) throw ArgumentError('Write something first.');

    final snap = await _defence(defenceId).get();
    if (!snap.exists) throw StateError('That defence no longer exists.');
    final status =
        DefenceStatus.fromString(snap.data()!['status'] as String?);
    if (!status.acceptsComments) {
      throw StateError(
          'Comments can only be added while the defence is under way.');
    }

    await _defence(defenceId).collection('comments').add({
      'authorUid': authorUid,
      'authorName': authorName,
      'authorPosition': authorPosition,
      'body': text,
      // Same reasoning as schedule(): the rule pins createdAt to
      // request.time, so it must be the server's clock, not the client's.
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  /// The adviser's release, which is what opens the log to the group.
  Future<void> release(String defenceId) async {
    final snap = await _defence(defenceId).get();
    if (!snap.exists) throw StateError('That defence no longer exists.');
    final data = snap.data()!;
    if (DefenceStatus.fromString(data['status'] as String?) !=
        DefenceStatus.completed) {
      throw StateError(
          'Consolidate once the defence is closed, so the log is complete.');
    }
    if (data['consolidatedAt'] != null) {
      throw StateError('These comments have already been released.');
    }
    await _defence(defenceId)
        .update({'consolidatedAt': FieldValue.serverTimestamp()});
  }
}
