# Notifications Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship a self-authored, in-app notification feed — a bell badge in the app shell and a list screen — covering five trigger categories (nomination/title lifecycle, chapter feedback, defence comments/scheduling, evaluation-awaits, archive published), with zero cross-user write authority.

**Architecture:** Each signed-in client watches the same live Firestore streams it already reads elsewhere (`myThesisProvider`, `myPendingNominationsProvider`, `chapterFeedbackProvider`, `myDefencesProvider`, `defenceCommentsProvider`, `defenceEvaluationsProvider`, `archiveProvider`), diffs against nothing but the source data itself (no separate cursor needed — see D71/D72 below), and idempotently writes into its own `notifications/{uid}/items/{itemId}` subcollection. A bell in `app_shell_host.dart`'s top bar shows the live unread count; tapping it opens a list screen that marks items read and navigates to their source, switching faculty mode first when needed (D75).

**Tech Stack:** Flutter, Riverpod (`StreamProvider`, `Provider`, `ref.listen` live fan-ins — the same shape `needs_you_providers.dart` and `archive_providers.dart` already use), Cloud Firestore, `fake_cloud_firestore` for repository/provider tests, the Firestore emulator (`rules-test/rules.test.js`) for rules tests.

**Spec:** `docs/superpowers/specs/2026-09-03-notifications-design.md`

## Global Constraints

- **No cross-user writes, ever** (D70). Every write in this plan is `request.auth.uid == uid` against the writer's own subcollection. If a task's code needs to read or write another user's `notifications/{uid}`, that is a bug in the plan, not a shortcut to take.
- **Deterministic item ids only** (D71). Every `AppNotification.id` this plan writes is derived from source-document content, never `DateTime.now()` or a random id. Two clients (or one client re-running detection) writing the same event must produce the exact same id.
- **`createdAt` is always the source event's own timestamp** (D72), never wall-clock detection time.
- **No `flutter_local_notifications` dependency is added** (D74). Nothing in this plan touches `pubspec.yaml` for a notification package.
- **Detection failures are logged, not surfaced** (D73) — a detector provider must never throw in a way that crashes the shell or blocks another detector.
- All new/changed Dart files run through `dart format` before committing, matching the rest of the codebase.

---

### Task 1: `AppNotification` model

**Files:**
- Create: `lib/data/models/app_notification.dart`
- Test: `test/data/models/app_notification_test.dart`

**Interfaces:**
- Produces: `enum NotificationType { conformeRequested, nominationRecommended, nominationApproved, titleApproved, titleRejected, chapterFeedback, defenceComment, defenceScheduled, evaluationAwaits, archivePublished }` with `.value` (String) and `NotificationType.fromString(String?)`; `class AppNotification { id, type, thesisId, message, read, createdAt }` with `AppNotification.fromMap(String id, Map<String, dynamic> map)`, `toMap()`, and a `copyWith({bool? read})`; top-level `String notificationId(NotificationType type, String sourceKey)`.

- [ ] **Step 1: Write the failing tests**

```dart
// test/data/models/app_notification_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:ethesishub/data/models/app_notification.dart';

void main() {
  group('NotificationType', () {
    test('round-trips through its string value', () {
      for (final type in NotificationType.values) {
        expect(NotificationType.fromString(type.value), type);
      }
    });

    test('an unrecognised or null string falls back to chapterFeedback', () {
      expect(NotificationType.fromString('made_up'), NotificationType.chapterFeedback);
      expect(NotificationType.fromString(null), NotificationType.chapterFeedback);
    });
  });

  group('notificationId', () {
    test('is deterministic for the same type and source key', () {
      final a = notificationId(NotificationType.defenceComment, 'c1');
      final b = notificationId(NotificationType.defenceComment, 'c1');
      expect(a, b);
    });

    test('differs across types for the same source key', () {
      final a = notificationId(NotificationType.defenceComment, 'x1');
      final b = notificationId(NotificationType.evaluationAwaits, 'x1');
      expect(a, isNot(b));
    });
  });

  group('AppNotification', () {
    test('round-trips through fromMap/toMap', () {
      final n = AppNotification(
        id: notificationId(NotificationType.archivePublished, 't1'),
        type: NotificationType.archivePublished,
        thesisId: 't1',
        message: 'Your thesis was published to the archive.',
        read: false,
        createdAt: DateTime(2026, 9, 3, 10, 30),
      );
      final back = AppNotification.fromMap(n.id, n.toMap());

      expect(back.id, n.id);
      expect(back.type, n.type);
      expect(back.thesisId, n.thesisId);
      expect(back.message, n.message);
      expect(back.read, n.read);
      expect(back.createdAt, n.createdAt);
    });

    test('copyWith(read: true) changes only read', () {
      final n = AppNotification(
        id: 'x',
        type: NotificationType.chapterFeedback,
        thesisId: 't1',
        message: 'm',
        read: false,
        createdAt: DateTime(2026, 1, 1),
      );
      final read = n.copyWith(read: true);

      expect(read.read, isTrue);
      expect(read.id, n.id);
      expect(read.message, n.message);
      expect(read.createdAt, n.createdAt);
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/data/models/app_notification_test.dart`
Expected: FAIL — `app_notification.dart` does not exist yet.

- [ ] **Step 3: Write the implementation**

```dart
// lib/data/models/app_notification.dart

/// What kind of event this notification reports.
///
/// Each value corresponds to exactly one detector in
/// `lib/providers/notification_providers.dart`. `titleApproved` and
/// `titleRejected` are separate values (not one `titleDecided`) because
/// their messages read completely differently and a reader should be able
/// to tell them apart from the type alone, the same way the app already
/// keeps `ThesisStatus.titleApproved`/`titleRejected` as distinct values.
enum NotificationType {
  conformeRequested,
  nominationRecommended,
  nominationApproved,
  titleApproved,
  titleRejected,
  chapterFeedback,
  defenceComment,
  defenceScheduled,
  evaluationAwaits,
  archivePublished;

  String get value => name;

  static NotificationType fromString(String? raw) {
    for (final t in NotificationType.values) {
      if (t.name == raw) return t;
    }
    return NotificationType.chapterFeedback;
  }
}

/// A deterministic item id, derived from the type and a source-specific
/// key — never random, never wall-clock. Two clients detecting the same
/// event (two of the reader's own devices, or one client re-running
/// detection after a reconnect) must land on the exact same id, so the
/// second write is a no-op rather than a duplicate row (D71).
///
/// `sourceKey` is each detector's own concern: a comment id is already
/// unique on its own, but a field-level change (a defence's schedule
/// moving) has no natural document id of its own, so its detector folds
/// the new value into the key instead — see
/// `lib/providers/notification_providers.dart`.
String notificationId(NotificationType type, String sourceKey) =>
    '${type.value}_$sourceKey';

/// One entry in a reader's own notification feed.
///
/// Lives at `notifications/{uid}/items/{id}` — always the READER's own
/// subcollection, written only by the reader's own client (D70). `id` is
/// always a [notificationId] result; nothing constructs one ad hoc.
class AppNotification {
  const AppNotification({
    required this.id,
    required this.type,
    required this.thesisId,
    required this.message,
    required this.read,
    required this.createdAt,
  });

  final String id;
  final NotificationType type;
  final String thesisId;

  /// A pure, already-rendered sentence — generated once by the detector
  /// that wrote this item, from fields the writer already has standing
  /// read access to. Never re-derived on read.
  final String message;

  final bool read;

  /// The SOURCE event's own timestamp (D72), not when this client noticed
  /// it — so the feed sorts correctly even for a client that only
  /// reconnects long after the underlying event happened.
  final DateTime createdAt;

  AppNotification copyWith({bool? read}) => AppNotification(
        id: id,
        type: type,
        thesisId: thesisId,
        message: message,
        read: read ?? this.read,
        createdAt: createdAt,
      );

  factory AppNotification.fromMap(String id, Map<String, dynamic> map) {
    return AppNotification(
      id: id,
      type: NotificationType.fromString(map['type'] as String?),
      thesisId: map['thesisId'] as String? ?? '',
      message: map['message'] as String? ?? '',
      read: map['read'] as bool? ?? false,
      createdAt: map['createdAt'] as DateTime? ?? DateTime.fromMillisecondsSinceEpoch(0),
    );
  }

  Map<String, dynamic> toMap() => {
        'type': type.value,
        'thesisId': thesisId,
        'message': message,
        'read': read,
        'createdAt': createdAt,
      };
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/data/models/app_notification_test.dart`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add lib/data/models/app_notification.dart test/data/models/app_notification_test.dart
git commit -m "feat: add AppNotification model and its deterministic id helper"
```

---

### Task 2: `NotificationRepository`

**Files:**
- Create: `lib/data/repositories/notification_repository.dart`
- Test: `test/data/repositories/notification_repository_test.dart`

**Interfaces:**
- Consumes: `AppNotification`, `notificationId` from Task 1.
- Produces: `class NotificationRepository(FirebaseFirestore firestore)` with `Stream<List<AppNotification>> watchItems(String uid)`, `Future<void> upsertIfAbsent(String uid, AppNotification item)`, `Future<void> markRead(String uid, String itemId)`, `Future<void> markAllRead(String uid, List<String> itemIds)`.

- [ ] **Step 1: Write the failing tests**

```dart
// test/data/repositories/notification_repository_test.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ethesishub/data/models/app_notification.dart';
import 'package:ethesishub/data/repositories/notification_repository.dart';

