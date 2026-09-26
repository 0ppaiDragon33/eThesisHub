/// Which change a request asks for. The value is also the document id, so a
/// thesis holds at most one request of each kind (spec 2026-09-25 §4.1).
enum ChangeRequestType {
  adviser,
  title;

  String get value => name;
  String get id => name;

  static ChangeRequestType? fromString(String? raw) {
    for (final t in values) {
      if (t.name == raw) return t;
    }
    return null;
  }
}

/// One approver's answer. Defaults to `pending` — the safe state that grants
/// nothing and blocks the stage.
enum SignoffStatus {
  pending,
  accepted,
  declined;

  String get value => name;

  static SignoffStatus fromString(String? raw) {
    for (final s in values) {
      if (s.name == raw) return s;
    }
    return SignoffStatus.pending;
  }
}

/// Where a request sits in its chain (spec §4.2). `pendingAdvisers` is the
/// adviser request's first stage (both advisers accept in parallel);
/// `pendingAdviser` is the title request's (the current adviser notes it).
enum ChangeRequestStage {
  pendingAdvisers,
  pendingAdviser,
  pendingCoordinator,
  pendingDean,
  approved,
  returned;

  String get value => name;

  /// Null rather than a default: an unknown stage must not read as an open
  /// one that some approver could act on.
  static ChangeRequestStage? fromString(String? raw) {
    for (final s in values) {
      if (s.name == raw) return s;
    }
    return null;
  }

  bool get isPending =>
      this == pendingAdvisers ||
      this == pendingAdviser ||
      this == pendingCoordinator ||
      this == pendingDean;
}

/// The roles that sign a request of [type], in order. The adviser request has
/// two adviser signers (new and former); the title request has one.
List<String> signoffRolesFor(ChangeRequestType type) => switch (type) {
  ChangeRequestType.adviser => const [
    'newAdviser',
    'formerAdviser',
    'coordinator',
    'dean',
  ],
  ChangeRequestType.title => const ['adviser', 'coordinator', 'dean'],
};

/// The stage a fresh request of [type] starts at.
ChangeRequestStage firstStageFor(ChangeRequestType type) =>
    type == ChangeRequestType.adviser
    ? ChangeRequestStage.pendingAdvisers
    : ChangeRequestStage.pendingAdviser;

/// The stage after [stage], or null past the Dean. Both adviser first stages
/// lead to the Coordinator.
ChangeRequestStage? nextStage(ChangeRequestStage stage) => switch (stage) {
  ChangeRequestStage.pendingAdvisers => ChangeRequestStage.pendingCoordinator,
  ChangeRequestStage.pendingAdviser => ChangeRequestStage.pendingCoordinator,
  ChangeRequestStage.pendingCoordinator => ChangeRequestStage.pendingDean,
  _ => null,
};

/// One approver's sign-off on a request.
class Signoff {
  const Signoff({
    this.status = SignoffStatus.pending,
    this.respondedAt,
    this.reason,
  });

  final SignoffStatus status;
  final DateTime? respondedAt;

  /// The reason given on a decline; null otherwise.
  final String? reason;

  factory Signoff.fromMap(Map<String, dynamic> map) => Signoff(
    status: SignoffStatus.fromString(map['status'] as String?),
    respondedAt: map['respondedAt'] as DateTime?,
    reason: map['reason'] as String?,
  );

  Map<String, dynamic> toMap() => {
    'status': status.value,
    'respondedAt': respondedAt,
    'reason': reason,
  };
}

/// A student's request to change their thesis's adviser or approved title,
/// routed through the sign-off chain (spec 2026-09-25).
class ChangeRequest {
  const ChangeRequest({
    required this.type,
    required this.stage,
    required this.reasons,
    required this.leaderUid,
    required this.signoffs,
    this.newAdviserUid,
    this.newAdviserName,
    this.formerAdviserUid,
    this.formerAdviserName,
    this.newTitle,
    this.oldTitle,
    this.awaitingUids = const [],
    this.createdAt,
    this.updatedAt,
  });

  final ChangeRequestType type;
  final ChangeRequestStage stage;
  final String reasons;
  final String leaderUid;

  /// One entry per role in [signoffRolesFor].
  final Map<String, Signoff> signoffs;

  final String? newAdviserUid;
  final String? newAdviserName;
  final String? formerAdviserUid;
  final String? formerAdviserName;
  final String? newTitle;

  /// The thesis's working title at the moment a title-change request was
  /// submitted -- captured then because by the time the request reaches
  /// `approved`, the Dean's batch has already overwritten the thesis's
  /// `workingTitle` with [newTitle]. Null for an adviser request.
  final String? oldTitle;

  /// The faculty uids whose sign-off is CURRENTLY awaited on this request.
  /// Denormalized so the faculty inbox can query with `arrayContains` rather
  /// than an unfiltered collection-group scan a per-document read rule would
  /// reject wholesale (spec 2026-09-25 fix round 2, Fix 1). Read-authorization
  /// only -- write authorization still comes from the per-role update arms.
  final List<String> awaitingUids;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  /// True while the request is still moving through the chain — not returned
  /// to the student and not approved.
  bool get isOpen => stage.isPending;

  factory ChangeRequest.fromMap(String id, Map<String, dynamic> map) {
    final rawSignoffs = (map['signoffs'] as Map?) ?? const {};
    return ChangeRequest(
      type:
          ChangeRequestType.fromString(map['type'] as String?) ??
          ChangeRequestType.adviser,
      stage:
          ChangeRequestStage.fromString(map['stage'] as String?) ??
          ChangeRequestStage.returned,
      reasons: map['reasons'] as String? ?? '',
      leaderUid: map['leaderUid'] as String? ?? '',
      signoffs: {
        for (final e in rawSignoffs.entries)
          e.key as String: Signoff.fromMap(
            (e.value as Map).cast<String, dynamic>(),
          ),
      },
      newAdviserUid: map['newAdviserUid'] as String?,
      newAdviserName: map['newAdviserName'] as String?,
      formerAdviserUid: map['formerAdviserUid'] as String?,
      formerAdviserName: map['formerAdviserName'] as String?,
      newTitle: map['newTitle'] as String?,
      oldTitle: map['oldTitle'] as String?,
      awaitingUids: (map['awaitingUids'] as List?)?.cast<String>() ??
          const [],
      createdAt: map['createdAt'] as DateTime?,
      updatedAt: map['updatedAt'] as DateTime?,
    );
  }

  Map<String, dynamic> toMap() => {
    'type': type.value,
    'stage': stage.value,
    'reasons': reasons,
    'leaderUid': leaderUid,
    'signoffs': {for (final e in signoffs.entries) e.key: e.value.toMap()},
    if (newAdviserUid != null) 'newAdviserUid': newAdviserUid,
    if (newAdviserName != null) 'newAdviserName': newAdviserName,
    if (formerAdviserUid != null) 'formerAdviserUid': formerAdviserUid,
    if (formerAdviserName != null) 'formerAdviserName': formerAdviserName,
    if (newTitle != null) 'newTitle': newTitle,
    if (oldTitle != null) 'oldTitle': oldTitle,
    'awaitingUids': awaitingUids,
    'createdAt': createdAt,
    'updatedAt': updatedAt,
  };
}
