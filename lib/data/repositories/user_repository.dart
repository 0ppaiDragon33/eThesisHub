import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:ethesishub/data/models/app_user.dart';
import 'package:ethesishub/data/models/faculty_invite.dart';
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

  /// [college] and [specialization] are optional and travel with the invite
  /// onto the promoted account — see [promoteFromInvite]. They have no other
  /// source in the app, and the coordinator issuing the invite knows them.
  Future<void> createInvite({
    required String email,
    required UserRole role,
    required String invitedBy,
    String? college,
    String? specialization,
  }) {
    return _invites.doc(normalise(email)).set({
      'role': role.value,
      'invitedBy': invitedBy,
      'createdAt': FieldValue.serverTimestamp(),
      'consumedAt': null,
      if (college != null && college.isNotEmpty) 'college': college,
      if (specialization != null && specialization.isNotEmpty)
        'specialization': specialization,
    });
  }

  /// Every invite, open and consumed alike — consumed ones are the permanent
  /// record of a completed promotion, so the list is an audit surface as much
  /// as a worklist. Only coordinators may read it (`firestore.rules`).
  Stream<List<FacultyInvite>> watchInvites() {
    return _invites.snapshots().map((s) {
      final list = s.docs
          .map((d) => FacultyInvite.fromMap(d.id, _withDates(d.data())))
          .toList();
      list.sort((a, b) => a.email.compareTo(b.email));
      return list;
    });
  }

  /// Retracts an invite that was never claimed. Consumed invites are the
  /// record of a promotion that actually happened, so removing one would
  /// erase evidence rather than cancel anything — the caller is expected to
  /// offer this only for open invites, and the rules permit deletion by
  /// coordinators alone.
  Future<void> deleteInvite(String email) =>
      _invites.doc(normalise(email)).delete();

  /// Firestore hands back `Timestamp`; the models are pure Dart.
  Map<String, dynamic> _withDates(Map<String, dynamic> raw) {
    return {
      ...raw,
      'createdAt': (raw['createdAt'] as Timestamp?)?.toDate(),
      'consumedAt': (raw['consumedAt'] as Timestamp?)?.toDate(),
    };
  }

  /// Applies a pending invite, returning the granted role or null if none.
  ///
  /// The invite is marked consumed rather than deleted, so every completed
  /// promotion leaves a permanent record.
  Future<UserRole?> promoteFromInvite({
    required String uid,
    required String email,
  }) async {
    final snapshot = await _invites.doc(normalise(email)).get();
    if (!snapshot.exists) return null;
    final data = snapshot.data()!;
    if (data['consumedAt'] != null) return null;
    final role = UserRole.tryParse(data['role'] as String?);
    if (role == null) return null;

    // Three separate writes, because the security rules police them under
    // three different branches and each is deliberately narrow:
    //
    //  1. the role, under the invite branch, which permits `onlyChanged
    //     (['role'])` and requires the invite to still be unconsumed;
    //  2. the profile fields, under the account-owner branch, which permits
    //     `onlyChanged(['fullName','college','program','specialization'])`
    //     and never `role`;
    //  3. marking the invite consumed.
    //
    // They cannot be merged: a single update touching `role` AND `college`
    // satisfies neither branch's `onlyChanged`, and would be denied outright
    // in production while passing every local test, since
    // `fake_cloud_firestore` does not enforce rules.
    await _users.doc(uid).update({'role': role.value});

    // Only the fields the invite actually carries. Writing them
    // unconditionally would null out whatever the account already had.
    final profile = <String, dynamic>{
      if (data['college'] != null) 'college': data['college'],
      if (data['specialization'] != null)
        'specialization': data['specialization'],
    };
    if (profile.isNotEmpty) {
      await _users.doc(uid).update(profile);
    }

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
