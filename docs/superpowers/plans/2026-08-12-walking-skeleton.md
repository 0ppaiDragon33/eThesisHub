# eThesisHub Walking Skeleton Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the foundation of eThesisHub — authentication with no client-selectable role, invite-based faculty promotion, deny-by-default Firestore rules, and role-guarded routing to four distinct dashboards — so that every later module drops into a working application.

**Architecture:** Flutter client talking directly to Firebase (Auth, Firestore) with no custom server; all authorization enforced in Firestore security rules rather than in UI code. Riverpod supplies dependency injection and reactive state. Supabase Storage sits behind a `StorageService` interface so the file provider can be swapped without touching feature code.

**Tech Stack:** Flutter 3.44.2 · Dart 3.12.2 · flutter_riverpod · go_router · firebase_core / firebase_auth / cloud_firestore · supabase_flutter · shared_preferences · fake_cloud_firestore + firebase_auth_mocks + mocktail (tests) · Firebase Emulator Suite + @firebase/rules-unit-testing (rules tests)

**Spec:** `docs/superpowers/specs/2026-08-12-ethesishub-design.md`

## Status

- **Task 1 — COMPLETE.** Dependencies installed, counter demo cleared, `lib/app.dart` created.
- **Task 2 — COMPLETE.** Firebase project (Spark) with Auth and Firestore, FlutterFire configured for Android and web, Supabase project and `thesis-documents` bucket, `AppConfig` populated, `main.dart` wired, `sharedPrefsProvider` created.
- **Git initialized** at commit `d73be05`. Commit steps in every task are live and must be executed.
- **Riverpod pinned to 2.6.1.** `flutter pub add` originally resolved 3.4.2, whose API differs from this plan's code. Do **not** upgrade Riverpod while executing this plan.
- **Known upstream deprecation:** `supabase_flutter` 2.17.1 deprecates `anonKey` in favour of `publishableKey` (`lib/main.dart`). Harmless; fix opportunistically.

**Start at Task 3.**

**Scope:** This plan covers **only** the walking skeleton (spec §9.1). Modules M1–M6 each get their own plan, written when reached.

## Global Constraints

- Flutter SDK 3.44.2, Dart SDK constraint `^3.12.2` (already in `pubspec.yaml`)
- Targets: **Android and Web only**. No iOS, no desktop. `dart:io` must never be imported in `lib/` — it breaks the web build
- Firebase **Spark (free) plan**: no Cloud Functions, no Firebase Storage, no server-side triggers
- **`role` is never a client-supplied value at registration.** Registration always writes `role: 'student'`
- Institutional domain restriction **enabled**: `isufst.edu.ph`, via `AppConfig.enforceInstitutionalDomain`
- Account roles are exactly: `student`, `faculty`, `coordinator`, `dean` (thesis positions `adviser`/`panelist` are per-thesis and out of scope for this plan)
- Firestore rules are **deny-by-default**; no rule may be left in test mode
- `auditLogs` is create-only; never update, never delete
- All model classes in `lib/data/models/` must be pure Dart — no `firebase` imports — so they are testable without emulators

**Exit criteria for the whole plan (spec §9.1):** register a student; promote a faculty member by invite; sign in as each of the four account types and reach four visibly distinct dashboards; confirm rules refuse a student writing `role: 'dean'`.

---

## File Structure

**Created in `lib/`:**

| File | Responsibility |
|---|---|
| `main.dart` | Bootstrap: Firebase init, Supabase init, SharedPreferences load, `ProviderScope` overrides |
| `app.dart` | `MaterialApp.router`, theme wiring |
| `core/config/app_config.dart` | Compile-time flags (domain enforcement, institutional domain, Supabase bucket) |
| `core/config/email_validator.dart` | Registration email validation |
| `core/theme/app_theme.dart` | Light and dark `ThemeData` |
| `core/routing/app_router.dart` | `GoRouter` with role-guard redirect |
| `core/widgets/responsive_scaffold.dart` | Bottom nav (mobile) / nav rail (web) |
| `data/models/user_role.dart` | `UserRole` enum + string mapping |
| `data/models/app_user.dart` | `AppUser` model, pure Dart |
| `data/models/faculty_mode.dart` | `FacultyMode` enum |
| `data/services/auth_service.dart` | Thin wrapper over `FirebaseAuth` |
| `data/services/audit_service.dart` | Writes `auditLogs` |
| `data/services/storage_service.dart` | `StorageService` interface + `StoredFile` |
| `data/services/supabase_storage_service.dart` | Supabase implementation |
| `data/repositories/user_repository.dart` | `users` + `facultyInvites` reads/writes |
| `features/auth/*` | Register, login, verify-email screens |
| `features/dashboard/*` | Four role dashboards + faculty mode switch |
| `providers/*.dart` | Riverpod providers |

**Created at repo root:** `firestore.rules`, `firebase.json`, `.firebaserc`, `rules-test/` (Node rules tests).

---

## Task 1: Repository hygiene and dependencies

Clears the Flutter counter demo and installs every package the skeleton needs, so no later task is blocked on a missing dependency.

**Files:**
- Create: `.gitignore` additions, `lib/app.dart`
- Modify: `lib/main.dart`, `test/widget_test.dart`
- Delete: nothing

**Interfaces:**
- Consumes: nothing
- Produces: `EThesisHubApp` — a `StatelessWidget` returning a `MaterialApp`; replaced in Task 12 by the router version

- [ ] **Step 1: Initialise version control**

Strongly recommended (spec §12 item 4). Skip only if you have accepted the risk of no rollback.

```bash
cd "c:/Users/marks/Downloads/Lockin/ethesishub"
git init
git add -A
git commit -m "chore: flutter scaffold baseline"
```

- [ ] **Step 2: Write the failing test**

Replace the entire contents of `test/widget_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ethesishub/app.dart';

void main() {
  testWidgets('app builds and shows its title', (tester) async {
    await tester.pumpWidget(const EThesisHubApp());
    expect(find.text('eThesisHub'), findsOneWidget);
  });
}
```

- [ ] **Step 3: Run test to verify it fails**

Run: `flutter test test/widget_test.dart`
Expected: FAIL — `Target of URI doesn't exist: 'package:ethesishub/app.dart'`

- [ ] **Step 4: Create `lib/app.dart`**

```dart
import 'package:flutter/material.dart';

class EThesisHubApp extends StatelessWidget {
  const EThesisHubApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      title: 'eThesisHub',
      home: Scaffold(body: Center(child: Text('eThesisHub'))),
    );
  }
}
```

- [ ] **Step 5: Replace `lib/main.dart`**

```dart
import 'package:flutter/material.dart';
import 'package:ethesishub/app.dart';

void main() {
  runApp(const EThesisHubApp());
}
```

- [ ] **Step 6: Run test to verify it passes**

Run: `flutter test test/widget_test.dart`
Expected: PASS

- [ ] **Step 7: Install dependencies**

```bash
flutter pub add firebase_core firebase_auth cloud_firestore flutter_riverpod go_router supabase_flutter shared_preferences
flutter pub add dev:fake_cloud_firestore dev:firebase_auth_mocks dev:mocktail
```

- [ ] **Step 8: Verify the project still analyses and builds**

Run: `flutter analyze && flutter test`
Expected: no analyzer errors, all tests pass

- [ ] **Step 9: Commit**

```bash
git add -A
git commit -m "chore: clear counter demo, add skeleton dependencies"
```

---

## Task 2: Firebase and Supabase project setup

Manual infrastructure. Nothing later can be verified until these exist. **This task is performed by a human — it requires browser logins and cannot be automated.**

**Files:**
- Create: `lib/firebase_options.dart` (generated), `.env` is *not* used — see Step 7
- Modify: `lib/main.dart`, `.gitignore`

**Interfaces:**
- Consumes: `EThesisHubApp` from Task 1
- Produces: initialised `Firebase` and `Supabase` singletons available to all later tasks

- [ ] **Step 1: Create the Firebase project**

1. Go to <https://console.firebase.google.com> and create a project named `ethesishub`
2. Disable Google Analytics (not needed, avoids extra consent screens)
3. Confirm the plan shows **Spark** — do not upgrade to Blaze

- [ ] **Step 2: Enable Authentication**

In the Firebase Console: **Build → Authentication → Get started → Sign-in method → Email/Password → Enable**. Leave "Email link (passwordless)" off.

- [ ] **Step 3: Create the Firestore database**

**Build → Firestore Database → Create database → Start in production mode** (not test mode — the Global Constraints forbid test-mode rules). Choose region `asia-southeast1`.

- [ ] **Step 4: Configure FlutterFire**

```bash
dart pub global activate flutterfire_cli
flutterfire configure --project=ethesishub --platforms=android,web
```

This writes `lib/firebase_options.dart` and `android/app/google-services.json`.

- [ ] **Step 5: Create the Supabase project and bucket**

1. Go to <https://supabase.com/dashboard>, create a project named `ethesishub`
2. **Storage → New bucket** → name `thesis-documents` → **Public bucket: on**
3. In bucket settings set **Allowed MIME types** to `application/pdf, application/vnd.openxmlformats-officedocument.wordprocessingml.document` and **File size limit** to `20MB`
4. From **Project Settings → API**, copy the **Project URL** and the **anon public** key

The anon key is designed to be published in clients and is safe to commit. The `service_role` key is not — never place it in this project.

- [ ] **Step 6: Record the Supabase credentials in config**

Create `lib/core/config/app_config.dart`:

```dart
class AppConfig {
  static const bool enforceInstitutionalDomain = true;
  static const String institutionalDomain = 'isufst.edu.ph';

  static const String supabaseUrl = 'PASTE_PROJECT_URL_HERE';
  static const String supabaseAnonKey = 'PASTE_ANON_KEY_HERE';
  static const String documentsBucket = 'thesis-documents';
}
```

Replace both `PASTE_` values with the real ones from Step 5.

- [ ] **Step 7: Wire initialisation into `main.dart`**

```dart
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:ethesishub/app.dart';
import 'package:ethesishub/core/config/app_config.dart';
import 'package:ethesishub/firebase_options.dart';
import 'package:ethesishub/providers/shared_prefs_provider.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  await Supabase.initialize(
    url: AppConfig.supabaseUrl,
    anonKey: AppConfig.supabaseAnonKey,
  );

  final prefs = await SharedPreferences.getInstance();

  runApp(
    ProviderScope(
      overrides: [sharedPrefsProvider.overrideWithValue(prefs)],
      child: const EThesisHubApp(),
    ),
  );
}
```

