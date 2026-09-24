import 'package:cloud_firestore/cloud_firestore.dart';

/// A folder in someone's My files, at `users/{uid}/folders/{id}`. One level
/// only: a folder holds form copies and files, never other folders.
class PersonalFolder {
  const PersonalFolder({required this.id, required this.name, this.createdAt});

  final String id;
  final String name;
  final DateTime? createdAt;

  factory PersonalFolder.fromMap(String id, Map<String, dynamic> m) =>
      PersonalFolder(
        id: id,
        name: m['name'] as String? ?? '',
        createdAt: (m['createdAt'] as Timestamp?)?.toDate(),
      );
}
