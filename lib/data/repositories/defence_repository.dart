import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:ethesishub/data/models/defence.dart';
import 'package:ethesishub/data/models/evaluation.dart';
import 'package:ethesishub/data/models/evaluation_criteria.dart';

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
      'evaluationsReleasedAt':
          (raw['evaluationsReleasedAt'] as Timestamp?)?.toDate(),
      'verdictRecordedAt': (raw['verdictRecordedAt'] as Timestamp?)?.toDate(),
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

  CollectionReference<Map<String, dynamic>> _evaluations(String defenceId) =>
      _defence(defenceId).collection('evaluations');

  Evaluation _toEvaluation(String id, Map<String, dynamic> raw) {
    return Evaluation.fromMap(id, {
      ...raw,
      'submittedAt': (raw['submittedAt'] as Timestamp?)?.toDate(),
      'updatedAt': (raw['updatedAt'] as Timestamp?)?.toDate(),
    });
  }

  /// Every submitted sheet for a defence, ordered by evaluator uid.
  ///
  /// Sorted in Dart rather than with `orderBy`: the document id IS the
  /// evaluator uid, so there is no field to order on, and a stable order
  /// is what stops the grades table reshuffling its columns between
  /// snapshots.
  Stream<List<Evaluation>> watchEvaluations(String defenceId) {
    return _evaluations(defenceId).snapshots().map((s) {
      final list =
          s.docs.map((d) => _toEvaluation(d.id, d.data())).toList();
      list.sort((a, b) => a.evaluatorUid.compareTo(b.evaluatorUid));
      return list;
    });
  }

  /// One panelist's own sheet, or null if they have not submitted.
  ///
  /// Null is a real answer here, not a failure: before release the rules
  /// let a panelist read only this one document, so this is the only
  /// evaluation stream they can open at all.
  Stream<Evaluation?> watchMyEvaluation(String defenceId, String uid) {
    return _evaluations(defenceId).doc(uid).snapshots().map(
        (s) => s.exists ? _toEvaluation(s.id, s.data()!) : null);
  }

  /// Writes or replaces one panelist's Form 5c.
  ///
  /// `set` with no merge, so an edit replaces the sheet wholesale rather
  /// than leaving a criterion from an earlier version behind.
  ///
  /// Every check below is ALSO a rule. They are repeated here because
  /// `fake_cloud_firestore` enforces none of them, so without these the
  /// whole Dart suite would pass against writes production denies -- and
  /// because a client-side refusal can say WHY, which a
  /// `permission-denied` cannot.
  Future<void> submitEvaluation({
    required String defenceId,
    required String evaluatorUid,
    required String evaluatorName,
    required Map<String, int> scores,
    required Map<String, String> comments,
    required PassFail rating,
  }) async {
    for (final c in evaluationCriteria) {
      final v = scores[c.key];
      if (v == null) {
        throw ArgumentError('Score every criterion before submitting.');
      }
      if (v < 0 || v > c.weight) {
        throw ArgumentError(
            '${c.label} is scored out of ${c.weight}.');
      }
    }
    if (scores.length != evaluationCriteria.length) {
      throw ArgumentError('That sheet has a criterion this form does not.');
    }
    for (final key in comments.keys) {
      if (!contentKeys.contains(key)) {
        throw ArgumentError(
            'Only the Content criteria take a comment on Form 5c.');
      }
    }

    final snap = await _defence(defenceId).get();
    if (!snap.exists) throw StateError('That defence no longer exists.');
    final data = snap.data()!;

    // Mirrors the rules' isPanelistHere(): request.auth.uid in
    // parent().panelUids. Duplicated here because fake_cloud_firestore
    // enforces no rules, and this is the check the milestone's headline
    // decision rests on -- the adviser is deliberately never in panelUids,
    // because they cannot mark at arm's length after months on the thesis.
    // Without this the whole Dart suite would prove nothing about it.
    final panelUids = (data['panelUids'] as List?)?.cast<String>() ?? const [];
    if (!panelUids.contains(evaluatorUid)) {
      if (evaluatorUid == data['adviserUid']) {
        throw StateError(
            'An adviser guides the thesis and cannot also score it.');
      }
      throw StateError('Only a panelist assigned to this defence can score it.');
    }

    final status = DefenceStatus.fromString(data['status'] as String?);
    if (status != DefenceStatus.inProgress &&
        status != DefenceStatus.completed) {
      throw StateError(
          'A defence can only be scored once it is under way.');
    }
    if (data['evaluationsReleasedAt'] != null) {
      throw StateError(
          'These evaluations have been released and can no longer be '
          'changed.');
    }

    // Trimmed, and blanks dropped rather than stored: an empty string is
    // not a comment, and the rules accept the key either way, so the
    // distinction has to be made here.
    final cleaned = <String, String>{};
    comments.forEach((key, value) {
      final text = value.trim();
      if (text.isNotEmpty) cleaned[key] = text;
    });

    final existing = await _evaluations(defenceId).doc(evaluatorUid).get();

    await _evaluations(defenceId).doc(evaluatorUid).set({
      // Denormalized at the moment of the act, exactly as addComment
      // stores authorName: a grade sheet naming a uid names nobody, and
      // resolving the name on read would let a later rename rewrite who
      // marked a defence that is already in the record.
      'evaluatorName': evaluatorName,
      'scores': scores,
      'comments': cleaned,
      'total': totalOf(scores),
      'rating': rating.value,
      // On an edit, submittedAt must survive unchanged -- the rules pin
      // it to its stored value, so re-stamping it here would be denied in
      // production while passing against the fake.
      'submittedAt': existing.exists
          ? existing.data()!['submittedAt']
          : FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
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
            status == DefenceStatus.completed) ||
        (current == DefenceStatus.scheduled &&
            status == DefenceStatus.cancelled);
    if (!legal) {
      throw StateError(
          'A defence goes scheduled, then in progress, then completed, and '
          'can only be cancelled while it is still scheduled. It cannot '
          'skip a step or go back.');
    }

    // Opening early is what this guards. A defence opened by accident and
    // closed cannot be reopened -- the lifecycle is forward-only -- so the
    // log would be frozen empty and the record permanent. The rules carry
    // the same window; this check exists because fake_cloud_firestore
    // enforces no rules, so without it every test would pass against a
    // transition no real user could make.
    if (status == DefenceStatus.inProgress) {
      final scheduledAt = (snap.data()!['scheduledAt'] as Timestamp?)?.toDate();
      if (scheduledAt == null) {
        throw StateError('This defence has no scheduled time.');
      }
      final opensAt = scheduledAt.subtract(defenceOpenGrace);
      if (DateTime.now().isBefore(opensAt)) {
        throw StateError(
            'This defence cannot be opened yet. It opens 30 minutes before '
            'its scheduled time.');
      }
    }

    await _defence(defenceId).update({'status': status.value});
  }

  /// Moves the date, time or venue of a defence that has not started.
  ///
  /// Without this the schedule was frozen at creation: a coordinator who
  /// picked the wrong date could neither fix it nor remove the defence,
  /// and the only way forward was opening it anyway.
  Future<void> reschedule({
    required String defenceId,
    required DateTime scheduledAt,
    required String venue,
  }) async {
    if (venue.trim().isEmpty) throw ArgumentError('Give the defence a venue.');

    final snap = await _defence(defenceId).get();
    if (!snap.exists) throw StateError('That defence no longer exists.');
    final current = DefenceStatus.fromString(snap.data()!['status'] as String?);
    if (!current.isEditable) {
      throw StateError(
          'Only a defence that has not started can be rescheduled.');
    }

    await _defence(defenceId).update({
      'scheduledAt': Timestamp.fromDate(scheduledAt),
      'venue': venue.trim(),
    });
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

  /// The adviser's release of the panel's evaluations to each other.
  ///
  /// Deliberately NOT conditioned on "everyone has submitted". Firestore
  /// rules cannot count documents in a collection, so that condition is
  /// unenforceable at the boundary -- and a check here that the rules
  /// cannot back would be theatre: anyone with the SDK could bypass it.
  /// The grades screen prints the count on the button instead, so an
  /// early release is a visible choice.
  Future<void> releaseEvaluations({
    required String defenceId,
    required String adviserUid,
  }) async {
    final snap = await _defence(defenceId).get();
    if (!snap.exists) throw StateError('That defence no longer exists.');
    final data = snap.data()!;

    // Mirrors firestore.rules: defence().adviserUid == request.auth.uid.
    // fake_cloud_firestore enforces no rules, so without this check a
    // coordinator or panelist calling this would appear to succeed in
    // every Dart test while production denies them.
    if (data['adviserUid'] != adviserUid) {
      throw StateError(
          'Only the adviser for this defence releases its evaluations.');
    }

    if (DefenceStatus.fromString(data['status'] as String?) !=
        DefenceStatus.completed) {
      throw StateError(
          'Release the evaluations once the defence is closed.');
    }
    if (data['evaluationsReleasedAt'] != null) {
      throw StateError('These evaluations have already been released.');
    }

    await _defence(defenceId)
        .update({'evaluationsReleasedAt': FieldValue.serverTimestamp()});
  }

  /// Records the verdict the panel deliberated under Guidelines §8b.
  ///
  /// The adviser is the scribe, not the decider -- they are barred from
  /// scoring at all. Nothing here derives the verdict from the panelists'
  /// ratings, and nothing should: §8b hands the decision to a
  /// conversation between people.
  Future<void> recordVerdict({
    required String defenceId,
    required String adviserUid,
    required PassFail verdict,
  }) async {
    final snap = await _defence(defenceId).get();
    if (!snap.exists) throw StateError('That defence no longer exists.');
    final data = snap.data()!;

    if (data['adviserUid'] != adviserUid) {
      throw StateError(
          'Only the adviser for this defence records the verdict.');
    }
    if (data['evaluationsReleasedAt'] == null) {
      throw StateError(
          'Release the evaluations first — the panel deliberates over the '
          'grades.');
    }
    if (data['panelVerdict'] != null) {
      throw StateError('A verdict has already been recorded.');
    }

    await _defence(defenceId).update({
      'panelVerdict': verdict.value,
      'verdictRecordedBy': adviserUid,
      'verdictRecordedAt': FieldValue.serverTimestamp(),
    });
  }
}