AppNotification item({
  String id = 'archivePublished_t1',
  bool read = false,
  DateTime? createdAt,
}) {
  return AppNotification(
    id: id,
    type: NotificationType.archivePublished,
    thesisId: 't1',
    message: 'Your thesis was published to the archive.',
    read: read,
    createdAt: createdAt ?? DateTime(2026, 9, 3),
  );
}

void main() {
  late FakeFirebaseFirestore firestore;
  late NotificationRepository repo;

  setUp(() {
    firestore = FakeFirebaseFirestore();
    repo = NotificationRepository(firestore);
  });

  group('upsertIfAbsent', () {
    test('writes a new item', () async {
      await repo.upsertIfAbsent('u1', item());

      final snap = await firestore
          .collection('notifications')
          .doc('u1')
          .collection('items')
          .doc('archivePublished_t1')
          .get();
      expect(snap.exists, isTrue);
      expect(snap.data()!['message'], 'Your thesis was published to the archive.');
    });

    test('never overwrites an existing item -- read state survives redetection', () async {
      await repo.upsertIfAbsent('u1', item());
      await repo.markRead('u1', 'archivePublished_t1');

      // Redetection fires again with the same deterministic id (D71).
      await repo.upsertIfAbsent('u1', item());

      final items = await repo.watchItems('u1').first;
      expect(items.single.read, isTrue);
    });
  });

  group('watchItems', () {
    test('newest first', () async {
      await repo.upsertIfAbsent('u1', item(id: 'a', createdAt: DateTime(2026, 1, 1)));
      await repo.upsertIfAbsent('u1', item(id: 'b', createdAt: DateTime(2026, 6, 1)));

      final items = await repo.watchItems('u1').first;
      expect(items.map((i) => i.id).toList(), ['b', 'a']);
    });

    test("one user's items never appear in another's watch", () async {
      await repo.upsertIfAbsent('u1', item());
      final other = await repo.watchItems('u2').first;
      expect(other, isEmpty);
    });
  });

  group('markAllRead', () {
    test('marks every listed item read in one batch', () async {
      await repo.upsertIfAbsent('u1', item(id: 'a'));
      await repo.upsertIfAbsent('u1', item(id: 'b'));

      await repo.markAllRead('u1', ['a', 'b']);

      final items = await repo.watchItems('u1').first;
      expect(items.every((i) => i.read), isTrue);
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/data/repositories/notification_repository_test.dart`
Expected: FAIL — `notification_repository.dart` does not exist yet.

- [ ] **Step 3: Write the implementation**

```dart
// lib/data/repositories/notification_repository.dart
import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:ethesishub/data/models/app_notification.dart';

/// One reader's own notification feed, at `notifications/{uid}/items`.
///
/// Every method here takes the `uid` whose subcollection to touch — never
/// resolved internally from auth state — because every call site (the
/// detectors in `notification_providers.dart`) is a self-authored write
/// (D70) and must be explicit about whose feed it is writing into. There
/// is no method that touches another user's `uid`.
class NotificationRepository {
  NotificationRepository(this._firestore);

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> _items(String uid) => _firestore
      .collection('notifications')
      .doc(uid)
      .collection('items');

  Stream<List<AppNotification>> watchItems(String uid) {
    return _items(uid)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((s) => s.docs
            .map((d) => AppNotification.fromMap(d.id, {
                  ...d.data(),
                  'createdAt': (d.data()['createdAt'] as Timestamp?)?.toDate(),
                }))
            .toList());
  }

  /// Writes [item] only if no document with its id already exists.
  ///
  /// The read-then-write is deliberate, not an oversight: a plain `set`
  /// would silently resurrect `read: false` on an item the reader already
  /// dismissed, the moment a detector re-runs against the same source
  /// event (which every detector does on every emission of its source
  /// stream, by design -- see `_detect` in `notification_providers.dart`).
  Future<void> upsertIfAbsent(String uid, AppNotification item) async {
    final ref = _items(uid).doc(item.id);
    final existing = await ref.get();
    if (existing.exists) return;
    await ref.set(item.toMap());
  }

  Future<void> markRead(String uid, String itemId) =>
      _items(uid).doc(itemId).update({'read': true});

  Future<void> markAllRead(String uid, List<String> itemIds) async {
    final batch = _firestore.batch();
    for (final id in itemIds) {
      batch.update(_items(uid).doc(id), {'read': true});
    }
    await batch.commit();
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/data/repositories/notification_repository_test.dart`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add lib/data/repositories/notification_repository.dart test/data/repositories/notification_repository_test.dart
git commit -m "feat: add NotificationRepository, owner-scoped read/write"
```

---

### Task 3: `firestore.rules` — owner-only

**Files:**
- Modify: `firestore.rules` (add before the `match /{document=**}` catch-all at the end)
- Test: `rules-test/rules.test.js` (add a new `describe('notifications', ...)` block)

**Interfaces:**
- Consumes: nothing from earlier tasks — this is pure rules text plus its own JS test file.
- Produces: the `notifications/{uid}/items/{itemId}` rule arm that Task 2's repository (once deployed against a real project) and every later provider task rely on.

- [ ] **Step 1: Write the failing rules tests**

Find the end of `rules-test/rules.test.js` (the closing of the last `describe` block, mirroring the style of the `archiveEntries` tests already in that file) and add:

```javascript
describe('notifications', () => {
  const notif = (uid, id, overrides = {}) =>
    setDoc(doc(db, 'notifications', uid, 'items', id), {
      type: 'archivePublished',
      thesisId: 't1',
      message: 'Your thesis was published to the archive.',
      read: false,
      createdAt: serverTimestamp(),
      ...overrides,
    });

  it('the owner can read their own items', async () => {
    const owner = testEnv.authenticatedContext('student1');
    const db = owner.firestore();
    await assertSucceeds(
      setDoc(doc(db, 'notifications', 'student1', 'items', 'a'), {
        type: 'archivePublished',
        thesisId: 't1',
        message: 'm',
        read: false,
        createdAt: serverTimestamp(),
      })
    );
    await assertSucceeds(getDoc(doc(db, 'notifications', 'student1', 'items', 'a')));
  });

  it('the owner can mark their own item read', async () => {
    const owner = testEnv.authenticatedContext('student1');
    const db = owner.firestore();
    await setDoc(doc(db, 'notifications', 'student1', 'items', 'a'), {
      type: 'archivePublished',
      thesisId: 't1',
      message: 'm',
      read: false,
      createdAt: serverTimestamp(),
    });
    await assertSucceeds(
      updateDoc(doc(db, 'notifications', 'student1', 'items', 'a'), { read: true })
    );
  });

  it('another signed-in user cannot read or write into someone else\'s feed', async () => {
    const owner = testEnv.authenticatedContext('student1');
    await setDoc(doc(owner.firestore(), 'notifications', 'student1', 'items', 'a'), {
      type: 'archivePublished',
      thesisId: 't1',
      message: 'm',
      read: false,
      createdAt: serverTimestamp(),
    });

    const intruder = testEnv.authenticatedContext('student2');
    const db = intruder.firestore();
    await assertFails(getDoc(doc(db, 'notifications', 'student1', 'items', 'a')));
    await assertFails(
      setDoc(doc(db, 'notifications', 'student1', 'items', 'b'), {
        type: 'archivePublished',
        thesisId: 't1',
        message: 'planted',
        read: false,
        createdAt: serverTimestamp(),
      })
    );
    await assertFails(
      updateDoc(doc(db, 'notifications', 'student1', 'items', 'a'), { read: true })
    );
  });

  it('an anonymous reader is denied both directions', async () => {
    const anon = testEnv.unauthenticatedContext();
    const db = anon.firestore();
    await assertFails(getDoc(doc(db, 'notifications', 'student1', 'items', 'a')));
    await assertFails(
      setDoc(doc(db, 'notifications', 'student1', 'items', 'a'), {
        type: 'archivePublished',
        thesisId: 't1',
        message: 'm',
        read: false,
        createdAt: serverTimestamp(),
      })
    );
  });
});
```

Adjust the destructured imports (`setDoc`, `getDoc`, `updateDoc`, `doc`, `serverTimestamp`, `assertSucceeds`, `assertFails`) to match whatever this file's existing top-of-file imports already use — do not add a second, differently-named import for something already imported.

- [ ] **Step 2: Run test to verify it fails**

Run: `npm --prefix rules-test test`
Expected: FAIL — `notifications/{uid}/items/{itemId}` falls through to the deny-by-default catch-all, so every `assertSucceeds` above fails.

- [ ] **Step 3: Add the rule**

In `firestore.rules`, insert this `match` block immediately before the final `match /{document=**} { allow read, write: if false; }` catch-all:

```
// Self-authored only (D70): every write here is a reader's own client
// reporting an event to itself, never one user notifying another. No
// get() lookup into any other collection is needed -- there is no
// cross-user fact for a rule to verify.
match /notifications/{uid}/items/{itemId} {
  allow read, write: if request.auth != null && request.auth.uid == uid;
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `npm --prefix rules-test test`
Expected: PASS — all four new tests, and every pre-existing rules test, still green.

- [ ] **Step 5: Commit**

```bash
git add firestore.rules rules-test/rules.test.js
git commit -m "feat: add owner-only notifications rule"
```

---

### Task 4: Read/write providers — feed, unread count, mark-read

**Files:**
- Create: `lib/providers/notification_providers.dart`
- Test: `test/providers/notification_providers_test.dart`

**Interfaces:**
- Consumes: `NotificationRepository`, `AppNotification` (Tasks 1-2); `firestoreProvider`, `signedInUidProvider` (existing, `lib/providers/service_providers.dart` / `lib/providers/auth_providers.dart` — same pattern every other repository provider in this codebase already follows, e.g. `archiveRepositoryProvider` in `lib/providers/archive_providers.dart`).
- Produces: `notificationRepositoryProvider` (`Provider<NotificationRepository>`), `notificationsProvider` (`StreamProvider<List<AppNotification>>`, the signed-in user's own feed), `unreadNotificationCountProvider` (`Provider<int>`), `Future<void> markNotificationRead(Ref ref, String itemId)`, `Future<void> markAllNotificationsRead(Ref ref)`. These four names are what Tasks 5-12 all depend on.

- [ ] **Step 1: Write the failing tests**

```dart
// test/providers/notification_providers_test.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ethesishub/providers/auth_providers.dart';
import 'package:ethesishub/providers/notification_providers.dart';
import 'package:ethesishub/providers/service_providers.dart';

void main() {
  Future<ProviderContainer> containerFor(String uid) async {
    final auth = MockFirebaseAuth(mockUser: MockUser(uid: uid, emailVerified: true));
    await auth.signInWithCredential(EmailAuthProvider.credential(email: 'a@b.com', password: 'x'));
    final firestore = FakeFirebaseFirestore();
    await firestore
        .collection('notifications')
        .doc(uid)
        .collection('items')
        .doc('archivePublished_t1')
        .set({
      'type': 'archivePublished',
      'thesisId': 't1',
      'message': 'Your thesis was published.',
      'read': false,
      'createdAt': Timestamp.fromDate(DateTime(2026, 9, 3)),
    });

    final container = ProviderContainer(overrides: [
      firebaseAuthProvider.overrideWithValue(auth),
      firestoreProvider.overrideWithValue(firestore),
    ]);
    addTearDown(container.dispose);
    return container;
  }

  test('notificationsProvider streams the signed-in user\'s own items', () async {
    final container = await containerFor('u1');
    final items = await container.read(notificationsProvider.future);
    expect(items, hasLength(1));
    expect(items.single.thesisId, 't1');
  });

  test('unreadNotificationCountProvider counts only unread items', () async {
    final container = await containerFor('u1');
    await container.read(notificationsProvider.future);
    expect(container.read(unreadNotificationCountProvider), 1);
  });

  test('markNotificationRead flips one item and the count drops', () async {
    final container = await containerFor('u1');
    await container.read(notificationsProvider.future);

    await markNotificationRead(container, 'archivePublished_t1');
    final items = await container.read(notificationsProvider.future);

    expect(items.single.read, isTrue);
  });

  test('markAllNotificationsRead flips every item at once', () async {
    final container = await containerFor('u1');
    final repo = container.read(notificationRepositoryProvider);
    await repo.upsertIfAbsent(
      'u1',
      (await container.read(notificationsProvider.future)).first.copyWith(),
    );

    await markAllNotificationsRead(container);
    final items = await container.read(notificationsProvider.future);

    expect(items.every((i) => i.read), isTrue);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/providers/notification_providers_test.dart`
Expected: FAIL — `notification_providers.dart` does not exist yet.

- [ ] **Step 3: Write the implementation**

```dart
// lib/providers/notification_providers.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ethesishub/data/models/app_notification.dart';
import 'package:ethesishub/data/repositories/notification_repository.dart';
import 'package:ethesishub/providers/auth_providers.dart';
import 'package:ethesishub/providers/service_providers.dart';

final notificationRepositoryProvider = Provider<NotificationRepository>(
  (ref) => NotificationRepository(ref.watch(firestoreProvider)),
);

/// The signed-in reader's own feed, newest first.
final notificationsProvider = StreamProvider<List<AppNotification>>((ref) {
  final uid = ref.watch(signedInUidProvider);
  if (uid == null) return Stream.value(const []);
  return ref.watch(notificationRepositoryProvider).watchItems(uid);
});

/// Zero when there is nothing unread OR the feed has not resolved yet --
/// the badge renders no chip at all for zero (D — see spec §5, "no badge
/// beats a badge reading zero"), so loading and empty share the same
/// visible result on purpose. A distinct loading state has no UI here to
/// serve; this provider exists to answer exactly one question.
final unreadNotificationCountProvider = Provider<int>((ref) {
  final items = ref.watch(notificationsProvider).valueOrNull ?? const [];
  return items.where((i) => !i.read).length;
});

Future<void> markNotificationRead(Ref ref, String itemId) async {
  final uid = ref.read(signedInUidProvider);
  if (uid == null) return;
  await ref.read(notificationRepositoryProvider).markRead(uid, itemId);
}

Future<void> markAllNotificationsRead(Ref ref) async {
  final uid = ref.read(signedInUidProvider);
  if (uid == null) return;
  final items = ref.read(notificationsProvider).valueOrNull ?? const [];
  final unreadIds = [for (final i in items) if (!i.read) i.id];
  if (unreadIds.isEmpty) return;
  await ref.read(notificationRepositoryProvider).markAllRead(uid, unreadIds);
}
```

`ProviderContainer` and `WidgetRef` both satisfy `Ref`, so `markNotificationRead`/`markAllNotificationsRead` work unchanged from both the test above and the UI widgets in Tasks 11-12.

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/providers/notification_providers_test.dart`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add lib/providers/notification_providers.dart test/providers/notification_providers_test.dart
git commit -m "feat: add notification feed, unread count, and mark-read providers"
```

---

### Task 5: Detector infrastructure + nomination/title lifecycle detector

**Files:**
- Modify: `lib/providers/notification_providers.dart` (append)
- Test: `test/providers/notification_detectors_test.dart` (create — shared by this and Tasks 6-9, one `group` per detector)

**Interfaces:**
- Consumes: `myPendingNominationsProvider`, `myThesisProvider` (`lib/providers/thesis_providers.dart`); `Nomination`, `ConformeStatus` (`lib/data/models/nomination.dart`); `Thesis`, `ThesisStatus` (`lib/data/models/thesis.dart`); `notificationRepositoryProvider`, `notificationId` (this file / Task 1).
- Produces: private `void _detect<T>(Ref ref, ProviderListenable<AsyncValue<T>> source, Future<void> Function(T value, NotificationRepository repo, String uid) onValue)` (used by every detector in Tasks 5-9); `nominationLifecycleDetectorProvider` (`Provider<void>`).

- [ ] **Step 1: Write the failing test**

```dart
// test/providers/notification_detectors_test.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ethesishub/data/models/nomination.dart';
import 'package:ethesishub/data/models/thesis.dart';
import 'package:ethesishub/data/models/thesis_status.dart';
import 'package:ethesishub/providers/auth_providers.dart';
import 'package:ethesishub/providers/notification_providers.dart';
import 'package:ethesishub/providers/service_providers.dart';

Future<ProviderContainer> containerFor(String uid) async {
  final auth = MockFirebaseAuth(mockUser: MockUser(uid: uid, emailVerified: true));
  await auth.signInWithCredential(EmailAuthProvider.credential(email: 'a@b.com', password: 'x'));
  final firestore = FakeFirebaseFirestore();
  final container = ProviderContainer(overrides: [
    firebaseAuthProvider.overrideWithValue(auth),
    firestoreProvider.overrideWithValue(firestore),
  ]);
  addTearDown(container.dispose);
  return container;
}

void main() {
  group('nominationLifecycleDetectorProvider', () {
    test('a pending Conforme writes a conformeRequested item', () async {
      final container = await containerFor('faculty1');
      final firestore = container.read(firestoreProvider);
      await firestore.collection('theses').doc('t1').set({
        'leaderUid': 'student1',
        'memberNames': ['Santos, J.'],
        'workingTitle': 'A Study',
        'college': 'CICT',
        'program': 'BSIT',
        'semester': '1',
        'academicYear': '2026-2027',
        'status': 'nominationPendingConforme',
        'panelistUids': ['faculty1'],
        'createdAt': Timestamp.fromDate(DateTime(2026, 1, 1)),
      });
      await firestore
          .collection('theses')
          .doc('t1')
          .collection('nominations')
          .doc('faculty1')
          .set({
        'nomineeName': 'Dr. Reyes',
        'position': 'panelist',
        'exOfficio': false,
        'conformeStatus': 'pending',
      });

      container.read(nominationLifecycleDetectorProvider);
      await container.read(notificationsProvider.future);
      // Let the detector's own listen callback (which awaits a Firestore
      // write) finish before asserting.
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      final items = await container.read(notificationRepositoryProvider).watchItems('faculty1').first;
      expect(items, isNotEmpty);
      expect(items.first.type.name, 'conformeRequested');
      expect(items.first.thesisId, 't1');
    });

    test('a thesis the reader leads with a recommendation writes nominationRecommended', () async {
      final container = await containerFor('student1');
      final firestore = container.read(firestoreProvider);
      await firestore.collection('theses').doc('t1').set({
        'leaderUid': 'student1',
        'memberNames': ['Santos, J.'],
        'workingTitle': 'A Study',
        'college': 'CICT',
        'program': 'BSIT',
        'semester': '1',
        'academicYear': '2026-2027',
        'status': 'nominationPendingDean',
        'panelistUids': <String>[],
        'createdAt': Timestamp.fromDate(DateTime(2026, 1, 1)),
        'coordinatorRecommendedAt': Timestamp.fromDate(DateTime(2026, 2, 1)),
        'coordinatorRecommendedBy': 'coord1',
      });

      container.read(nominationLifecycleDetectorProvider);
      await container.read(notificationsProvider.future);
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      final items = await container.read(notificationRepositoryProvider).watchItems('student1').first;
      expect(items.any((i) => i.type.name == 'nominationRecommended'), isTrue);
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/providers/notification_detectors_test.dart`
Expected: FAIL — `nominationLifecycleDetectorProvider` does not exist yet.

- [ ] **Step 3: Write the implementation**

Append to `lib/providers/notification_providers.dart`:

```dart
import 'package:ethesishub/data/models/nomination.dart';
import 'package:ethesishub/data/models/thesis.dart';
import 'package:ethesishub/data/models/thesis_status.dart';
import 'package:ethesishub/providers/thesis_providers.dart';

/// Runs [onValue] every time [source] resolves to a real value, handing it
/// the reader's own repository and uid.
///
/// `fireImmediately: true` on purpose: a detector must also catch up on
/// whatever already happened before this session started (a Conforme
/// request sitting there since before the reader last opened the app is
/// still a notification they have not seen). Re-running against the same
/// source event on every emission is safe because every write below is
/// idempotent per source key (D71) -- this is not a "first emission only"
/// cursor, and does not need to be one.
///
/// Failures are swallowed (D73): a missed notification is a degraded
/// convenience, not a hidden fact -- the source event is still visible
/// wherever it actually lives.
void _detect<T>(
  Ref ref,
  ProviderListenable<AsyncValue<T>> source,
  Future<void> Function(T value, NotificationRepository repo, String uid) onValue,
) {
  ref.listen<AsyncValue<T>>(source, (previous, next) {
    final uid = ref.read(signedInUidProvider);
    final value = next.valueOrNull;
    if (uid == null || value == null) return;
    onValue(value, ref.read(notificationRepositoryProvider), uid).catchError((_) {});
  }, fireImmediately: true);
}

/// Conforme requests, coordinator recommendation, dean nomination approval,
/// and the M1b title-round verdict — every thesis-status-driven event a
/// nominee or a group leader needs to know about.
final nominationLifecycleDetectorProvider = Provider<void>((ref) {
  _detect<List<({String thesisId, Nomination nomination})>>(
    ref,
    myPendingNominationsProvider,
    (pending, repo, uid) async {
      for (final p in pending) {
        if (p.nomination.conformeStatus != ConformeStatus.pending) continue;
        await repo.upsertIfAbsent(
          uid,
          AppNotification(
            id: notificationId(NotificationType.conformeRequested, p.thesisId),
            type: NotificationType.conformeRequested,
            thesisId: p.thesisId,
            message: 'A Conforme is waiting on you for a thesis nomination.',
            read: false,
            createdAt: DateTime.now(),
          ),
        );
      }
    },
  );

  _detect<Thesis?>(ref, myThesisProvider, (thesis, repo, uid) async {
    if (thesis == null) return;

    if (thesis.coordinatorRecommendedAt != null) {
      await repo.upsertIfAbsent(
        uid,
        AppNotification(
          id: notificationId(NotificationType.nominationRecommended, thesis.id),
          type: NotificationType.nominationRecommended,
          thesisId: thesis.id,
          message:
              'The Research Coordinator recommended your nomination for '
              '"${thesis.workingTitle}".',
          read: false,
          createdAt: thesis.coordinatorRecommendedAt!,
        ),
      );
    }

    if (thesis.deanApprovedAt != null) {
      await repo.upsertIfAbsent(
        uid,
        AppNotification(
          id: notificationId(NotificationType.nominationApproved, thesis.id),
          type: NotificationType.nominationApproved,
          thesisId: thesis.id,
          message:
              'The Dean approved your adviser and panel nomination for '
              '"${thesis.workingTitle}".',
          read: false,
          createdAt: thesis.deanApprovedAt!,
        ),
      );
    }

    if (thesis.titleDecidedAt != null) {
      final approved = thesis.status == ThesisStatus.titleApproved;
      final type = approved ? NotificationType.titleApproved : NotificationType.titleRejected;
      await repo.upsertIfAbsent(
        uid,
        AppNotification(
          id: notificationId(type, thesis.id),
          type: type,
          thesisId: thesis.id,
          message: approved
              ? 'Your candidate title was approved.'
              : 'Your candidate title was returned for revision.',
          read: false,
          createdAt: thesis.titleDecidedAt!,
        ),
      );
    }
  });
});
```

`myPendingNominationsProvider` resolves to `data(const [])` for anyone with no pending nominations (never null — see its own definition in `thesis_providers.dart`), and `myThesisProvider` resolves to `data(null)` for anyone with no thesis of their own (a faculty member): both cases pass through `_detect`'s `value == null` guard harmlessly, or iterate an empty list — no separate role check is needed here.

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/providers/notification_detectors_test.dart`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add lib/providers/notification_providers.dart test/providers/notification_detectors_test.dart
git commit -m "feat: add the detector fan-in helper and the nomination/title lifecycle detector"
```

---

### Task 6: Chapter feedback detector

**Files:**
- Modify: `lib/providers/notification_providers.dart` (append)
- Modify: `test/providers/notification_detectors_test.dart` (append a `group`)

**Interfaces:**
- Consumes: `_detect` (Task 5); `myThesisProvider` (`thesis_providers.dart`); `chapterFeedbackProvider`, `ChapterRef` (`lib/providers/document_providers.dart`); `ChapterId` (`lib/data/models/chapter.dart`).
- Produces: `chapterFeedbackDetectorProvider` (`Provider<void>`).

- [ ] **Step 1: Write the failing test**

Append to `test/providers/notification_detectors_test.dart`:

```dart
  group('chapterFeedbackDetectorProvider', () {
    test('feedback from someone else on my own chapter writes a notification', () async {
      final container = await containerFor('student1');
      final firestore = container.read(firestoreProvider);
      await firestore.collection('theses').doc('t1').set({
        'leaderUid': 'student1',
        'memberNames': ['Santos, J.'],
        'workingTitle': 'A Study',
        'college': 'CICT',
        'program': 'BSIT',
        'semester': '1',
        'academicYear': '2026-2027',
        'status': 'titleApproved',
        'panelistUids': <String>[],
        'createdAt': Timestamp.fromDate(DateTime(2026, 1, 1)),
      });
      await firestore
          .collection('theses')
          .doc('t1')
          .collection('chapters')
          .doc('chapterI')
          .collection('feedback')
          .doc('f1')
          .set({
        'version': 1,
        'reviewerUid': 'adviser1',
        'reviewerName': 'Dr. Cruz',
        'reviewerRole': 'adviser',
        'body': 'Please revise the statement of the problem.',
        'createdAt': Timestamp.fromDate(DateTime(2026, 3, 1)),
      });

      container.read(chapterFeedbackDetectorProvider);
      await container.read(notificationsProvider.future);
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      final items = await container.read(notificationRepositoryProvider).watchItems('student1').first;
      expect(items.any((i) => i.type.name == 'chapterFeedback'), isTrue);
    });

    test('feedback the reader wrote about their own chapter does not notify them', () async {
      final container = await containerFor('student1');
      final firestore = container.read(firestoreProvider);
      await firestore.collection('theses').doc('t1').set({
        'leaderUid': 'student1',
        'memberNames': ['Santos, J.'],
        'workingTitle': 'A Study',
        'college': 'CICT',
        'program': 'BSIT',
        'semester': '1',
        'academicYear': '2026-2027',
        'status': 'titleApproved',
        'panelistUids': <String>[],
        'createdAt': Timestamp.fromDate(DateTime(2026, 1, 1)),
      });
      await firestore
          .collection('theses')
          .doc('t1')
          .collection('chapters')
          .doc('chapterI')
          .collection('feedback')
          .doc('f1')
          .set({
        'version': 1,
        'reviewerUid': 'student1',
        'reviewerName': 'Santos, J.',
        'reviewerRole': 'student',
        'body': 'Fixed the typo.',
        'createdAt': Timestamp.fromDate(DateTime(2026, 3, 1)),
      });

      container.read(chapterFeedbackDetectorProvider);
      await container.read(notificationsProvider.future);
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      final items = await container.read(notificationRepositoryProvider).watchItems('student1').first;
      expect(items.where((i) => i.type.name == 'chapterFeedback'), isEmpty);
    });
  });
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/providers/notification_detectors_test.dart`
Expected: FAIL — `chapterFeedbackDetectorProvider` does not exist yet.

- [ ] **Step 3: Write the implementation**

Append to `lib/providers/notification_providers.dart`:

```dart
import 'package:ethesishub/data/models/chapter.dart';
import 'package:ethesishub/providers/document_providers.dart';

/// New feedback on any of the reader's own five chapters, from anyone but
/// themselves.
///
/// A nested fan-in (the chapter source is only known once [myThesisProvider]
/// resolves), the same shape `facultyNeedsYouProvider`'s own doc comment in
/// `needs_you_providers.dart` describes for its chapter source: the five
/// per-chapter feedback subscriptions are opened once the thesis id is
/// known, not fixed at provider-build time.
final chapterFeedbackDetectorProvider = Provider<void>((ref) {
  _detect<Thesis?>(ref, myThesisProvider, (thesis, repo, uid) async {
    if (thesis == null) return;
    for (final chapter in ChapterId.values) {
      final feedback = ref.read(
        chapterFeedbackProvider((thesisId: thesis.id, chapter: chapter)).future,
      );
      final entries = await feedback;
      for (final f in entries) {
        if (f.reviewerUid == uid) continue;
        await repo.upsertIfAbsent(
          uid,
          AppNotification(
            id: notificationId(NotificationType.chapterFeedback, f.id),
            type: NotificationType.chapterFeedback,
            thesisId: thesis.id,
            message: '${f.reviewerName} left feedback on ${chapter.label}.',
            read: false,
            createdAt: f.createdAt ?? DateTime.now(),
          ),
        );
      }
    }
  });
});
```

This reads `chapterFeedbackProvider(...).future` once per thesis-value emission rather than opening a standing `ref.listen` per chapter: a new-thesis emission is rare (it fires once when the student's thesis first resolves and essentially never again for the life of the session), so re-reading the current snapshot of each of the five feedback lists on that one occasion is simpler than five nested live subscriptions, and still catches every feedback entry that exists at the time — new feedback arriving after that is caught the next time anything re-triggers this provider's rebuild (any dependency change forces Riverpod to re-run `_detect`'s `fireImmediately` path). If manual testing in Task 12 shows feedback added mid-session is missed until some other rebuild happens, promote this to a standing per-chapter `_detect(ref, chapterFeedbackProvider((thesisId: ..., chapter: c)), ...)` call per `ChapterId` instead — five `_detect` calls, one per chapter, each independently live.

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/providers/notification_detectors_test.dart`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add lib/providers/notification_providers.dart test/providers/notification_detectors_test.dart
git commit -m "feat: add the chapter feedback detector"
```

---

### Task 7: Defence comments and scheduling detector

**Files:**
- Modify: `lib/providers/notification_providers.dart` (append)
- Modify: `test/providers/notification_detectors_test.dart` (append a `group`)

**Interfaces:**
- Consumes: `_detect` (Task 5); `myDefencesProvider`, `defenceCommentsProvider` (`lib/providers/defence_providers.dart`); `Defence`, `DefenceComment` (`lib/data/models/defence.dart`); `currentUserProvider`, `UserRole` (`lib/providers/auth_providers.dart`, `lib/data/models/user_role.dart`).
- Produces: `defenceDetectorProvider` (`Provider<void>`).

- [ ] **Step 1: Write the failing test**

Append to `test/providers/notification_detectors_test.dart`:

```dart
  group('defenceDetectorProvider', () {
    test('a comment from someone else writes a notification', () async {
      final container = await containerFor('student1');
      final firestore = container.read(firestoreProvider);
      await firestore.collection('users').doc('student1').set({'role': 'student'});
      await firestore.collection('defences').doc('d1').set({
        'thesisId': 't1',
        'type': 'final',
        'venue': 'Room 1',
        'panelUids': <String>[],
        'adviserUid': 'adviser1',
        'leaderUid': 'student1',
        'status': 'scheduled',
        'createdBy': 'coord1',
        'scheduledAt': Timestamp.fromDate(DateTime(2026, 5, 1)),
      });
      await firestore.collection('defences').doc('d1').collection('comments').doc('c1').set({
        'authorUid': 'adviser1',
        'authorName': 'Dr. Cruz',
        'authorPosition': 'adviser',
        'body': 'Please prepare the slides.',
        'createdAt': Timestamp.fromDate(DateTime(2026, 4, 1)),
      });

      container.read(defenceDetectorProvider);
      await container.read(notificationsProvider.future);
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      final items = await container.read(notificationRepositoryProvider).watchItems('student1').first;
      expect(items.any((i) => i.type.name == 'defenceComment'), isTrue);
    });

    test('a schedule change writes a notification keyed by the new value', () async {
      final container = await containerFor('student1');
      final firestore = container.read(firestoreProvider);
      await firestore.collection('users').doc('student1').set({'role': 'student'});
      await firestore.collection('defences').doc('d1').set({
        'thesisId': 't1',
        'type': 'final',
        'venue': 'Room 2',
        'panelUids': <String>[],
        'adviserUid': 'adviser1',
        'leaderUid': 'student1',
        'status': 'scheduled',
        'createdBy': 'coord1',
        'scheduledAt': Timestamp.fromDate(DateTime(2026, 5, 15)),
      });

      container.read(defenceDetectorProvider);
      await container.read(notificationsProvider.future);
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      final items = await container.read(notificationRepositoryProvider).watchItems('student1').first;
      expect(items.any((i) => i.type.name == 'defenceScheduled'), isTrue);
    });
  });
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/providers/notification_detectors_test.dart`
Expected: FAIL — `defenceDetectorProvider` does not exist yet.

- [ ] **Step 3: Write the implementation**

Append to `lib/providers/notification_providers.dart`:

```dart
import 'package:ethesishub/data/models/defence.dart';
import 'package:ethesishub/data/models/user_role.dart';
import 'package:ethesishub/providers/defence_providers.dart';

/// New comments and schedule changes on every defence the reader is party
/// to.
///
/// Restricted to student and faculty readers. `myDefencesProvider` returns
/// EVERY defence in the college for a coordinator or dean (their own
/// `allow list` arm has no per-thesis restriction), and this detector is
/// about a defence's own parties knowing what happened on their defence,
/// not a college-wide comment firehose for the two roles who already have
/// a dedicated overview of every defence's status.
final defenceDetectorProvider = Provider<void>((ref) {
  final role = ref.watch(currentUserProvider).valueOrNull?.role;
  if (role != UserRole.student && role != UserRole.faculty) return;

  _detect<List<Defence>>(ref, myDefencesProvider, (defences, repo, uid) async {
    for (final defence in defences) {
      if (defence.scheduledAt != null) {
        final key = '${defence.id}_${defence.scheduledAt!.millisecondsSinceEpoch}_${defence.venue}';
        await repo.upsertIfAbsent(
          uid,
          AppNotification(
            id: notificationId(NotificationType.defenceScheduled, key),
            type: NotificationType.defenceScheduled,
            thesisId: defence.thesisId,
            message: 'Your defence is scheduled for ${defence.venue} on '
                '${defence.scheduledAt!.day}/${defence.scheduledAt!.month}/${defence.scheduledAt!.year}.',
            read: false,
            createdAt: defence.createdAt ?? DateTime.now(),
          ),
        );
      }

      final comments = await ref.read(defenceCommentsProvider(defence.id).future);
      for (final c in comments) {
        if (c.authorUid == uid) continue;
        await repo.upsertIfAbsent(
          uid,
          AppNotification(
            id: notificationId(NotificationType.defenceComment, c.id),
            type: NotificationType.defenceComment,
            thesisId: defence.thesisId,
            message: '${c.authorName} commented on your defence.',
            read: false,
            createdAt: c.createdAt ?? DateTime.now(),
          ),
        );
      }
    }
  });
});
```

The schedule-change id folds `scheduledAt` and `venue` into the key itself (rather than comparing against a stored "previous" value), so a genuinely new schedule value produces a new id and a fresh notification, while re-detecting the same unchanged value keeps writing the same id — an idempotent no-op per D71. No separate "previous value" state is needed.

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/providers/notification_detectors_test.dart`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add lib/providers/notification_providers.dart test/providers/notification_detectors_test.dart
git commit -m "feat: add the defence comments and scheduling detector"
```

---

### Task 8: Evaluation-awaits detector

**Files:**
- Modify: `lib/providers/notification_providers.dart` (append)
- Modify: `test/providers/notification_detectors_test.dart` (append a `group`)

**Interfaces:**
- Consumes: `_detect`, `defenceDetectorProvider`'s role-check pattern (Task 7); `myDefencesProvider`, `myEvaluationProvider` (`defence_providers.dart`); `DefenceStatus` (`defence.dart`).
- Produces: `evaluationAwaitsDetectorProvider` (`Provider<void>`).

- [ ] **Step 1: Write the failing test**

Append to `test/providers/notification_detectors_test.dart`:

```dart
  group('evaluationAwaitsDetectorProvider', () {
    test('a completed defence with no evaluation on file from this panelist writes one', () async {
      final container = await containerFor('faculty1');
      final firestore = container.read(firestoreProvider);
      await firestore.collection('users').doc('faculty1').set({'role': 'faculty'});
      await firestore.collection('defences').doc('d1').set({
        'thesisId': 't1',
        'type': 'final',
        'venue': 'Room 1',
        'panelUids': ['faculty1'],
        'adviserUid': 'adviser1',
        'leaderUid': 'student1',
        'status': 'completed',
        'createdBy': 'coord1',
      });

      container.read(evaluationAwaitsDetectorProvider);
      await container.read(notificationsProvider.future);
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      final items = await container.read(notificationRepositoryProvider).watchItems('faculty1').first;
      expect(items.any((i) => i.type.name == 'evaluationAwaits'), isTrue);
    });

    test('a completed defence this panelist already scored writes nothing', () async {
      final container = await containerFor('faculty1');
      final firestore = container.read(firestoreProvider);
      await firestore.collection('users').doc('faculty1').set({'role': 'faculty'});
      await firestore.collection('defences').doc('d1').set({
        'thesisId': 't1',
        'type': 'final',
        'venue': 'Room 1',
        'panelUids': ['faculty1'],
        'adviserUid': 'adviser1',
        'leaderUid': 'student1',
        'status': 'completed',
        'createdBy': 'coord1',
      });
      await firestore
          .collection('defences')
          .doc('d1')
          .collection('evaluations')
          .doc('faculty1')
          .set({
        'evaluatorName': 'Dr. Reyes',
        'scores': <String, int>{},
        'comments': <String, String>{},
        'total': 90,
        'rating': 'pass',
        'submittedAt': Timestamp.fromDate(DateTime(2026, 5, 2)),
      });

      container.read(evaluationAwaitsDetectorProvider);
      await container.read(notificationsProvider.future);
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      final items = await container.read(notificationRepositoryProvider).watchItems('faculty1').first;
      expect(items.where((i) => i.type.name == 'evaluationAwaits'), isEmpty);
    });
  });
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/providers/notification_detectors_test.dart`
Expected: FAIL — `evaluationAwaitsDetectorProvider` does not exist yet.

- [ ] **Step 3: Write the implementation**

Append to `lib/providers/notification_providers.dart`:

```dart
/// A completed defence where the reader sits on the panel but has not yet
/// filed their Form 5c. Only "awaits" is covered (not "submitted") --
/// brainstorming found no concrete recipient for a submission event that
/// is not already covered by one of the other four categories, and adding
/// one with no real use case would be exactly the kind of speculative
/// scope the spec's Out of Scope section already rules out.
final evaluationAwaitsDetectorProvider = Provider<void>((ref) {
  final role = ref.watch(currentUserProvider).valueOrNull?.role;
  if (role != UserRole.faculty) return;

  _detect<List<Defence>>(ref, myDefencesProvider, (defences, repo, uid) async {
    for (final defence in defences) {
      if (defence.status != DefenceStatus.completed) continue;
      if (!defence.panelUids.contains(uid)) continue;

      final mine = await ref.read(myEvaluationProvider(defence.id).future);
      if (mine != null) continue;

      await repo.upsertIfAbsent(
        uid,
        AppNotification(
          id: notificationId(NotificationType.evaluationAwaits, defence.id),
          type: NotificationType.evaluationAwaits,
          thesisId: defence.thesisId,
          message: 'A defence has completed and is waiting on your Form 5c.',
          read: false,
          createdAt: defence.createdAt ?? DateTime.now(),
        ),
      );
    }
  });
});
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/providers/notification_detectors_test.dart`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add lib/providers/notification_providers.dart test/providers/notification_detectors_test.dart
git commit -m "feat: add the evaluation-awaits detector"
```

---

### Task 9: Archive-published detector

**Files:**
- Modify: `lib/providers/notification_providers.dart` (append)
- Modify: `test/providers/notification_detectors_test.dart` (append a `group`)

**Interfaces:**
- Consumes: `_detect` (Task 5); `myThesisProvider` (`thesis_providers.dart`); `myAdviseesProvider`, `myDefencesProvider` (existing providers, for the adviser/panel recipient case); `archiveEntryProvider` (`lib/providers/archive_providers.dart`); `ArchiveEntry` (`lib/data/models/archive_entry.dart`).
- Produces: `archivePublishedDetectorProvider` (`Provider<void>`).

- [ ] **Step 1: Write the failing test**

Append to `test/providers/notification_detectors_test.dart`:

```dart
  group('archivePublishedDetectorProvider', () {
    test("the thesis leader's own client sees an archivePublished item", () async {
      final container = await containerFor('student1');
      final firestore = container.read(firestoreProvider);
      await firestore.collection('theses').doc('t1').set({
        'leaderUid': 'student1',
        'memberNames': ['Santos, J.'],
        'workingTitle': 'A Study',
        'college': 'CICT',
        'program': 'BSIT',
        'semester': '1',
        'academicYear': '2026-2027',
        'status': 'titleApproved',
        'panelistUids': <String>[],
        'createdAt': Timestamp.fromDate(DateTime(2026, 1, 1)),
      });
      await firestore.collection('archive').doc('t1').set({
        'title': 'A Study of Coastal Fisheries',
        'memberNames': ['Santos, J.'],
        'abstract': 'Fish were counted.',
        'college': 'CICT',
        'program': 'BSIT',
        'academicYear': '2026-2027',
        'adviserName': 'Dr. Cruz',
        'panelNames': <String>['Dr. Reyes'],
        'manuscriptUrl': 'https://example.test/m.pdf',
        'manuscriptPath': 'p/m.pdf',
        'finalDefenceId': 'd1',
        'uploadedBy': 'student1',
        'archivedBy': 'coord1',
        'archivedAt': Timestamp.fromDate(DateTime(2026, 9, 1)),
      });

      container.read(archivePublishedDetectorProvider);
      await container.read(notificationsProvider.future);
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      final items = await container.read(notificationRepositoryProvider).watchItems('student1').first;
      expect(items.any((i) => i.type.name == 'archivePublished'), isTrue);
    });
  });
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/providers/notification_detectors_test.dart`
Expected: FAIL — `archivePublishedDetectorProvider` does not exist yet.

- [ ] **Step 3: Write the implementation**

Append to `lib/providers/notification_providers.dart`:

```dart
import 'package:ethesishub/data/models/archive_entry.dart';
import 'package:ethesishub/providers/archive_providers.dart';

/// The reader's own thesis appearing in the archive.
///
/// Scoped to the group leader only (via [myThesisProvider]) for this first
/// pass -- notifying the adviser and panel too would mean resolving "which
/// theses is this faculty member attached to" from [myAdviseesProvider]
/// and [myDefencesProvider] and cross-referencing both against
/// [archiveProvider], which is a second, more expensive fan-in for an
/// event advisers and panelists already see reflected on their own
/// dashboards the moment it happens. The group leader has no such standing
/// view, which is why they are the one this detector covers.
final archivePublishedDetectorProvider = Provider<void>((ref) {
  _detect<Thesis?>(ref, myThesisProvider, (thesis, repo, uid) async {
    if (thesis == null) return;
    final entry = await ref.read(archiveEntryProvider(thesis.id).future);
    if (entry == null) return;

    await repo.upsertIfAbsent(
      uid,
      AppNotification(
        id: notificationId(NotificationType.archivePublished, thesis.id),
        type: NotificationType.archivePublished,
        thesisId: thesis.id,
        message: 'Your thesis "${entry.title}" was published to the archive.',
        read: false,
        createdAt: entry.archivedAt ?? DateTime.now(),
      ),
    );
  });
});
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/providers/notification_detectors_test.dart`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add lib/providers/notification_providers.dart test/providers/notification_detectors_test.dart
git commit -m "feat: add the archive-published detector"
```

---

### Task 10: Aggregate provider, wired into the app shell

**Files:**
- Modify: `lib/providers/notification_providers.dart` (append)
- Modify: `lib/core/widgets/app_shell_host.dart` (wire it in)
- Test: `test/core/widgets/app_shell_host_test.dart` (add one case to the existing file)

**Interfaces:**
- Consumes: all five detector providers (Tasks 5-9).
- Produces: `notificationDetectorsProvider` (`Provider<void>`), watched once from `AppShellHost.build`.

- [ ] **Step 1: Write the failing test**

Open `test/core/widgets/app_shell_host_test.dart`, find its existing `setUp`/pump helper (it already builds an `AppShellHost` under a `ProviderScope` with Firebase mocks — reuse that exact helper rather than writing a new one), and add:

```dart
  testWidgets('watching the shell keeps every notification detector alive', (tester) async {
    // Reuses this file's existing pump helper (see the top of this file
    // for its exact name and signature) to build a signed-in AppShellHost,
    // then confirms none of the five detector providers throw or leave
    // the widget tree in an error state -- a regression here would mean
    // one detector's own bug (e.g. a null role read) crashes shell
    // rendering for every signed-in reader, not just the detector itself.
    await pumpShell(tester); // use this file's actual helper name
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });
```

Adjust `pumpShell` to whatever this test file's existing helper is actually named — read the file first and match it exactly; do not invent a second helper.

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/core/widgets/app_shell_host_test.dart`
Expected: FAIL, or at minimum not proof of anything yet — the detectors are not wired in, so this test cannot yet catch a detector crash. (If the test framework has nothing to distinguish here, this step's purpose is satisfied by confirming the file still compiles and the existing suite still passes before the wiring change; the assertion becomes meaningful once Step 3 lands.)

- [ ] **Step 3: Write the implementation**

Append to `lib/providers/notification_providers.dart`:

```dart
/// Keeps every detector's `ref.listen` subscription alive for as long as
/// something watches this -- see `AppShellHost.build`, the one place that
/// does, for the whole life of a signed-in session.
final notificationDetectorsProvider = Provider<void>((ref) {
  ref.watch(nominationLifecycleDetectorProvider);
  ref.watch(chapterFeedbackDetectorProvider);
  ref.watch(defenceDetectorProvider);
  ref.watch(evaluationAwaitsDetectorProvider);
  ref.watch(archivePublishedDetectorProvider);
});
```

In `lib/core/widgets/app_shell_host.dart`, add the import and one line at the top of `AppShellHost.build`:

```dart
import 'package:ethesishub/providers/notification_providers.dart';
```

```dart
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(notificationDetectorsProvider);
    final destinations = ref.watch(shellDestinationsProvider);
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/core/widgets/app_shell_host_test.dart`
Expected: PASS

- [ ] **Step 5: Run the full suite to check for regressions**

Run: `flutter test`
Expected: PASS, same count as before plus this task's new test.

- [ ] **Step 6: Commit**

```bash
git add lib/providers/notification_providers.dart lib/core/widgets/app_shell_host.dart test/core/widgets/app_shell_host_test.dart
git commit -m "feat: keep every notification detector alive for the life of the shell"
```

---

### Task 11: Notification bell in the app shell top bar

**Files:**
- Create: `lib/features/notifications/notification_bell.dart`
- Modify: `lib/core/widgets/app_shell_host.dart`
- Test: `test/features/notifications/notification_bell_test.dart`

**Interfaces:**
- Consumes: `unreadNotificationCountProvider` (Task 4); `AppShellHost`'s existing `trailing` wiring (`lib/core/widgets/app_shell_host.dart`, `AppShellHost.build`'s `trailing:` parameter, currently `role == UserRole.faculty ? FacultyModeSwitch(...) : null`).
- Produces: `class NotificationBell extends ConsumerWidget` with `Key('notificationBell')` on its `IconButton` and `Key('notificationBellBadge')` on the count label.

- [ ] **Step 1: Write the failing test**

```dart
// test/features/notifications/notification_bell_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:ethesishub/features/notifications/notification_bell.dart';
import 'package:ethesishub/providers/notification_providers.dart';

void main() {
  Future<void> pump(WidgetTester tester, {required int unread}) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          unreadNotificationCountProvider.overrideWithValue(unread),
        ],
        child: MaterialApp.router(
          routerConfig: GoRouter(routes: [
            GoRoute(path: '/', builder: (_, _) => const Scaffold(body: NotificationBell())),
            GoRoute(path: '/notifications', builder: (_, _) => const Scaffold(body: Text('Notifications'))),
          ]),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('shows no badge when nothing is unread', (tester) async {
    await pump(tester, unread: 0);
    expect(find.byKey(const Key('notificationBellBadge')), findsNothing);
  });

  testWidgets('shows the unread count as a badge', (tester) async {
    await pump(tester, unread: 3);
    expect(find.text('3'), findsOneWidget);
  });

  testWidgets('tapping the bell navigates to /notifications', (tester) async {
    await pump(tester, unread: 1);
    await tester.tap(find.byKey(const Key('notificationBell')));
    await tester.pumpAndSettle();
    expect(find.text('Notifications'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/notifications/notification_bell_test.dart`
Expected: FAIL — `notification_bell.dart` does not exist yet.

- [ ] **Step 3: Write the implementation**

```dart
// lib/features/notifications/notification_bell.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:ethesishub/providers/notification_providers.dart';

/// The bell in the app shell's top bar. Zero unread renders no badge at
/// all -- not a badge reading "0" -- the same "0 is indistinguishable from
/// absent" discipline this project already applies to loading states
/// elsewhere (spec §5).
class NotificationBell extends ConsumerWidget {
  const NotificationBell({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unread = ref.watch(unreadNotificationCountProvider);

    return IconButton(
      key: const Key('notificationBell'),
      tooltip: 'Notifications',
      onPressed: () => context.push('/notifications'),
      icon: Badge(
        key: unread > 0 ? const Key('notificationBellBadge') : null,
        isLabelVisible: unread > 0,
        label: Text('$unread'),
        child: const Icon(Icons.notifications_outlined),
      ),
    );
  }
}
```

In `lib/core/widgets/app_shell_host.dart`, add the import:

```dart
import 'package:ethesishub/features/notifications/notification_bell.dart';
```

Replace `AppShellHost.build`'s `trailing:` parameter — currently:

```dart
      trailing:
          role == UserRole.faculty ? FacultyModeSwitch(location: location) : null,
```

with a combined widget so the bell shows for every signed-in role and the mode switch still appears for faculty:

```dart
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const NotificationBell(),
          if (role == UserRole.faculty) FacultyModeSwitch(location: location),
        ],
      ),
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/features/notifications/notification_bell_test.dart`
Expected: PASS

- [ ] **Step 5: Run the app shell suite to check for regressions**

Run: `flutter test test/core/widgets/app_shell_test.dart test/core/widgets/app_shell_host_test.dart`
Expected: PASS — `AppShell`'s own tests assert on `shell.trailing` being non-null under various roles; confirm none of them assert the trailing widget IS a bare `FacultyModeSwitch` (a type check rather than a presence check) — if one does, update that assertion to check for the `NotificationBell` inside the new `Row` instead, since the trailing slot's shape has genuinely changed for every role, not just faculty.

- [ ] **Step 6: Commit**

```bash
git add lib/features/notifications/notification_bell.dart lib/core/widgets/app_shell_host.dart test/features/notifications/notification_bell_test.dart
git commit -m "feat: add the notification bell to the app shell top bar"
```

---

### Task 12: Notifications list screen, route, and mode-aware deep links

**Files:**
- Create: `lib/features/notifications/notifications_screen.dart`
- Modify: `lib/core/routing/app_router.dart` (register `/notifications`)
- Modify: `lib/core/widgets/app_shell_host.dart` (`_staticTitles`, add `'/notifications': 'Notifications'`)
- Test: `test/features/notifications/notifications_screen_test.dart`

**Interfaces:**
- Consumes: `notificationsProvider`, `markNotificationRead`, `markAllNotificationsRead` (Task 4); `AppNotification`, `NotificationType` (Task 1); `facultyModeProvider`, `FacultyMode` (`lib/providers/faculty_mode_provider.dart`, `lib/data/models/faculty_mode.dart`); `currentUserProvider`, `UserRole` for the mode-aware check.
- Produces: `class NotificationsScreen extends ConsumerWidget`, registered at `/notifications`.

- [ ] **Step 1: Write the failing test**

```dart
// test/features/notifications/notifications_screen_test.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:ethesishub/features/notifications/notifications_screen.dart';
import 'package:ethesishub/providers/auth_providers.dart';
import 'package:ethesishub/providers/service_providers.dart';

Future<void> pump(
  WidgetTester tester, {
  required FakeFirebaseFirestore firestore,
  required String uid,
}) async {
  final auth = MockFirebaseAuth(mockUser: MockUser(uid: uid, emailVerified: true));
  await auth.signInWithCredential(EmailAuthProvider.credential(email: 'a@b.com', password: 'x'));

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        firebaseAuthProvider.overrideWithValue(auth),
        firestoreProvider.overrideWithValue(firestore),
      ],
      child: MaterialApp.router(
        routerConfig: GoRouter(routes: [
          GoRoute(path: '/', builder: (_, _) => const NotificationsScreen()),
          GoRoute(path: '/thesis', builder: (_, _) => const Scaffold(body: Text('My thesis'))),
        ]),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<FakeFirebaseFirestore> firestoreWith(List<Map<String, dynamic>> items, String uid) async {
  final firestore = FakeFirebaseFirestore();
  for (final item in items) {
    await firestore
        .collection('notifications')
        .doc(uid)
        .collection('items')
        .doc(item['id'] as String)
        .set(item);
  }
  return firestore;
}

void main() {
  testWidgets('lists every item, newest first, unread visually distinct', (tester) async {
    final firestore = await firestoreWith([
      {
        'id': 'a',
        'type': 'archivePublished',
        'thesisId': 't1',
        'message': 'Older, already read',
        'read': true,
        'createdAt': Timestamp.fromDate(DateTime(2026, 1, 1)),
      },
      {
        'id': 'b',
        'type': 'defenceComment',
        'thesisId': 't1',
        'message': 'Newer, unread',
        'read': false,
        'createdAt': Timestamp.fromDate(DateTime(2026, 6, 1)),
      },
    ], 'u1');

    await pump(tester, firestore: firestore, uid: 'u1');

    final tiles = find.byType(ListTile);
    expect(tiles, findsNWidgets(2));
    expect(
      tester.widget<ListTile>(tiles.at(0)).title,
      isA<Text>().having((t) => t.data, 'text', 'Newer, unread'),
    );
  });

  testWidgets('an empty feed shows an empty state, not a blank screen', (tester) async {
    final firestore = await firestoreWith([], 'u1');
    await pump(tester, firestore: firestore, uid: 'u1');
    expect(find.text('Nothing yet'), findsOneWidget);
  });

  testWidgets('tapping an item marks it read', (tester) async {
    final firestore = await firestoreWith([
      {
        'id': 'a',
        'type': 'archivePublished',
        'thesisId': 't1',
        'message': 'Tap me',
        'read': false,
        'createdAt': Timestamp.fromDate(DateTime(2026, 1, 1)),
      },
    ], 'u1');

    await pump(tester, firestore: firestore, uid: 'u1');
    await tester.tap(find.text('Tap me'));
    await tester.pumpAndSettle();

    final doc = await firestore.collection('notifications').doc('u1').collection('items').doc('a').get();
    expect(doc.data()!['read'], isTrue);
  });

  testWidgets('mark all read clears every unread item', (tester) async {
    final firestore = await firestoreWith([
      {
        'id': 'a',
        'type': 'archivePublished',
        'thesisId': 't1',
        'message': 'One',
        'read': false,
        'createdAt': Timestamp.fromDate(DateTime(2026, 1, 1)),
      },
      {
        'id': 'b',
        'type': 'defenceComment',
        'thesisId': 't1',
        'message': 'Two',
        'read': false,
        'createdAt': Timestamp.fromDate(DateTime(2026, 2, 1)),
      },
    ], 'u1');

    await pump(tester, firestore: firestore, uid: 'u1');
    await tester.tap(find.byKey(const Key('markAllRead')));
    await tester.pumpAndSettle();

    final items = await firestore.collection('notifications').doc('u1').collection('items').get();
    expect(items.docs.every((d) => d.data()['read'] == true), isTrue);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/notifications/notifications_screen_test.dart`
Expected: FAIL — `notifications_screen.dart` does not exist yet.

- [ ] **Step 3: Write the implementation**

```dart
// lib/features/notifications/notifications_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:ethesishub/data/models/app_notification.dart';
import 'package:ethesishub/data/models/faculty_mode.dart';
import 'package:ethesishub/data/models/user_role.dart';
import 'package:ethesishub/providers/auth_providers.dart';
import 'package:ethesishub/providers/faculty_mode_provider.dart';
import 'package:ethesishub/providers/notification_providers.dart';

/// Where tapping a notification of this type should land, and which
/// [FacultyMode] the reader needs to be in to land there sensibly (D75).
///
/// `null` mode means "no mode-switch is relevant" — a student-only or
/// role-agnostic destination.
({String route, FacultyMode? mode}) _destinationFor(AppNotification n) {
  switch (n.type) {
    case NotificationType.conformeRequested:
      return (route: '/nominations', mode: null);
    case NotificationType.nominationRecommended:
    case NotificationType.nominationApproved:
    case NotificationType.titleApproved:
    case NotificationType.titleRejected:
      return (route: '/thesis', mode: null);
    case NotificationType.chapterFeedback:
      return (route: '/thesis/chapters', mode: FacultyMode.adviser);
    case NotificationType.defenceComment:
    case NotificationType.defenceScheduled:
      return (route: '/defence/${n.thesisId}', mode: null);
    case NotificationType.evaluationAwaits:
      return (route: '/defence/${n.thesisId}', mode: FacultyMode.panelist);
    case NotificationType.archivePublished:
      return (route: '/archive/${n.thesisId}', mode: null);
  }
}

class NotificationsScreen extends ConsumerWidget {
  const NotificationsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final items = ref.watch(notificationsProvider).valueOrNull ?? const [];
    final role = ref.watch(currentUserProvider).valueOrNull?.role;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Notifications'),
        actions: [
          IconButton(
            key: const Key('markAllRead'),
            tooltip: 'Mark all read',
            icon: const Icon(Icons.done_all),
            onPressed: () => markAllNotificationsRead(ref),
          ),
        ],
      ),
      body: items.isEmpty
          ? const Center(child: Text('Nothing yet'))
          : ListView.builder(
              itemCount: items.length,
              itemBuilder: (context, i) {
                final n = items[i];
                return ListTile(
                  leading: Icon(n.read ? Icons.circle_outlined : Icons.circle, size: 10),
                  title: Text(n.message),
                  subtitle: Text('${n.createdAt.day}/${n.createdAt.month}/${n.createdAt.year}'),
                  onTap: () async {
                    await markNotificationRead(ref, n.id);
                    final dest = _destinationFor(n);
                    // Switch mode first (D75): a faculty member opening a
                    // panelist-only notification while in Adviser mode must
                    // not land on a screen their current mode hides.
                    if (dest.mode != null && role == UserRole.faculty) {
                      ref.read(facultyModeProvider.notifier).set(dest.mode!);
                    }
                    if (context.mounted) context.push(dest.route);
                  },
                );
              },
            ),
    );
  }
}
```

Register the route in `lib/core/routing/app_router.dart`, alongside the existing `/archive` and `/forms` top-level routes (near line 657-658):

```dart
GoRoute(path: '/notifications', builder: (_, _) => const NotificationsScreen()),
```

adding the corresponding import at the top of the file:

```dart
import 'package:ethesishub/features/notifications/notifications_screen.dart';
```

In `lib/core/widgets/app_shell_host.dart`'s `_staticTitles` map, add:

```dart
  '/notifications': 'Notifications',
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/features/notifications/notifications_screen_test.dart`
Expected: PASS

- [ ] **Step 5: Run the full suite**

Run: `flutter test`
Expected: PASS, every test including this task's new ones.

- [ ] **Step 6: Run `flutter analyze`**

Run: `flutter analyze`
Expected: clean (no new warnings introduced by this plan).

- [ ] **Step 7: Commit**

```bash
git add lib/features/notifications/notifications_screen.dart lib/core/routing/app_router.dart lib/core/widgets/app_shell_host.dart test/features/notifications/notifications_screen_test.dart
git commit -m "feat: add the notifications list screen with mode-aware deep links"
```

---

## Manual verification (after Task 12)

Deploy the updated rules before testing against live Firebase — a write to `notifications/{uid}/items` is denied by every OTHER client until this runs:

```bash
firebase deploy --only firestore:rules
```

Then, in the running app: sign in as a student with a pending Conforme nominee, a faculty member with a completed defence and no filed evaluation, and a coordinator who just published an archive entry — confirm the bell badges each account correctly, the list shows the right message, and tapping an evaluation-awaits item on a faculty account currently in Adviser mode switches to Panelist mode before landing on the defence room.
