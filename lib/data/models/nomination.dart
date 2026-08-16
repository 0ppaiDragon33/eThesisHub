enum NominationPosition {
  adviser,
  panelist,
  coordinator,
  dean;

  String get value => name;

  static NominationPosition fromString(String? raw) {
    for (final p in NominationPosition.values) {
      if (p.name == raw) return p;
    }
    return NominationPosition.panelist;
  }
}

enum ConformeStatus {
  pending,
  accepted,
  declined,
  exOfficio;

  String get value => name;

  static ConformeStatus fromString(String? raw) {
    for (final c in ConformeStatus.values) {
      if (c.name == raw) return c;
    }
    return ConformeStatus.pending;
  }
}

class Nomination {
  const Nomination({
    required this.nomineeUid,
    required this.nomineeName,
    required this.position,
    required this.exOfficio,
    required this.conformeStatus,
    this.respondedAt,
    this.declineReason,
  });

  final String nomineeUid;
  final String nomineeName;
  final NominationPosition position;
  final bool exOfficio;
  final ConformeStatus conformeStatus;
  final DateTime? respondedAt;
  final String? declineReason;

  /// Ex officio seats are never asked, so they must not gate approval.
  bool get needsConforme => !exOfficio;

  factory Nomination.fromMap(String nomineeUid, Map<String, dynamic> map) {
    return Nomination(
      nomineeUid: nomineeUid,
      nomineeName: map['nomineeName'] as String? ?? '',
      position: NominationPosition.fromString(map['position'] as String?),
      exOfficio: map['exOfficio'] as bool? ?? false,
      conformeStatus: ConformeStatus.fromString(map['conformeStatus'] as String?),
      respondedAt: map['respondedAt'] as DateTime?,
      declineReason: map['declineReason'] as String?,
    );
  }

  Map<String, dynamic> toMap() => {
        'nomineeName': nomineeName,
        'position': position.value,
        'exOfficio': exOfficio,
        'conformeStatus': conformeStatus.value,
        'respondedAt': respondedAt,
        'declineReason': declineReason,
      };
}
