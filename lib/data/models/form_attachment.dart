import 'package:cloud_firestore/cloud_firestore.dart';

/// A copy of a form the leader attached to a request: a snapshot of one of
/// their My files copies, kept with the request so the people who must sign
/// can read it. Stored at `theses/{id}/attachments/form1`.
class FormAttachment {
  const FormAttachment({
    required this.formId,
    required this.copyName,
    required this.overrides,
    this.attachedAt,
  });

  final String formId;

  /// The name the leader gave the copy.
  final String copyName;

  /// The copy's edited text, as it was when attached.
  final Map<String, String> overrides;

  final DateTime? attachedAt;

  factory FormAttachment.fromMap(Map<String, dynamic> m) {
    final raw = (m['overrides'] as Map?) ?? const {};
    return FormAttachment(
      formId: m['formId'] as String? ?? '',
      copyName: m['copyName'] as String? ?? '',
      overrides: {
        for (final e in raw.entries)
          if (e.key is String && e.value is String)
            e.key as String: e.value as String,
      },
      attachedAt: (m['attachedAt'] as Timestamp?)?.toDate(),
    );
  }
}
