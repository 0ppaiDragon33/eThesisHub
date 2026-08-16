/// Test-only workaround for a `fake_cloud_firestore` 4.2.0 defect.
///
/// `_DummyTransaction.update()`/`.set()` (in
/// `fake_cloud_firestore_instance.dart`) call the real
/// `MockDocumentReference.update()`/`.set()` **without awaiting the returned
/// Future** (this mirrors real `Transaction.update()`, which also returns
/// synchronously — real Firestore stages writes and commits them as a batch
/// when the handler returns; the fake does not defer/batch, it just fires
/// the write and drops the Future). `MockDocumentReference.update()`'s first
/// line is `await _firestore.maybeThrowSecurityException(...)`, itself an
/// `await Future.value()` — so under the fake, the actual mutation to its
/// backing map lands *one microtask turn after* `FirebaseFirestore
/// .runTransaction()` can already have resolved. Confirmed empirically:
/// immediately after `await db.runTransaction(...)`, a plain
/// `collection.doc(id).snapshots().first` / repository `watchThesis(id)
/// .first` (which subscribes via `snapshots().startWith(_getSync())`, i.e.
/// reads synchronously at subscription time) could observe the **pre-write**
/// value, while an awaited `.get()` call right after (which itself yields
/// once) always observed the post-write value.
///
/// This is purely a `fake_cloud_firestore` bug, not a real Firestore
/// behaviour — real `cloud_firestore`'s `runTransaction()` never resolves
/// before the commit is confirmed, so this helper would be a no-op against
/// it. That is exactly why it lives in `test/`, not in `lib/`: production
/// code must not carry an accommodation for a test double's quirk.
///
/// Call this immediately after awaiting a repository method that runs a
/// `runTransaction` block (e.g. `ThesisRepository.respondToNomination`,
/// `ThesisRepository.approve`) whenever the test's next step reads the
/// result via a stream's synchronous-at-subscription-time `.first` (e.g.
/// `watchThesis(id).first`) rather than via an awaited `.get()`.
Future<void> settleFakeTransaction() => Future<void>.value();
