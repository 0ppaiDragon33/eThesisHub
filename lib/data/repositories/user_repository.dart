import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:ethesishub/data/models/app_user.dart';
import 'package:ethesishub/data/models/user_role.dart';

class UserRepository {
  UserRepository(this._db);

  final FirebaseFirestore _db;

  CollectionReference<Map<String, dynamic>> get _users =>
      _db.collection('users');
  CollectionReference<Map<String, dynamic>> get _invites =>
      _db.collection('facultyInvites');

  static String normalise(String email) => email.trim().toLowerCase();

  Future<void> createStudentProfile({
    required String uid,
    required String fullName,
    required String email,
    String? college,
    String? program,
  }) {
    return _users.doc(uid).set({
      'fullName': fullName.trim(),
      'email': normalise(email),
      'role': UserRole.student.value,
      'college': college,
      'program': program,
      'specialization': null,
      'active': true,
      'createdAt': FieldValue.serverTimestamp(),
      'createdBy': null,
    });
  }

  Future<AppUser?> fetchUser(String uid) async {
    final snapshot = await _users.doc(uid).get();
    return _toUser(uid, snapshot.data());
  }

  Stream<AppUser?> watchUser(String uid) {
    return _users.doc(uid).snapshots().map((s) => _toUser(uid, s.data()));
  }

  Future<UserRole?> fetchInviteRole(String email) async {
    final snapshot = await _invites.doc(normalise(email)).get();
    if (!snapshot.exists) return null;
    final data = snapshot.data()!;
    if (data['consumedAt'] != null) return null;
    return UserRole.tryParse(data['role'] as String?);
  }

  Future<void> createInvite({
    required String email,
    required UserRole role,
    required String invitedBy,
  }) {
    return _invites.doc(normalise(email)).set({
      'role': role.value,
      'invitedBy': invitedBy,
      'createdAt': FieldValue.serverTimestamp(),
      'consumedAt': null,
    });
  }

  /// Applies a pending invite, returning the granted role or null if none.
  ///
  /// The invite is marked consumed rather than deleted, so every completed
  /// promotion leaves a permanent record.
  Future<UserRole?> promoteFromInvite({
    required String uid,
    required String email,
  }) async {
    final role = await fetchInviteRole(email);
    if (role == null) return null;

    await _users.doc(uid).update({'role': role.value});
    await _invites.doc(normalise(email)).update({
      'consumedAt': FieldValue.serverTimestamp(),
    });
    return role;
  }

  AppUser? _toUser(String uid, Map<String, dynamic>? data) {
    if (data == null) return null;
    final raw = Map<String, dynamic>.from(data);
    final createdAt = raw['createdAt'];
    // createdAt is null in the local snapshot until the server acknowledges a
    // FieldValue.serverTimestamp() write, so a client reading its own freshly
    // created profile legitimately sees no timestamp. Falling back to "now"
    // keeps that path working; it cannot distinguish that case from genuinely
    // malformed data, which is an accepted trade-off.
    raw['createdAt'] =
        createdAt is Timestamp ? createdAt.toDate() : DateTime.now().toUtc();
    return AppUser.fromMap(uid, raw);
  }
}