- [ ] **Step 8: Create the SharedPreferences provider**

Create `lib/providers/shared_prefs_provider.dart`:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Overridden in main() with the real instance, and in tests with a fake.
final sharedPrefsProvider = Provider<SharedPreferences>(
  (ref) => throw UnimplementedError('sharedPrefsProvider must be overridden'),
);
```

- [ ] **Step 9: Verify the app launches against real Firebase**

Run: `flutter run -d chrome`
Expected: the app window opens showing "eThesisHub" with no Firebase initialisation errors in the console.

- [ ] **Step 10: Commit**

```bash
git add -A
git commit -m "feat: initialise Firebase and Supabase"
```

---

## Task 3: UserRole and AppUser model

Pure-Dart domain types. No Firebase imports, so these test instantly without emulators.

**Files:**
- Create: `lib/data/models/user_role.dart`, `lib/data/models/app_user.dart`
- Test: `test/data/models/user_role_test.dart`, `test/data/models/app_user_test.dart`

**Interfaces:**
- Consumes: nothing
- Produces:
  - `enum UserRole { student, faculty, coordinator, dean }` with `String get value` and `static UserRole? tryParse(String?)`
  - `class AppUser` with fields `uid, fullName, email, role, college, program, specialization, active, createdAt, createdBy`; `AppUser.fromMap(String uid, Map<String, dynamic> map)`; `Map<String, dynamic> toMap()`; `bool get isFaculty`

- [ ] **Step 1: Write the failing test for UserRole**

Create `test/data/models/user_role_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:ethesishub/data/models/user_role.dart';

