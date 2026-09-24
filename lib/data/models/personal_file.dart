import 'package:cloud_firestore/cloud_firestore.dart';

/// A file someone uploaded to their My files. The bytes live in the private
/// bucket at [storagePath]; this record (at `users/{uid}/files/{id}`) is what
/// makes the file appear, and it is readable only by its owner.
class PersonalFile {
  const PersonalFile({
    required this.id,
    required this.name,
    required this.storagePath,
    required this.contentType,
    required this.sizeBytes,
    this.folderId,
    this.createdAt,
  });

  final String id;

  /// The person's own filename, shown in the list.
  final String name;
  final String storagePath;
  final String contentType;
  final int sizeBytes;
  final String? folderId;
  final DateTime? createdAt;

  factory PersonalFile.fromMap(String id, Map<String, dynamic> m) =>
      PersonalFile(
        id: id,
        name: m['name'] as String? ?? '',
        storagePath: m['storagePath'] as String? ?? '',
        contentType: m['contentType'] as String? ?? '',
        sizeBytes: (m['sizeBytes'] as num?)?.toInt() ?? 0,
        folderId: m['folderId'] as String?,
        createdAt: (m['createdAt'] as Timestamp?)?.toDate(),
      );
}
