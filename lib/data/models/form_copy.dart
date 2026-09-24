import 'package:cloud_firestore/cloud_firestore.dart';

/// One person's saved copy of a form: which form, what they called it, and
/// the text they changed. Stored at `users/{uid}/formCopies/{id}`, readable
/// only by that person (see `firestore.rules`).
class FormCopy {
  const FormCopy({
    required this.id,
    required this.formId,
    required this.name,
    required this.overrides,
    this.folderId,
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String formId;
  final String name;

  /// Only the blocks whose text differs from the form's own wording.
  final Map<String, String> overrides;

  /// The My files folder this copy sits in (spec Phase 2). Always null until
  /// that phase ships.
  final String? folderId;

  /// Null only in the moment between a local write and the server stamping
  /// its time.
  final DateTime? createdAt;
  final DateTime? updatedAt;

  factory FormCopy.fromMap(String id, Map<String, dynamic> m) {
    final raw = (m['overrides'] as Map?) ?? const {};
    return FormCopy(
      id: id,
      formId: m['formId'] as String? ?? '',
      name: m['name'] as String? ?? '',
      overrides: {
        for (final e in raw.entries)
          if (e.key is String && e.value is String)
            e.key as String: e.value as String,
      },
      folderId: m['folderId'] as String?,
      createdAt: (m['createdAt'] as Timestamp?)?.toDate(),
      updatedAt: (m['updatedAt'] as Timestamp?)?.toDate(),
    );
  }
}