void main() {
  test('value returns the stored string form', () {
    expect(UserRole.coordinator.value, 'coordinator');
  });

  test('tryParse maps known strings', () {
    expect(UserRole.tryParse('dean'), UserRole.dean);
    expect(UserRole.tryParse('student'), UserRole.student);
  });

  test('tryParse returns null for unknown or missing values', () {
    expect(UserRole.tryParse('administrator'), isNull);
    expect(UserRole.tryParse(null), isNull);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/data/models/user_role_test.dart`
Expected: FAIL — `Target of URI doesn't exist`

- [ ] **Step 3: Implement UserRole**

Create `lib/data/models/user_role.dart`:

```dart
enum UserRole {
  student,
  faculty,
  coordinator,
  dean;

  String get value => name;

  static UserRole? tryParse(String? raw) {
    if (raw == null) return null;
    for (final role in UserRole.values) {
      if (role.name == raw) return role;
    }
    return null;
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/data/models/user_role_test.dart`
Expected: PASS

- [ ] **Step 5: Write the failing test for AppUser**

Create `test/data/models/app_user_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:ethesishub/data/models/app_user.dart';
import 'package:ethesishub/data/models/user_role.dart';

void main() {
  final createdAt = DateTime.utc(2026, 8, 12);

  test('fromMap reads all fields', () {
    final user = AppUser.fromMap('uid-1', {
      'fullName': 'Karl Joshua P. Vargas',
      'email': 'kjvargas@isufst.edu.ph',
      'role': 'student',
      'college': 'CICT',
      'program': 'BSIT',
      'specialization': null,
      'active': true,
      'createdAt': createdAt,
      'createdBy': null,
    });

    expect(user.uid, 'uid-1');
    expect(user.fullName, 'Karl Joshua P. Vargas');
    expect(user.role, UserRole.student);
    expect(user.program, 'BSIT');
    expect(user.active, isTrue);
  });

  test('fromMap defaults an unknown role to student', () {
    final user = AppUser.fromMap('uid-2', {
      'fullName': 'Someone',
      'email': 'someone@isufst.edu.ph',
      'role': 'superadmin',
      'active': true,
      'createdAt': createdAt,
    });

    expect(user.role, UserRole.student);
  });

  test('toMap round-trips through fromMap', () {
    final original = AppUser(
      uid: 'uid-3',
      fullName: 'Dr. Reyes',
      email: 'reyes@isufst.edu.ph',
      role: UserRole.faculty,
      college: 'CICT',
      active: true,
      createdAt: createdAt,
    );

    final restored = AppUser.fromMap('uid-3', original.toMap());
    expect(restored.email, original.email);
    expect(restored.role, UserRole.faculty);
    expect(restored.college, 'CICT');
  });

  test('isFaculty is true for faculty, coordinator and dean', () {
    AppUser build(UserRole role) => AppUser(
          uid: 'u',
          fullName: 'n',
          email: 'e@isufst.edu.ph',
          role: role,
          active: true,
          createdAt: createdAt,
        );

    expect(build(UserRole.student).isFaculty, isFalse);
    expect(build(UserRole.faculty).isFaculty, isTrue);
    expect(build(UserRole.coordinator).isFaculty, isTrue);
    expect(build(UserRole.dean).isFaculty, isTrue);
  });
}
```

- [ ] **Step 6: Run test to verify it fails**

Run: `flutter test test/data/models/app_user_test.dart`
Expected: FAIL — `Target of URI doesn't exist`

- [ ] **Step 7: Implement AppUser**

Create `lib/data/models/app_user.dart`:

```dart
import 'package:ethesishub/data/models/user_role.dart';

class AppUser {
  const AppUser({
    required this.uid,
    required this.fullName,
    required this.email,
    required this.role,
    required this.active,
    required this.createdAt,
    this.college,
    this.program,
    this.specialization,
    this.createdBy,
  });

  final String uid;
  final String fullName;
  final String email;
  final UserRole role;
  final bool active;
  final DateTime createdAt;
  final String? college;
  final String? program;
  final String? specialization;
  final String? createdBy;

  /// True for every role that may hold a thesis position or approve work.
  bool get isFaculty => role != UserRole.student;

  factory AppUser.fromMap(String uid, Map<String, dynamic> map) {
    return AppUser(
      uid: uid,
      fullName: map['fullName'] as String? ?? '',
      email: map['email'] as String? ?? '',
      role: UserRole.tryParse(map['role'] as String?) ?? UserRole.student,
      college: map['college'] as String?,
      program: map['program'] as String?,
      specialization: map['specialization'] as String?,
      active: map['active'] as bool? ?? true,
      createdAt: map['createdAt'] as DateTime? ?? DateTime.now().toUtc(),
      createdBy: map['createdBy'] as String?,
    );
  }

  Map<String, dynamic> toMap() => {
        'fullName': fullName,
        'email': email,
        'role': role.value,
        'college': college,
        'program': program,
        'specialization': specialization,
        'active': active,
        'createdAt': createdAt,
        'createdBy': createdBy,
      };
}
```

Note the deliberate default: an unrecognised role degrades to `student`, the least-privileged role. Never default to anything higher.

- [ ] **Step 8: Run test to verify it passes**

Run: `flutter test test/data/models/`
Expected: PASS, all tests

- [ ] **Step 9: Commit**

```bash
git add -A
git commit -m "feat: add UserRole and AppUser domain models"
```

---

## Task 4: Email validation and institutional domain rule

**Files:**
- Create: `lib/core/config/email_validator.dart`
- Modify: `lib/core/config/app_config.dart` (created in Task 2 — no change needed if already present)
- Test: `test/core/config/email_validator_test.dart`

**Interfaces:**
- Consumes: `AppConfig.enforceInstitutionalDomain`, `AppConfig.institutionalDomain`
- Produces: `EmailValidator.validateForRegistration(String email)` returning `String?` — an error message, or `null` when valid

- [ ] **Step 1: Write the failing test**

Create `test/core/config/email_validator_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:ethesishub/core/config/email_validator.dart';

void main() {
  test('accepts a well-formed institutional address', () {
    expect(
      EmailValidator.validateForRegistration('kjvargas@isufst.edu.ph'),
      isNull,
    );
  });

  test('rejects an empty address', () {
    expect(EmailValidator.validateForRegistration(''), isNotNull);
  });

  test('rejects a malformed address', () {
    expect(EmailValidator.validateForRegistration('not-an-email'), isNotNull);
  });

  test('rejects a non-institutional domain while enforcement is on', () {
    final error = EmailValidator.validateForRegistration('someone@gmail.com');
    expect(error, isNotNull);
    expect(error, contains('isufst.edu.ph'));
  });

  test('is case-insensitive about the domain', () {
    expect(
      EmailValidator.validateForRegistration('Someone@ISUFST.EDU.PH'),
      isNull,
    );
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/core/config/email_validator_test.dart`
Expected: FAIL — `Target of URI doesn't exist`

- [ ] **Step 3: Implement the validator**

Create `lib/core/config/email_validator.dart`:

```dart
import 'package:ethesishub/core/config/app_config.dart';

class EmailValidator {
  static final RegExp _pattern = RegExp(r'^[\w.+-]+@[\w-]+(\.[\w-]+)+$');

  /// Returns an error message, or null when the address may register.
  static String? validateForRegistration(String email) {
    final trimmed = email.trim();
    if (trimmed.isEmpty) return 'Email is required.';
    if (!_pattern.hasMatch(trimmed)) return 'Enter a valid email address.';

    if (AppConfig.enforceInstitutionalDomain) {
      final domain = trimmed.split('@').last.toLowerCase();
      if (domain != AppConfig.institutionalDomain) {
        return 'Use your ${AppConfig.institutionalDomain} account to register.';
      }
    }
    return null;
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/core/config/email_validator_test.dart`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "feat: enforce institutional email domain at registration"
```

---

## Task 5: AuthService

A thin, injectable wrapper over `FirebaseAuth` so screens never touch the SDK directly and tests can substitute `firebase_auth_mocks`.

**Files:**
- Create: `lib/data/services/auth_service.dart`
- Test: `test/data/services/auth_service_test.dart`

**Interfaces:**
- Consumes: `FirebaseAuth` (injected)
- Produces: `AuthService` with `Stream<User?> authStateChanges()`, `User? get currentUser`, `Future<UserCredential> register({required String email, required String password})`, `Future<UserCredential> signIn({required String email, required String password})`, `Future<void> sendEmailVerification()`, `Future<void> sendPasswordReset(String email)`, `Future<void> signOut()`

- [ ] **Step 1: Write the failing test**

Create `test/data/services/auth_service_test.dart`:

```dart
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ethesishub/data/services/auth_service.dart';

void main() {
  test('register creates a signed-in user', () async {
    final auth = MockFirebaseAuth();
    final service = AuthService(auth);

    final credential = await service.register(
      email: 'kjvargas@isufst.edu.ph',
      password: 'Str0ngPass!',
    );

    expect(credential.user, isNotNull);
    expect(service.currentUser, isNotNull);
  });

  test('signIn returns a credential for an existing user', () async {
    final auth = MockFirebaseAuth(
      mockUser: MockUser(
        uid: 'uid-1',
        email: 'kjvargas@isufst.edu.ph',
        isEmailVerified: true,
      ),
    );
    final service = AuthService(auth);

    final credential = await service.signIn(
      email: 'kjvargas@isufst.edu.ph',
      password: 'Str0ngPass!',
    );

    expect(credential.user!.uid, 'uid-1');
  });

  test('signOut clears the current user', () async {
    final auth = MockFirebaseAuth(signedIn: true);
    final service = AuthService(auth);

    expect(service.currentUser, isNotNull);
    await service.signOut();
    expect(service.currentUser, isNull);
  });

  test('authStateChanges emits on sign out', () async {
    final auth = MockFirebaseAuth(signedIn: true);
    final service = AuthService(auth);

    expectLater(service.authStateChanges(), emitsThrough(isNull));
    await service.signOut();
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/data/services/auth_service_test.dart`
Expected: FAIL — `Target of URI doesn't exist`

- [ ] **Step 3: Implement AuthService**

Create `lib/data/services/auth_service.dart`:

```dart
import 'package:firebase_auth/firebase_auth.dart';

class AuthService {
  AuthService(this._auth);

  final FirebaseAuth _auth;

  Stream<User?> authStateChanges() => _auth.authStateChanges();

  User? get currentUser => _auth.currentUser;

  Future<UserCredential> register({
    required String email,
    required String password,
  }) {
    return _auth.createUserWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );
  }

  Future<UserCredential> signIn({
    required String email,
    required String password,
  }) {
    return _auth.signInWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );
  }

  Future<void> sendEmailVerification() async {
    await _auth.currentUser?.sendEmailVerification();
  }

  Future<void> sendPasswordReset(String email) {
    return _auth.sendPasswordResetEmail(email: email.trim());
  }

  Future<void> signOut() => _auth.signOut();
}
```

Note there is **no `role` parameter anywhere in this class**. Role is not something a caller can express.

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/data/services/auth_service_test.dart`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "feat: add AuthService wrapper over FirebaseAuth"
```

---

## Task 6: UserRepository with invite-based promotion

Owns the `users` and `facultyInvites` collections, including the promotion path that turns a registered student into faculty.

**Files:**
- Create: `lib/data/repositories/user_repository.dart`
- Test: `test/data/repositories/user_repository_test.dart`

**Interfaces:**
- Consumes: `FirebaseFirestore` (injected), `AppUser`, `UserRole`
- Produces: `UserRepository` with:
  - `Future<void> createStudentProfile({required String uid, required String fullName, required String email, String? college, String? program})`
  - `Future<AppUser?> fetchUser(String uid)`
  - `Stream<AppUser?> watchUser(String uid)`
  - `Future<UserRole?> fetchInviteRole(String email)`
  - `Future<UserRole?> promoteFromInvite({required String uid, required String email})` — returns the new role, or `null` when no invite exists
  - `Future<void> createInvite({required String email, required UserRole role, required String invitedBy})`

- [ ] **Step 1: Write the failing test**

Create `test/data/repositories/user_repository_test.dart`:

```dart
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ethesishub/data/models/user_role.dart';
import 'package:ethesishub/data/repositories/user_repository.dart';

void main() {
  late FakeFirebaseFirestore db;
  late UserRepository repo;

  setUp(() {
    db = FakeFirebaseFirestore();
    repo = UserRepository(db);
  });

  test('createStudentProfile always writes the student role', () async {
    await repo.createStudentProfile(
      uid: 'uid-1',
      fullName: 'Karl Joshua P. Vargas',
      email: 'kjvargas@isufst.edu.ph',
      program: 'BSIT',
    );

    final user = await repo.fetchUser('uid-1');
    expect(user!.role, UserRole.student);
    expect(user.program, 'BSIT');
  });

  test('fetchUser returns null for an unknown uid', () async {
    expect(await repo.fetchUser('missing'), isNull);
  });

  test('fetchInviteRole finds an invite by lowercased email', () async {
    await repo.createInvite(
      email: 'Reyes@ISUFST.edu.ph',
      role: UserRole.faculty,
      invitedBy: 'coordinator-uid',
    );

    expect(
      await repo.fetchInviteRole('reyes@isufst.edu.ph'),
      UserRole.faculty,
    );
  });

  test('promoteFromInvite upgrades the user and consumes the invite', () async {
    await repo.createStudentProfile(
      uid: 'uid-2',
      fullName: 'Dr. Reyes',
      email: 'reyes@isufst.edu.ph',
    );
    await repo.createInvite(
      email: 'reyes@isufst.edu.ph',
      role: UserRole.coordinator,
      invitedBy: 'seed',
    );

    final newRole = await repo.promoteFromInvite(
      uid: 'uid-2',
      email: 'reyes@isufst.edu.ph',
    );

    expect(newRole, UserRole.coordinator);
    expect((await repo.fetchUser('uid-2'))!.role, UserRole.coordinator);
    expect(await repo.fetchInviteRole('reyes@isufst.edu.ph'), isNull);
  });

  test('promoteFromInvite is a no-op without an invite', () async {
    await repo.createStudentProfile(
      uid: 'uid-3',
      fullName: 'Student',
      email: 'student@isufst.edu.ph',
    );

    final newRole = await repo.promoteFromInvite(
      uid: 'uid-3',
      email: 'student@isufst.edu.ph',
    );

    expect(newRole, isNull);
    expect((await repo.fetchUser('uid-3'))!.role, UserRole.student);
  });

  test('watchUser emits updates', () async {
    await repo.createStudentProfile(
      uid: 'uid-4',
      fullName: 'Watched',
      email: 'watched@isufst.edu.ph',
    );

    expectLater(
      repo.watchUser('uid-4').map((u) => u?.fullName),
      emits('Watched'),
    );
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/data/repositories/user_repository_test.dart`
Expected: FAIL — `Target of URI doesn't exist`

- [ ] **Step 3: Implement UserRepository**

Create `lib/data/repositories/user_repository.dart`:

```dart
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
    return UserRole.tryParse(snapshot.data()!['role'] as String?);
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
    });
  }

  /// Applies a pending invite, returning the granted role or null if none.
  Future<UserRole?> promoteFromInvite({
    required String uid,
    required String email,
  }) async {
    final role = await fetchInviteRole(email);
    if (role == null) return null;

    await _users.doc(uid).update({'role': role.value});
    await _invites.doc(normalise(email)).delete();
    return role;
  }

  AppUser? _toUser(String uid, Map<String, dynamic>? data) {
    if (data == null) return null;
    final raw = Map<String, dynamic>.from(data);
    final createdAt = raw['createdAt'];
    raw['createdAt'] =
        createdAt is Timestamp ? createdAt.toDate() : DateTime.now().toUtc();
    return AppUser.fromMap(uid, raw);
  }
}
```

The `_toUser` helper is where `Timestamp` becomes `DateTime`, keeping `AppUser` free of Firebase imports as the Global Constraints require.

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/data/repositories/user_repository_test.dart`
Expected: PASS, all six tests

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "feat: add UserRepository with invite-based faculty promotion"
```

---

## Task 7: Riverpod providers for auth and current user

**Files:**
- Create: `lib/providers/auth_providers.dart`
- Test: `test/providers/auth_providers_test.dart`

**Interfaces:**
- Consumes: `AuthService`, `UserRepository`, `AppUser`
- Produces:
  - `firebaseAuthProvider` → `FirebaseAuth`
  - `firestoreProvider` → `FirebaseFirestore`
  - `authServiceProvider` → `AuthService`
  - `userRepositoryProvider` → `UserRepository`
  - `authStateProvider` → `StreamProvider<User?>`
  - `currentUserProvider` → `StreamProvider<AppUser?>` (null when signed out)

- [ ] **Step 1: Write the failing test**

Create `test/providers/auth_providers_test.dart`:

```dart
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ethesishub/data/models/user_role.dart';
import 'package:ethesishub/data/repositories/user_repository.dart';
import 'package:ethesishub/providers/auth_providers.dart';

void main() {
  test('currentUserProvider resolves the profile of the signed-in user',
      () async {
    final db = FakeFirebaseFirestore();
    await UserRepository(db).createStudentProfile(
      uid: 'uid-1',
      fullName: 'Karl Joshua P. Vargas',
      email: 'kjvargas@isufst.edu.ph',
    );

    final container = ProviderContainer(
      overrides: [
        firestoreProvider.overrideWithValue(db),
        firebaseAuthProvider.overrideWithValue(
          MockFirebaseAuth(
            signedIn: true,
            mockUser: MockUser(
              uid: 'uid-1',
              email: 'kjvargas@isufst.edu.ph',
              isEmailVerified: true,
            ),
          ),
        ),
      ],
    );
    addTearDown(container.dispose);

    final user = await container.read(currentUserProvider.future);
    expect(user, isNotNull);
    expect(user!.role, UserRole.student);
  });

  test('currentUserProvider is null when signed out', () async {
    final container = ProviderContainer(
      overrides: [
        firestoreProvider.overrideWithValue(FakeFirebaseFirestore()),
        firebaseAuthProvider.overrideWithValue(MockFirebaseAuth()),
      ],
    );
    addTearDown(container.dispose);

    expect(await container.read(currentUserProvider.future), isNull);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/providers/auth_providers_test.dart`
Expected: FAIL — `Target of URI doesn't exist`

- [ ] **Step 3: Implement the providers**

Create `lib/providers/auth_providers.dart`:

```dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ethesishub/data/models/app_user.dart';
import 'package:ethesishub/data/repositories/user_repository.dart';
import 'package:ethesishub/data/services/auth_service.dart';

final firebaseAuthProvider =
    Provider<FirebaseAuth>((ref) => FirebaseAuth.instance);

final firestoreProvider =
    Provider<FirebaseFirestore>((ref) => FirebaseFirestore.instance);

final authServiceProvider = Provider<AuthService>(
  (ref) => AuthService(ref.watch(firebaseAuthProvider)),
);

final userRepositoryProvider = Provider<UserRepository>(
  (ref) => UserRepository(ref.watch(firestoreProvider)),
);

final authStateProvider = StreamProvider<User?>(
  (ref) => ref.watch(authServiceProvider).authStateChanges(),
);

/// The signed-in user's profile, or null when signed out.
final currentUserProvider = StreamProvider<AppUser?>((ref) {
  final authState = ref.watch(authStateProvider).value;
  if (authState == null) return Stream.value(null);
  return ref.watch(userRepositoryProvider).watchUser(authState.uid);
});
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/providers/auth_providers_test.dart`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "feat: add Riverpod providers for auth and current user"
```

---

## Task 8: Firestore security rules and rules tests

The security core. This is the task that proves a student cannot become a dean.

**Files:**
- Create: `firestore.rules`, `firebase.json`, `.firebaserc`, `rules-test/package.json`, `rules-test/rules.test.js`
- Test: `rules-test/rules.test.js` (Node, runs against the Firebase Emulator Suite)

**Interfaces:**
- Consumes: collection shapes from Tasks 3 and 6
- Produces: deployed rules governing `users`, `facultyInvites`, `auditLogs`

- [ ] **Step 1: Install the Firebase CLI and emulator**

```bash
npm install -g firebase-tools
firebase login
```

- [ ] **Step 2: Create `firebase.json` at the repo root**

```json
{
  "firestore": {
    "rules": "firestore.rules"
  },
  "emulators": {
    "firestore": { "port": 8080 },
    "ui": { "enabled": true }
  }
}
```

- [ ] **Step 3: Create `.firebaserc` at the repo root**

```json
{
  "projects": {
    "default": "ethesishub"
  }
}
```

- [ ] **Step 4: Write the failing rules test**

Create `rules-test/package.json`:

```json
{
  "name": "ethesishub-rules-test",
  "private": true,
  "type": "module",
  "scripts": {
    "test": "firebase emulators:exec --only firestore \"node --test rules.test.js\""
  },
  "devDependencies": {
    "@firebase/rules-unit-testing": "^3.0.4",
    "firebase": "^10.12.0"
  }
}
```

Create `rules-test/rules.test.js`:

```javascript
import { readFileSync } from "node:fs";
import test from "node:test";
import assert from "node:assert";
import {
  initializeTestEnvironment,
  assertFails,
  assertSucceeds,
} from "@firebase/rules-unit-testing";
import { doc, getDoc, setDoc, updateDoc, deleteDoc } from "firebase/firestore";

const env = await initializeTestEnvironment({
  projectId: "ethesishub-rules-test",
  firestore: {
    rules: readFileSync("../firestore.rules", "utf8"),
    host: "127.0.0.1",
    port: 8080,
  },
});

const student = env
  .authenticatedContext("student-uid", {
    email: "student@isufst.edu.ph",
    email_verified: true,
  })
  .firestore();

test("a new account may only be created with the student role", async () => {
  await assertSucceeds(
    setDoc(doc(student, "users/student-uid"), {
      fullName: "A Student",
      email: "student@isufst.edu.ph",
      role: "student",
      active: true,
    })
  );
});

test("a new account may NOT be created with an elevated role", async () => {
  const attacker = env
    .authenticatedContext("attacker-uid", {
      email: "attacker@isufst.edu.ph",
      email_verified: true,
    })
    .firestore();

  await assertFails(
    setDoc(doc(attacker, "users/attacker-uid"), {
      fullName: "Attacker",
      email: "attacker@isufst.edu.ph",
      role: "dean",
      active: true,
    })
  );
});

test("a student may NOT promote themselves without an invite", async () => {
  await assertFails(updateDoc(doc(student, "users/student-uid"), { role: "dean" }));
});

test("a student MAY promote themselves when a matching invite exists", async () => {
  await env.withSecurityRulesDisabled(async (ctx) => {
    await setDoc(doc(ctx.firestore(), "facultyInvites/invited@isufst.edu.ph"), {
      role: "faculty",
      invitedBy: "seed",
    });
    await setDoc(doc(ctx.firestore(), "users/invited-uid"), {
      fullName: "Invited",
      email: "invited@isufst.edu.ph",
      role: "student",
      active: true,
    });
  });

  const invited = env
    .authenticatedContext("invited-uid", {
      email: "invited@isufst.edu.ph",
      email_verified: true,
    })
    .firestore();

  await assertSucceeds(
    updateDoc(doc(invited, "users/invited-uid"), { role: "faculty" })
  );
});

test("an invited user may NOT claim a role higher than their invite", async () => {
  await env.withSecurityRulesDisabled(async (ctx) => {
    await setDoc(doc(ctx.firestore(), "facultyInvites/greedy@isufst.edu.ph"), {
      role: "faculty",
      invitedBy: "seed",
    });
    await setDoc(doc(ctx.firestore(), "users/greedy-uid"), {
      fullName: "Greedy",
      email: "greedy@isufst.edu.ph",
      role: "student",
      active: true,
    });
  });

  const greedy = env
    .authenticatedContext("greedy-uid", {
      email: "greedy@isufst.edu.ph",
      email_verified: true,
    })
    .firestore();

  await assertFails(
    updateDoc(doc(greedy, "users/greedy-uid"), { role: "dean" })
  );
});

test("a user may not read an invite belonging to someone else", async () => {
  await env.withSecurityRulesDisabled(async (ctx) => {
    await setDoc(doc(ctx.firestore(), "facultyInvites/other@isufst.edu.ph"), {
      role: "dean",
      invitedBy: "seed",
    });
  });

  await assertFails(
    getDoc(doc(student, "facultyInvites/other@isufst.edu.ph"))
  );
});

test("audit logs may be created but never deleted", async () => {
  await assertSucceeds(
    setDoc(doc(student, "auditLogs/log-1"), {
      actorUid: "student-uid",
      action: "login",
      targetType: "session",
      targetId: "student-uid",
    })
  );
  await assertFails(deleteDoc(doc(student, "auditLogs/log-1")));
});

test("unauthenticated access is denied", async () => {
  const anon = env.unauthenticatedContext().firestore();
  await assertFails(getDoc(doc(anon, "users/student-uid")));
});

test.after(async () => {
  await env.cleanup();
});
```

- [ ] **Step 5: Install test dependencies and run to verify failure**

```bash
cd rules-test && npm install && npm test
```

Expected: FAIL — `firestore.rules` does not exist yet.

- [ ] **Step 6: Write the rules**

Create `firestore.rules` at the repo root:

```javascript
rules_version = '2';

service cloud.firestore {
  match /databases/{database}/documents {

    function signedIn() {
      return request.auth != null;
    }

    function verified() {
      return signedIn() && request.auth.token.email_verified == true;
    }

    function myEmail() {
      return request.auth.token.email;
    }

    function myRole() {
      return get(/databases/$(database)/documents/users/$(request.auth.uid)).data.role;
    }

    function isCoordinator() {
      return signedIn() && myRole() == 'coordinator';
    }

    function isDean() {
      return signedIn() && myRole() == 'dean';
    }

    function invitedRoleFor(email) {
      return get(/databases/$(database)/documents/facultyInvites/$(email)).data.role;
    }

    function hasInvite(email) {
      return exists(/databases/$(database)/documents/facultyInvites/$(email));
    }

    // Only the listed fields may differ between the stored and incoming doc.
    function onlyChanged(fields) {
      return request.resource.data.diff(resource.data).affectedKeys()
             .hasOnly(fields);
    }

    match /users/{uid} {
      allow get: if signedIn() &&
                 (request.auth.uid == uid || isCoordinator() || isDean());
      allow list: if isCoordinator() || isDean();

      // Self-registration: student role only, and only for yourself.
      allow create: if signedIn()
                    && request.auth.uid == uid
                    && request.resource.data.role == 'student'
                    && request.resource.data.email == myEmail();

      // Profile edits by the owner, but never the role.
      allow update: if signedIn()
                    && request.auth.uid == uid
                    && onlyChanged(['fullName', 'college', 'program', 'specialization']);

      // Invite promotion: only to exactly the invited role, for your own email.
      allow update: if verified()
                    && request.auth.uid == uid
                    && onlyChanged(['role'])
                    && hasInvite(myEmail())
                    && request.resource.data.role == invitedRoleFor(myEmail());

      // Coordinators administer accounts.
      allow update: if isCoordinator();

      allow delete: if false;
    }

    match /facultyInvites/{email} {
      // You may read only your own invite; the collection is never listable.
      allow get: if signedIn() && myEmail() == email;
      allow list: if isCoordinator();
      allow create, update: if isCoordinator();
      // The invitee consumes their own invite after promotion.
      allow delete: if isCoordinator() || (verified() && myEmail() == email);
    }

    match /auditLogs/{logId} {
      allow create: if signedIn()
                    && request.resource.data.actorUid == request.auth.uid;
      allow get, list: if isCoordinator() || isDean();
      allow update, delete: if false;
    }

    // Deny-by-default for everything not matched above.
    match /{document=**} {
      allow read, write: if false;
    }
  }
}
```

- [ ] **Step 7: Run the rules tests to verify they pass**

```bash
cd rules-test && npm test
```

Expected: PASS, all eight tests. The critical ones are *"may NOT be created with an elevated role"*, *"may NOT promote themselves without an invite"*, and *"may NOT claim a role higher than their invite"*.

- [ ] **Step 8: Deploy the rules**

```bash
firebase deploy --only firestore:rules
```

Expected: `Deploy complete!`

- [ ] **Step 9: Commit**

```bash
git add -A
git commit -m "feat: add deny-by-default Firestore rules with rules tests"
```

---

## Task 9: Registration screen

**Files:**
- Create: `lib/features/auth/register_screen.dart`, `lib/features/auth/registration_controller.dart`
- Test: `test/features/auth/register_screen_test.dart`

**Interfaces:**
- Consumes: `authServiceProvider`, `userRepositoryProvider`, `EmailValidator`
- Produces: `RegisterScreen` (route `/register`); `RegistrationController` with `Future<String?> submit({required String fullName, required String email, required String password, String? program})` returning an error message or `null` on success

- [ ] **Step 1: Write the failing test**

Create `test/features/auth/register_screen_test.dart`:

```dart
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ethesishub/features/auth/register_screen.dart';
import 'package:ethesishub/providers/auth_providers.dart';

Widget wrap(Widget child, {required FakeFirebaseFirestore db}) {
  return ProviderScope(
    overrides: [
      firestoreProvider.overrideWithValue(db),
      firebaseAuthProvider.overrideWithValue(MockFirebaseAuth()),
    ],
    child: MaterialApp(home: child),
  );
}

void main() {
  testWidgets('has no role selector anywhere on the form', (tester) async {
    await tester.pumpWidget(wrap(const RegisterScreen(),
        db: FakeFirebaseFirestore()));

    expect(find.byType(DropdownButtonFormField<String>), findsNothing);
    expect(find.textContaining('Role'), findsNothing);
    expect(find.textContaining('Faculty'), findsNothing);
  });

  testWidgets('rejects a non-institutional email', (tester) async {
    await tester.pumpWidget(wrap(const RegisterScreen(),
        db: FakeFirebaseFirestore()));

    await tester.enterText(find.byKey(const Key('fullName')), 'Someone');
    await tester.enterText(find.byKey(const Key('email')), 'someone@gmail.com');
    await tester.enterText(find.byKey(const Key('password')), 'Str0ngPass!');
    await tester.tap(find.byKey(const Key('submit')));
    await tester.pumpAndSettle();

    expect(find.textContaining('isufst.edu.ph'), findsOneWidget);
  });

  testWidgets('creates a student profile on success', (tester) async {
    final db = FakeFirebaseFirestore();
    await tester.pumpWidget(wrap(const RegisterScreen(), db: db));

    await tester.enterText(find.byKey(const Key('fullName')), 'Karl Vargas');
    await tester.enterText(
        find.byKey(const Key('email')), 'kjvargas@isufst.edu.ph');
    await tester.enterText(find.byKey(const Key('password')), 'Str0ngPass!');
    await tester.tap(find.byKey(const Key('submit')));
    await tester.pumpAndSettle();

    final users = await db.collection('users').get();
    expect(users.docs, hasLength(1));
    expect(users.docs.first.data()['role'], 'student');
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/auth/register_screen_test.dart`
Expected: FAIL — `Target of URI doesn't exist`

- [ ] **Step 3: Implement the controller**

Create `lib/features/auth/registration_controller.dart`:

```dart
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ethesishub/core/config/email_validator.dart';
import 'package:ethesishub/providers/auth_providers.dart';

class RegistrationController {
  RegistrationController(this._ref);

  final Ref _ref;

  /// Returns an error message, or null when registration succeeded.
  Future<String?> submit({
    required String fullName,
    required String email,
    required String password,
    String? program,
  }) async {
    if (fullName.trim().isEmpty) return 'Full name is required.';
    final emailError = EmailValidator.validateForRegistration(email);
    if (emailError != null) return emailError;
    if (password.length < 8) {
      return 'Password must be at least 8 characters.';
    }

    final auth = _ref.read(authServiceProvider);
    final users = _ref.read(userRepositoryProvider);

    try {
      final credential = await auth.register(email: email, password: password);
      final uid = credential.user!.uid;

      await users.createStudentProfile(
        uid: uid,
        fullName: fullName,
        email: email,
        program: program,
      );
      await auth.sendEmailVerification();
      return null;
    } on FirebaseAuthException catch (e) {
      return switch (e.code) {
        'email-already-in-use' => 'That email is already registered.',
        'weak-password' => 'Choose a stronger password.',
        _ => 'Registration failed. Please try again.',
      };
    }
  }
}

final registrationControllerProvider = Provider<RegistrationController>(
  (ref) => RegistrationController(ref),
);
```

- [ ] **Step 4: Implement the screen**

Create `lib/features/auth/register_screen.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ethesishub/features/auth/registration_controller.dart';

class RegisterScreen extends ConsumerStatefulWidget {
  const RegisterScreen({super.key});

  @override
  ConsumerState<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends ConsumerState<RegisterScreen> {
  final _fullName = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _program = TextEditingController();

  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _fullName.dispose();
    _email.dispose();
    _password.dispose();
    _program.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _busy = true;
      _error = null;
    });

    final error = await ref.read(registrationControllerProvider).submit(
          fullName: _fullName.text,
          email: _email.text,
          password: _password.text,
          program: _program.text.trim().isEmpty ? null : _program.text.trim(),
        );

    if (!mounted) return;
    setState(() {
      _busy = false;
      _error = error;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Create account')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  key: const Key('fullName'),
                  controller: _fullName,
                  decoration: const InputDecoration(labelText: 'Full name'),
                ),
                const SizedBox(height: 12),
                TextField(
                  key: const Key('email'),
                  controller: _email,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(
                    labelText: 'Institutional email',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  key: const Key('program'),
                  controller: _program,
                  decoration: const InputDecoration(
                    labelText: 'Program (optional)',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  key: const Key('password'),
                  controller: _password,
                  obscureText: true,
                  decoration: const InputDecoration(labelText: 'Password'),
                ),
                const SizedBox(height: 20),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text(
                      _error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                FilledButton(
                  key: const Key('submit'),
                  onPressed: _busy ? null : _submit,
                  child: Text(_busy ? 'Creating…' : 'Create account'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
```

There is deliberately no role input. Accounts are students; faculty arrive by invite (Task 6).

- [ ] **Step 5: Run test to verify it passes**

Run: `flutter test test/features/auth/register_screen_test.dart`
Expected: PASS, all three tests

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "feat: add registration screen with no role selector"
```

---

## Task 10: Login screen and email verification gate

**Files:**
- Create: `lib/features/auth/login_screen.dart`, `lib/features/auth/verify_email_screen.dart`
- Test: `test/features/auth/login_screen_test.dart`

**Interfaces:**
- Consumes: `authServiceProvider`, `userRepositoryProvider`
- Produces: `LoginScreen` (route `/login`), `VerifyEmailScreen` (route `/verify-email`). On successful sign-in the login flow calls `UserRepository.promoteFromInvite` so an invited faculty member is upgraded at first login.

- [ ] **Step 1: Write the failing test**

Create `test/features/auth/login_screen_test.dart`:

```dart
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ethesishub/data/models/user_role.dart';
import 'package:ethesishub/data/repositories/user_repository.dart';
import 'package:ethesishub/data/services/auth_service.dart';
import 'package:ethesishub/features/auth/login_screen.dart';
import 'package:ethesishub/providers/auth_providers.dart';

/// Rejects every sign-in. Subclassing AuthService keeps this test independent
/// of firebase_auth_mocks' exception-injection API.
class FailingAuthService extends AuthService {
  FailingAuthService() : super(MockFirebaseAuth());

  @override
  Future<UserCredential> signIn({
    required String email,
    required String password,
  }) {
    throw FirebaseAuthException(code: 'wrong-password');
  }
}

void main() {
  testWidgets('shows an error when credentials are rejected', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          firestoreProvider.overrideWithValue(FakeFirebaseFirestore()),
          firebaseAuthProvider.overrideWithValue(MockFirebaseAuth()),
          authServiceProvider.overrideWithValue(FailingAuthService()),
        ],
        child: const MaterialApp(home: LoginScreen()),
      ),
    );

    await tester.enterText(
        find.byKey(const Key('email')), 'kjvargas@isufst.edu.ph');
    await tester.enterText(find.byKey(const Key('password')), 'wrong');
    await tester.tap(find.byKey(const Key('submit')));
    await tester.pumpAndSettle();

    expect(find.textContaining('Incorrect'), findsOneWidget);
  });

  testWidgets('promotes an invited user on first successful login',
      (tester) async {
    final db = FakeFirebaseFirestore();
    final repo = UserRepository(db);
    await repo.createStudentProfile(
      uid: 'uid-1',
      fullName: 'Dr. Reyes',
      email: 'reyes@isufst.edu.ph',
    );
    await repo.createInvite(
      email: 'reyes@isufst.edu.ph',
      role: UserRole.faculty,
      invitedBy: 'coordinator',
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          firestoreProvider.overrideWithValue(db),
          firebaseAuthProvider.overrideWithValue(
            MockFirebaseAuth(
              mockUser: MockUser(
                uid: 'uid-1',
                email: 'reyes@isufst.edu.ph',
                isEmailVerified: true,
              ),
            ),
          ),
        ],
        child: const MaterialApp(home: LoginScreen()),
      ),
    );

    await tester.enterText(
        find.byKey(const Key('email')), 'reyes@isufst.edu.ph');
    await tester.enterText(find.byKey(const Key('password')), 'Str0ngPass!');
    await tester.tap(find.byKey(const Key('submit')));
    await tester.pumpAndSettle();

    expect((await repo.fetchUser('uid-1'))!.role, UserRole.faculty);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/auth/login_screen_test.dart`
Expected: FAIL — `Target of URI doesn't exist`

- [ ] **Step 3: Implement LoginScreen**

Create `lib/features/auth/login_screen.dart`:

```dart
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ethesishub/providers/auth_providers.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();

  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      final auth = ref.read(authServiceProvider);
      final credential = await auth.signIn(
        email: _email.text,
        password: _password.text,
      );

      // Apply any pending faculty invite at first login.
      final user = credential.user;
      if (user != null && user.email != null) {
        await ref.read(userRepositoryProvider).promoteFromInvite(
              uid: user.uid,
              email: user.email!,
            );
      }
      if (!mounted) return;
      setState(() => _busy = false);
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = switch (e.code) {
          'wrong-password' || 'invalid-credential' =>
            'Incorrect email or password.',
          'user-not-found' => 'Incorrect email or password.',
          'too-many-requests' => 'Too many attempts. Try again later.',
          _ => 'Sign-in failed. Please try again.',
        };
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Sign in')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  key: const Key('email'),
                  controller: _email,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(labelText: 'Email'),
                ),
                const SizedBox(height: 12),
                TextField(
                  key: const Key('password'),
                  controller: _password,
                  obscureText: true,
                  decoration: const InputDecoration(labelText: 'Password'),
                ),
                const SizedBox(height: 20),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text(
                      _error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                FilledButton(
                  key: const Key('submit'),
                  onPressed: _busy ? null : _submit,
                  child: Text(_busy ? 'Signing in…' : 'Sign in'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 4: Implement VerifyEmailScreen**

Create `lib/features/auth/verify_email_screen.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ethesishub/providers/auth_providers.dart';

class VerifyEmailScreen extends ConsumerWidget {
  const VerifyEmailScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.read(authServiceProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Verify your email')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'We sent a verification link to your institutional email. '
                  'Open it, then return here and continue.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 20),
                FilledButton(
                  key: const Key('reload'),
                  onPressed: () async {
                    await auth.currentUser?.reload();
                  },
                  child: const Text("I've verified — continue"),
                ),
                TextButton(
                  key: const Key('resend'),
                  onPressed: auth.sendEmailVerification,
                  child: const Text('Resend link'),
                ),
                TextButton(
                  key: const Key('signout'),
                  onPressed: auth.signOut,
                  child: const Text('Sign out'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 5: Add the password reset flow**

Spec §9.1 item 4 requires password reset. `AuthService.sendPasswordReset` already exists (Task 5); it needs an entry point. Add this method and the two widgets to `_LoginScreenState`, placing the `TextButton` directly below the `FilledButton` in the `Column`:

```dart
  Future<void> _resetPassword() async {
    final email = _email.text.trim();
    if (email.isEmpty) {
      setState(() => _error = 'Enter your email first, then tap Reset.');
      return;
    }
    await ref.read(authServiceProvider).sendPasswordReset(email);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Password reset link sent to $email')),
    );
  }
```

```dart
                TextButton(
                  key: const Key('reset'),
                  onPressed: _busy ? null : _resetPassword,
                  child: const Text('Forgot password?'),
                ),
```

- [ ] **Step 6: Add the password reset test**

Append to `test/features/auth/login_screen_test.dart`, inside `main()`:

```dart
  testWidgets('reset requires an email address first', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          firestoreProvider.overrideWithValue(FakeFirebaseFirestore()),
          firebaseAuthProvider.overrideWithValue(MockFirebaseAuth()),
        ],
        child: const MaterialApp(home: LoginScreen()),
      ),
    );

    await tester.tap(find.byKey(const Key('reset')));
    await tester.pumpAndSettle();

    expect(find.textContaining('Enter your email first'), findsOneWidget);
  });
```

- [ ] **Step 7: Run test to verify it passes**

Run: `flutter test test/features/auth/login_screen_test.dart`
Expected: PASS, all three tests

- [ ] **Step 8: Commit**

```bash
git add -A
git commit -m "feat: add login screen with invite promotion, verification gate and password reset"
```

---

## Task 11: Theme and responsive scaffold

**Files:**
- Create: `lib/core/theme/app_theme.dart`, `lib/core/widgets/responsive_scaffold.dart`
- Test: `test/core/widgets/responsive_scaffold_test.dart`

**Interfaces:**
- Consumes: nothing
- Produces:
  - `AppTheme.light` and `AppTheme.dark` — `ThemeData`
  - `ResponsiveScaffold({required String title, required List<NavDestination> destinations, required int selectedIndex, required ValueChanged<int> onDestinationSelected, required Widget body, List<Widget>? actions})`
  - `class NavDestination { final String label; final IconData icon; }`

- [ ] **Step 1: Write the failing test**

Create `test/core/widgets/responsive_scaffold_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ethesishub/core/widgets/responsive_scaffold.dart';

Widget harness() {
  return MaterialApp(
    home: ResponsiveScaffold(
      title: 'Dashboard',
      selectedIndex: 0,
      onDestinationSelected: (_) {},
      destinations: const [
        NavDestination(label: 'Home', icon: Icons.home),
        NavDestination(label: 'Theses', icon: Icons.description),
      ],
      body: const Text('body'),
    ),
  );
}

void main() {
  testWidgets('uses a bottom navigation bar on narrow screens',
      (tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(harness());

    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.byType(NavigationRail), findsNothing);
  });

  testWidgets('uses a navigation rail on wide screens', (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(harness());

    expect(find.byType(NavigationRail), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/core/widgets/responsive_scaffold_test.dart`
Expected: FAIL — `Target of URI doesn't exist`

- [ ] **Step 3: Implement the theme**

Create `lib/core/theme/app_theme.dart`:

```dart
import 'package:flutter/material.dart';

class AppTheme {
  static const _seed = Color(0xFF0B5FA5); // ISUFST blue

  static ThemeData get light => ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: _seed),
      );

  static ThemeData get dark => ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: _seed,
          brightness: Brightness.dark,
        ),
      );
}
```

- [ ] **Step 4: Implement the responsive scaffold**

Create `lib/core/widgets/responsive_scaffold.dart`:

```dart
import 'package:flutter/material.dart';

class NavDestination {
  const NavDestination({required this.label, required this.icon});
  final String label;
  final IconData icon;
}

/// Bottom navigation on narrow screens, navigation rail on wide ones.
class ResponsiveScaffold extends StatelessWidget {
  const ResponsiveScaffold({
    super.key,
    required this.title,
    required this.destinations,
    required this.selectedIndex,
    required this.onDestinationSelected,
    required this.body,
    this.actions,
  });

  static const double railBreakpoint = 900;

  final String title;
  final List<NavDestination> destinations;
  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;
  final Widget body;
  final List<Widget>? actions;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= railBreakpoint;

        return Scaffold(
          appBar: AppBar(title: Text(title), actions: actions),
          body: wide
              ? Row(
                  children: [
                    NavigationRail(
                      selectedIndex: selectedIndex,
                      onDestinationSelected: onDestinationSelected,
                      labelType: NavigationRailLabelType.all,
                      destinations: [
                        for (final d in destinations)
                          NavigationRailDestination(
                            icon: Icon(d.icon),
                            label: Text(d.label),
                          ),
                      ],
                    ),
                    const VerticalDivider(width: 1),
                    Expanded(child: body),
                  ],
                )
              : body,
          bottomNavigationBar: wide
              ? null
              : NavigationBar(
                  selectedIndex: selectedIndex,
                  onDestinationSelected: onDestinationSelected,
                  destinations: [
                    for (final d in destinations)
                      NavigationDestination(
                        icon: Icon(d.icon),
                        label: d.label,
                      ),
                  ],
                ),
        );
      },
    );
  }
}
```

- [ ] **Step 5: Run test to verify it passes**

Run: `flutter test test/core/widgets/responsive_scaffold_test.dart`
Expected: PASS, both tests

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "feat: add theme and responsive scaffold"
```

---

## Task 12: Router with role guards and four dashboards

**Files:**
- Create: `lib/core/routing/app_router.dart`, `lib/features/dashboard/student_dashboard.dart`, `lib/features/dashboard/faculty_dashboard.dart`, `lib/features/dashboard/coordinator_dashboard.dart`, `lib/features/dashboard/dean_dashboard.dart`
- Modify: `lib/app.dart`
- Test: `test/core/routing/app_router_test.dart`

**Interfaces:**
- Consumes: `currentUserProvider`, `authStateProvider`, `AppTheme`, `ResponsiveScaffold`
- Produces: `goRouterProvider` → `GoRouter`; each dashboard is a `ConsumerWidget` displaying a heading unique to its role

- [ ] **Step 1: Write the failing test**

Create `test/core/routing/app_router_test.dart`:

```dart
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ethesishub/app.dart';
import 'package:ethesishub/data/models/user_role.dart';
import 'package:ethesishub/providers/auth_providers.dart';
import 'package:ethesishub/providers/shared_prefs_provider.dart';

Future<ProviderScope> scopeFor(UserRole role, {required String uid}) async {
  final db = FakeFirebaseFirestore();
  await db.collection('users').doc(uid).set({
    'fullName': 'Test User',
    'email': 'test@isufst.edu.ph',
    'role': role.value,
    'active': true,
  });

  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();

  return ProviderScope(
    overrides: [
      sharedPrefsProvider.overrideWithValue(prefs),
      firestoreProvider.overrideWithValue(db),
      firebaseAuthProvider.overrideWithValue(
        MockFirebaseAuth(
          signedIn: true,
          mockUser: MockUser(
            uid: uid,
            email: 'test@isufst.edu.ph',
            isEmailVerified: true,
          ),
        ),
      ),
    ],
    child: const EThesisHubApp(),
  );
}

void main() {
  testWidgets('student lands on the student dashboard', (tester) async {
    await tester.pumpWidget(await scopeFor(UserRole.student, uid: 'u1'));
    await tester.pumpAndSettle();
    expect(find.text('My Thesis'), findsOneWidget);
  });

  testWidgets('faculty lands on the faculty dashboard', (tester) async {
    await tester.pumpWidget(await scopeFor(UserRole.faculty, uid: 'u2'));
    await tester.pumpAndSettle();
    expect(find.text('My Advisees'), findsOneWidget);
  });

  testWidgets('coordinator lands on the coordinator dashboard',
      (tester) async {
    await tester.pumpWidget(await scopeFor(UserRole.coordinator, uid: 'u3'));
    await tester.pumpAndSettle();
    expect(find.text('All Theses'), findsOneWidget);
  });

  testWidgets('dean lands on the dean dashboard', (tester) async {
    await tester.pumpWidget(await scopeFor(UserRole.dean, uid: 'u4'));
    await tester.pumpAndSettle();
    expect(find.text('College Overview'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/core/routing/app_router_test.dart`
Expected: FAIL — `goRouterProvider` undefined

- [ ] **Step 3: Create the four dashboards**

Create `lib/features/dashboard/student_dashboard.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ethesishub/core/widgets/responsive_scaffold.dart';

class StudentDashboard extends ConsumerWidget {
  const StudentDashboard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return const ResponsiveScaffold(
      title: 'eThesisHub',
      selectedIndex: 0,
      onDestinationSelected: _noop,
      destinations: [
        NavDestination(label: 'Thesis', icon: Icons.description),
        NavDestination(label: 'Archive', icon: Icons.library_books),
      ],
      body: Center(child: Text('My Thesis')),
    );
  }
}

void _noop(int _) {}
```

Create `lib/features/dashboard/faculty_dashboard.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ethesishub/core/widgets/responsive_scaffold.dart';

class FacultyDashboard extends ConsumerWidget {
  const FacultyDashboard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return const ResponsiveScaffold(
      title: 'eThesisHub',
      selectedIndex: 0,
      onDestinationSelected: _noop,
      destinations: [
        NavDestination(label: 'Groups', icon: Icons.groups),
        NavDestination(label: 'Defenses', icon: Icons.event),
      ],
      body: Center(child: Text('My Advisees')),
    );
  }
}

void _noop(int _) {}
```

Create `lib/features/dashboard/coordinator_dashboard.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ethesishub/core/widgets/responsive_scaffold.dart';

class CoordinatorDashboard extends ConsumerWidget {
  const CoordinatorDashboard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return const ResponsiveScaffold(
      title: 'eThesisHub',
      selectedIndex: 0,
      onDestinationSelected: _noop,
      destinations: [
        NavDestination(label: 'Theses', icon: Icons.folder),
        NavDestination(label: 'Faculty', icon: Icons.badge),
        NavDestination(label: 'Defenses', icon: Icons.event),
      ],
      body: Center(child: Text('All Theses')),
    );
  }
}

void _noop(int _) {}
```

Create `lib/features/dashboard/dean_dashboard.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ethesishub/core/widgets/responsive_scaffold.dart';

class DeanDashboard extends ConsumerWidget {
  const DeanDashboard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return const ResponsiveScaffold(
      title: 'eThesisHub',
      selectedIndex: 0,
      onDestinationSelected: _noop,
      destinations: [
        NavDestination(label: 'Overview', icon: Icons.dashboard),
        NavDestination(label: 'Approvals', icon: Icons.approval),
      ],
      body: Center(child: Text('College Overview')),
    );
  }
}

void _noop(int _) {}
```

- [ ] **Step 4: Implement the router**

Create `lib/core/routing/app_router.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:ethesishub/data/models/user_role.dart';
import 'package:ethesishub/features/auth/login_screen.dart';
import 'package:ethesishub/features/auth/register_screen.dart';
import 'package:ethesishub/features/auth/verify_email_screen.dart';
import 'package:ethesishub/features/dashboard/coordinator_dashboard.dart';
import 'package:ethesishub/features/dashboard/dean_dashboard.dart';
import 'package:ethesishub/features/dashboard/faculty_dashboard.dart';
import 'package:ethesishub/features/dashboard/student_dashboard.dart';
import 'package:ethesishub/providers/auth_providers.dart';

/// Home route for each account role.
String homeRouteFor(UserRole role) => switch (role) {
      UserRole.student => '/student',
      UserRole.faculty => '/faculty',
      UserRole.coordinator => '/coordinator',
      UserRole.dean => '/dean',
    };

final goRouterProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: '/login',
    redirect: (context, state) {
      final authState = ref.read(authStateProvider).value;
      final location = state.matchedLocation;
      final onAuthScreen = location == '/login' || location == '/register';

      if (authState == null) {
        return onAuthScreen ? null : '/login';
      }
      if (!authState.emailVerified) {
        return location == '/verify-email' ? null : '/verify-email';
      }

      final profile = ref.read(currentUserProvider).value;
      if (profile == null) return null; // still loading

      final home = homeRouteFor(profile.role);
      if (onAuthScreen || location == '/verify-email') return home;

      // Prevent reaching another role's dashboard by typing its URL.
      const dashboards = ['/student', '/faculty', '/coordinator', '/dean'];
      if (dashboards.contains(location) && location != home) return home;

      return null;
    },
    routes: [
      GoRoute(path: '/login', builder: (_, __) => const LoginScreen()),
      GoRoute(path: '/register', builder: (_, __) => const RegisterScreen()),
      GoRoute(
        path: '/verify-email',
        builder: (_, __) => const VerifyEmailScreen(),
      ),
      GoRoute(path: '/student', builder: (_, __) => const StudentDashboard()),
      GoRoute(path: '/faculty', builder: (_, __) => const FacultyDashboard()),
      GoRoute(
        path: '/coordinator',
        builder: (_, __) => const CoordinatorDashboard(),
      ),
      GoRoute(path: '/dean', builder: (_, __) => const DeanDashboard()),
    ],
  );
});
```

- [ ] **Step 5: Rewrite `lib/app.dart` to use the router**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ethesishub/core/routing/app_router.dart';
import 'package:ethesishub/core/theme/app_theme.dart';
import 'package:ethesishub/providers/auth_providers.dart';

class EThesisHubApp extends ConsumerWidget {
  const EThesisHubApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Keep these alive so router redirects see fresh values.
    ref.watch(authStateProvider);
    ref.watch(currentUserProvider);

    return MaterialApp.router(
      title: 'eThesisHub',
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: ThemeMode.system,
      routerConfig: ref.watch(goRouterProvider),
    );
  }
}
```

- [ ] **Step 6: Delete the original smoke test**

`test/widget_test.dart` from Task 1 pumps `EThesisHubApp` without a `ProviderScope` and will now fail. Delete the file:

```bash
git rm test/widget_test.dart
```

`EThesisHubApp` is genuinely covered by the four routing tests in this task. Do **not** replace it with a placeholder test that asserts a constant — a test that cannot fail adds no coverage and misreports the suite size.

- [ ] **Step 7: Run the full suite**

Run: `flutter test`
Expected: PASS, all tests including the four routing tests

- [ ] **Step 8: Commit**

```bash
git add -A
git commit -m "feat: add role-guarded routing and four role dashboards"
```

---

## Task 13: Faculty mode switch

Adviser/Panelist mode with persistence, an inactive-mode badge, and auto-lock for panel-only faculty (spec §8.4).

**Files:**
- Create: `lib/data/models/faculty_mode.dart`, `lib/providers/faculty_mode_provider.dart`
- Modify: `lib/features/dashboard/faculty_dashboard.dart`
- Test: `test/providers/faculty_mode_provider_test.dart`

**Interfaces:**
- Consumes: `sharedPrefsProvider`
- Produces:
  - `enum FacultyMode { adviser, panelist }`
  - `facultyModeProvider` → `NotifierProvider<FacultyModeNotifier, FacultyMode>` with `void set(FacultyMode mode)`
  - Persistence key `faculty_mode`

- [ ] **Step 1: Write the failing test**

Create `test/providers/faculty_mode_provider_test.dart`:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ethesishub/data/models/faculty_mode.dart';
import 'package:ethesishub/providers/faculty_mode_provider.dart';
import 'package:ethesishub/providers/shared_prefs_provider.dart';

Future<ProviderContainer> containerWith(Map<String, Object> seed) async {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues(seed);
  final prefs = await SharedPreferences.getInstance();
  return ProviderContainer(
    overrides: [sharedPrefsProvider.overrideWithValue(prefs)],
  );
}

void main() {
  test('defaults to adviser mode', () async {
    final container = await containerWith({});
    addTearDown(container.dispose);

    expect(container.read(facultyModeProvider), FacultyMode.adviser);
  });

  test('restores the persisted mode', () async {
    final container = await containerWith({'faculty_mode': 'panelist'});
    addTearDown(container.dispose);

    expect(container.read(facultyModeProvider), FacultyMode.panelist);
  });

  test('set updates state and persists', () async {
    final container = await containerWith({});
    addTearDown(container.dispose);

    container.read(facultyModeProvider.notifier).set(FacultyMode.panelist);

    expect(container.read(facultyModeProvider), FacultyMode.panelist);
    expect(
      container.read(sharedPrefsProvider).getString('faculty_mode'),
      'panelist',
    );
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/providers/faculty_mode_provider_test.dart`
Expected: FAIL — `Target of URI doesn't exist`

- [ ] **Step 3: Implement the enum**

Create `lib/data/models/faculty_mode.dart`:

```dart
enum FacultyMode {
  adviser,
  panelist;

  String get value => name;
  String get label => this == FacultyMode.adviser ? 'Adviser' : 'Panelist';

  static FacultyMode fromString(String? raw) =>
      raw == FacultyMode.panelist.name ? FacultyMode.panelist : FacultyMode.adviser;
}
```

- [ ] **Step 4: Implement the provider**

Create `lib/providers/faculty_mode_provider.dart`:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ethesishub/data/models/faculty_mode.dart';
import 'package:ethesishub/providers/shared_prefs_provider.dart';

const facultyModeKey = 'faculty_mode';

class FacultyModeNotifier extends Notifier<FacultyMode> {
  @override
  FacultyMode build() {
    final prefs = ref.watch(sharedPrefsProvider);
    return FacultyMode.fromString(prefs.getString(facultyModeKey));
  }

  void set(FacultyMode mode) {
    state = mode;
    ref.read(sharedPrefsProvider).setString(facultyModeKey, mode.value);
  }
}

final facultyModeProvider =
    NotifierProvider<FacultyModeNotifier, FacultyMode>(FacultyModeNotifier.new);
```

- [ ] **Step 5: Add position-count providers**

The mode switch depends on two facts that do not exist until M1: how many adviser positions this faculty member holds, and how much work is pending in the mode they are not looking at. Expose them as providers now so M1 fills in the bodies without touching the widget. Append to `lib/providers/faculty_mode_provider.dart`:

```dart
/// Number of theses where the signed-in faculty member is the adviser.
/// M1 replaces this body with a query over `theses` filtered by adviserUid.
final adviserPositionCountProvider = Provider<int>((ref) => 0);

/// Items awaiting action in whichever mode is NOT currently selected.
/// M1/M3 replace this body with real pending-work counts.
final pendingInOtherModeProvider = Provider<int>((ref) => 0);
```

Do **not** hardcode these values as constants inside the widget — UI branching on a literal is unreachable code until M1 and reads as dead code.

- [ ] **Step 6: Wire the switch into the faculty dashboard**

Replace `lib/features/dashboard/faculty_dashboard.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ethesishub/core/widgets/responsive_scaffold.dart';
import 'package:ethesishub/data/models/faculty_mode.dart';
import 'package:ethesishub/providers/faculty_mode_provider.dart';

class FacultyDashboard extends ConsumerWidget {
  const FacultyDashboard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(facultyModeProvider);
    final holdsAdviserPositions = ref.watch(adviserPositionCountProvider) > 0;
    final pendingElsewhere = ref.watch(pendingInOtherModeProvider);

    return ResponsiveScaffold(
      title: 'eThesisHub',
      selectedIndex: 0,
      onDestinationSelected: (_) {},
      destinations: const [
        NavDestination(label: 'Groups', icon: Icons.groups),
        NavDestination(label: 'Defenses', icon: Icons.event),
      ],
      actions: [
        if (holdsAdviserPositions)
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Badge(
              isLabelVisible: pendingElsewhere > 0,
              label: Text('$pendingElsewhere'),
              child: SegmentedButton<FacultyMode>(
                segments: const [
                  ButtonSegment(
                    value: FacultyMode.adviser,
                    label: Text('Adviser'),
                  ),
                  ButtonSegment(
                    value: FacultyMode.panelist,
                    label: Text('Panelist'),
                  ),
                ],
                selected: {mode},
                onSelectionChanged: (selection) => ref
                    .read(facultyModeProvider.notifier)
                    .set(selection.first),
              ),
            ),
          ),
      ],
      body: Center(
        child: Text(
          mode == FacultyMode.adviser ? 'My Advisees' : 'My Panels',
        ),
      ),
    );
  }
}
```

The routing test from Task 12 asserts `'My Advisees'`, which remains the default (adviser) mode's label. Note that with `adviserPositionCountProvider` returning 0, the toggle is hidden until M1 supplies real positions — this is the panel-only auto-lock behaviour from spec §8.4 working correctly, not a bug.

- [ ] **Step 7: Run the full suite**

Run: `flutter test`
Expected: PASS, all tests

- [ ] **Step 8: Commit**

```bash
git add -A
git commit -m "feat: add persisted faculty adviser/panelist mode switch"
```

---

## Task 14: StorageService and AuditService

**Files:**
- Create: `lib/data/services/storage_service.dart`, `lib/data/services/supabase_storage_service.dart`, `lib/data/services/audit_service.dart`, `lib/providers/service_providers.dart`
- Test: `test/data/services/audit_service_test.dart`, `test/data/services/storage_path_test.dart`

**Interfaces:**
- Consumes: `firestoreProvider`, `AppConfig.documentsBucket`
- Produces:
  - `class StoredFile { final String path; final String url; }`
  - `abstract class StorageService` with `Future<StoredFile> upload({required List<int> bytes, required String path, required String contentType})` and `Future<void> delete(String path)`
  - `SupabaseStorageService implements StorageService`
  - `StoragePaths.thesisDocument({required String thesisId, required String documentId, required String extension})` → unguessable UUID-suffixed path
  - `AuditService.log({required String actorUid, required String action, required String targetType, required String targetId, Map<String, dynamic>? metadata})`
  - `storageServiceProvider`, `auditServiceProvider`

- [ ] **Step 1: Write the failing tests**

Create `test/data/services/storage_path_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:ethesishub/data/services/storage_service.dart';

void main() {
  test('thesis document paths are namespaced and unguessable', () {
    final path = StoragePaths.thesisDocument(
      thesisId: 'thesis-1',
      documentId: 'doc-1',
      extension: 'pdf',
    );

    expect(path, startsWith('theses/thesis-1/doc-1/'));
    expect(path, endsWith('.pdf'));
    // A UUID v4 has 36 characters; the segment must not be predictable.
    final filename = path.split('/').last;
    expect(filename.length, greaterThan(36));
  });

  test('two calls never produce the same path', () {
    final a = StoragePaths.thesisDocument(
        thesisId: 't', documentId: 'd', extension: 'pdf');
    final b = StoragePaths.thesisDocument(
        thesisId: 't', documentId: 'd', extension: 'pdf');
    expect(a, isNot(b));
  });
}
```

Create `test/data/services/audit_service_test.dart`:

```dart
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ethesishub/data/services/audit_service.dart';

void main() {
  test('log writes an entry attributed to the actor', () async {
    final db = FakeFirebaseFirestore();
    final service = AuditService(db);

    await service.log(
      actorUid: 'uid-1',
      action: 'role.promoted',
      targetType: 'user',
      targetId: 'uid-1',
      metadata: {'to': 'faculty'},
    );

    final logs = await db.collection('auditLogs').get();
    expect(logs.docs, hasLength(1));
    expect(logs.docs.first.data()['actorUid'], 'uid-1');
    expect(logs.docs.first.data()['action'], 'role.promoted');
    expect(logs.docs.first.data()['metadata']['to'], 'faculty');
  });
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `flutter test test/data/services/`
Expected: FAIL — `Target of URI doesn't exist` for both new files

- [ ] **Step 3: Add the uuid dependency**

```bash
flutter pub add uuid
```

- [ ] **Step 4: Implement StorageService and paths**

Create `lib/data/services/storage_service.dart`:

```dart
import 'package:uuid/uuid.dart';

class StoredFile {
  const StoredFile({required this.path, required this.url});
  final String path;
  final String url;
}

/// The Supabase bucket is public, so paths must be unguessable (spec §7.2).
class StoragePaths {
  static const _uuid = Uuid();

  static String thesisDocument({
    required String thesisId,
    required String documentId,
    required String extension,
  }) {
    return 'theses/$thesisId/$documentId/${_uuid.v4()}-${_uuid.v4()}.$extension';
  }
}

abstract class StorageService {
  Future<StoredFile> upload({
    required List<int> bytes,
    required String path,
    required String contentType,
  });

  Future<void> delete(String path);
}
```

- [ ] **Step 5: Implement the Supabase adapter**

Create `lib/data/services/supabase_storage_service.dart`:

```dart
import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:ethesishub/core/config/app_config.dart';
import 'package:ethesishub/data/services/storage_service.dart';

class SupabaseStorageService implements StorageService {
  SupabaseStorageService(this._client);

  final SupabaseClient _client;

  @override
  Future<StoredFile> upload({
    required List<int> bytes,
    required String path,
    required String contentType,
  }) async {
    final bucket = _client.storage.from(AppConfig.documentsBucket);

    await bucket.uploadBinary(
      path,
      Uint8List.fromList(bytes),
      fileOptions: FileOptions(contentType: contentType, upsert: false),
    );

    return StoredFile(path: path, url: bucket.getPublicUrl(path));
  }

  @override
  Future<void> delete(String path) async {
    await _client.storage.from(AppConfig.documentsBucket).remove([path]);
  }
}
```

- [ ] **Step 6: Implement AuditService**

Create `lib/data/services/audit_service.dart`:

```dart
import 'package:cloud_firestore/cloud_firestore.dart';

class AuditService {
  AuditService(this._db);

  final FirebaseFirestore _db;

  Future<void> log({
    required String actorUid,
    required String action,
    required String targetType,
    required String targetId,
    Map<String, dynamic>? metadata,
  }) {
    return _db.collection('auditLogs').add({
      'actorUid': actorUid,
      'action': action,
      'targetType': targetType,
      'targetId': targetId,
      'metadata': metadata ?? <String, dynamic>{},
      'timestamp': FieldValue.serverTimestamp(),
    });
  }
}
```

- [ ] **Step 7: Register the providers**

Create `lib/providers/service_providers.dart`:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:ethesishub/data/services/audit_service.dart';
import 'package:ethesishub/data/services/storage_service.dart';
import 'package:ethesishub/data/services/supabase_storage_service.dart';
import 'package:ethesishub/providers/auth_providers.dart';

final supabaseClientProvider =
    Provider<SupabaseClient>((ref) => Supabase.instance.client);

final storageServiceProvider = Provider<StorageService>(
  (ref) => SupabaseStorageService(ref.watch(supabaseClientProvider)),
);

final auditServiceProvider = Provider<AuditService>(
  (ref) => AuditService(ref.watch(firestoreProvider)),
);
```

- [ ] **Step 8: Run tests to verify they pass**

Run: `flutter test`
Expected: PASS, all tests

- [ ] **Step 9: Commit**

```bash
git add -A
git commit -m "feat: add StorageService, Supabase adapter and AuditService"
```

---

## Task 15: Bootstrap and exit-criteria verification

Proves the skeleton against the spec's exit criteria on real infrastructure, not mocks.

**Files:**
- Create: `docs/superpowers/plans/skeleton-verification.md` (record of results)
- Modify: none

**Interfaces:**
- Consumes: everything built in Tasks 1–14
- Produces: a verified, running application ready for M1

- [ ] **Step 1: Run the whole suite and the analyzer**

```bash
flutter analyze
flutter test
cd rules-test && npm test && cd ..
```

Expected: no analyzer errors; all Dart tests pass; all eight rules tests pass.

- [ ] **Step 2: Register the first account**

```bash
flutter run -d chrome
```

Register with your own institutional address. Confirm: no role selector appears anywhere on the form, and a verification email arrives.

- [ ] **Step 3: Seed the first coordinator by hand**

In the Firebase Console → Firestore → `users` → your new document, change `role` from `student` to `coordinator`. This is the one-time bootstrap from spec §6.2; every later coordinator is made through an invite.

- [ ] **Step 4: Verify the coordinator dashboard**

Reload the app. Expected: you land on **All Theses**, not **My Thesis**.

- [ ] **Step 5: Verify invite-based promotion end to end**

1. In the Console, create `facultyInvites/{some.faculty@isufst.edu.ph}` with `role: "faculty"` and `invitedBy: "<your uid>"`
2. Register a second account with that exact email, verify it, and sign in
3. Expected: the account lands on **My Advisees**, and the `facultyInvites` document is gone

- [ ] **Step 6: Verify a student cannot escalate**

In the Console, create a third student account. With that account signed in, open the browser devtools console and attempt a direct write:

Expected: **PERMISSION_DENIED**. The equivalent assertion already runs automatically in `rules-test/rules.test.js` (*"a student may NOT promote themselves without an invite"*), so this is a confirmation on production rules rather than emulator rules.

- [ ] **Step 7: Verify the responsive shell and themes**

Narrow the browser below 900px: the navigation rail becomes a bottom navigation bar. Switch your OS to dark mode: the app follows.

- [ ] **Step 8: Verify the Android build**

```bash
flutter build apk --debug
```

Expected: build succeeds. If it fails on `dart:io`, a `lib/` file has imported it in violation of the Global Constraints.

- [ ] **Step 9: Record the results**

Create `docs/superpowers/plans/skeleton-verification.md` listing each exit criterion from spec §9.1 with its outcome and the date. This is evidence for Chapter IV's testing section, which claims Firebase Emulator Suite integration testing.

- [ ] **Step 10: Commit**

```bash
git add -A
git commit -m "docs: record walking skeleton verification against exit criteria"
```

---

## Next plans

Written when reached, one per module, each producing working software on its own:

| Plan | Module | Prerequisite |
|---|---|---|
| `<date>-m1-nomination.md` | Title submission, nomination, Conforme, coordinator recommend, dean approve | This plan |
| `<date>-m2-documents.md` | Upload, versioning, revision feedback | M1 |
| `<date>-m3-defense-comments.md` | Scheduling, append-only bracketed comments | M1 |
| `<date>-m4-evaluation.md` | Form 5c rubric, scoring, Pass/Fail | M3 |
| `<date>-m5-repository.md` | Archive, search, notifications | This plan |
| `<date>-m6-forms.md` | Pre-filled PDF form generation | M1, M3, M4 |

M1 replaces the two placeholder constants in `FacultyDashboard` (`holdsAdviserPositions`, `inactiveModePendingCount`) with real values, and extends `firestore.rules` with the `theses` and `nominations` collections.
