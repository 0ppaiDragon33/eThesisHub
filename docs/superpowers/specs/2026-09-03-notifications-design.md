# Notifications

Objective 5 is the repository and notifications. The archive half (M5a)
shipped and merged. This is the other half: the original design's §6.5
already settled the mechanism (no Cloud Functions on Spark, so
notifications are in-app and real-time) and §9.3 already pre-agreed a
reduction under schedule pressure — in-app badges only, no local tray
popups. Both are inherited rather than re-decided here.

## 0. Scope

Five trigger categories, chosen because each is either named directly in
a prior milestone's spec as deferred to M5, or is the nomination lifecycle
itself:

1. Nomination/title lifecycle (Conforme requested; coordinator
   recommends; dean approves or rejects)
2. Chapter feedback (M2 spec: "notifications on new feedback (M5)")
3. Defence comments and scheduling changes (M3)
4. Evaluation awaits / evaluation submitted (M4 spec names this exactly:
   "Notifying panelists that a defence awaits evaluation")
5. Archive published (M5a)

Tray notifications (`flutter_local_notifications`) are not attempted and
then cut — this design goes straight to the reduced scope §9.3 already
named, so there is nothing to remove later.

## 1. What this delivers

- **`AppNotification`** — a data model for one notification item.
- **Per-source detectors** — one provider per trigger category, each
  reusing an existing live stream (largely the same sources
  `needs_you_providers.dart` already subscribes to) rather than opening
  new Firestore reads.
- **A bell badge** in the app shell's top bar, and a **notifications
  list screen** it opens onto.
- **`firestore.rules`** additions: one new collection, owner-only.

## 2. Decisions taken

Numbering continues from the M6 spec, which ended at D68.

**D69 — Notifications are a distinct event feed, not a replacement for
needs-you.** The app-shell chain already shipped `needs_you_providers.dart`
— a live, unpersisted view of what still requires the reader's action,
with no history and no read state. Notifications answer a different
question: *what happened*, not *what is still on you*. Some events will
appear in both (a new comment might sit on a needs-you tile and also post
a notification) — that duplication is accepted, not solved, because the
two views answer genuinely different questions and collapsing them into
one would make each read for the other's purpose worse.

**D70 — Self-authored: a recipient's own client detects and writes their
own notifications.** The original design has the *acting* user's client
write into the *recipient's* inbox at the moment of the action. That
needs new cross-user write rules validated against each thesis's roles —
exactly the class of check this project has gotten wrong before (four
prior access bugs, per the M5a spec's own accounting). Instead, each
client watches the same source streams it already has standing read
access to — comments, evaluations, chapter feedback, nominations, archive
entries — diffs against its own "last seen" cursor, and writes only into
its own subcollection. No client ever writes a document another user
reads with different authorization from what it already holds.

**D71 — Deterministic per-event item ids.** `notifications/{uid}/items/{itemId}`
where `itemId` is derived from the source document's own id and the
notification type (e.g. `comment_c1_new`), not a random id. A user
signed in on two devices, or a client that re-runs detection after a
reconnect, writes the same id twice — an idempotent no-op, not a
duplicate row.

**D72 — `createdAt` copies the source event's timestamp, not the
detection time.** A client that was offline when a comment was posted and
only reconnects later must still see that notification sort into the
place in the feed where the comment actually happened, not jump to the
top as if it just occurred.

**D73 — Detection failures are logged, not surfaced.** Needs-you treats a
failed source as blocking, because a queue that silently drops an action
item is worse than one that shows an error (M5a's own reasoning, applied
there to a different provider). Notifications are not that: the
underlying event is always still visible at its actual source — the
chapter, the defence log, the thesis status screen — so a notification is
a pointer to that source, not the source of truth. A missed notification
degrades convenience; it does not hide anything the reader has no other
way to see.

**D74 — In-app only, decided once, not built-then-cut.** Matches §9.3's
own pre-agreed reduction. No `flutter_local_notifications` dependency is
added at all.

**D75 — Deep links are mode-aware.** Carried over from the original
design's §8: opening a notification about a defence where the reader is
currently in the other faculty mode switches `facultyModeProvider` first,
then navigates — never lands on a screen that doesn't apply to the
current mode.

**D76 — No pruning or expiry.** Spark has no Cloud Functions, so no
server-side TTL is possible, and at this project's scale (one college,
bounded theses and defences per account) unbounded per-user growth is not
a real problem. Documented as an accepted limitation rather than solved.

## 3. Structure

```
lib/
  data/models/
    app_notification.dart        NotificationType, AppNotification
  providers/
    notification_providers.dart  one detector per trigger category,
                                  the unread-count provider, the list
                                  provider, mark-read / mark-all-read
  features/notifications/
    notification_bell.dart       badge widget for app_shell_host.dart
    notifications_screen.dart    the list screen
```

Each detector follows the same live-fan-in shape already proven in
`myDefencesProvider` and `facultyNeedsYouProvider`: one `.listen()`
subscription per source, `ref.onDispose` cleanup, diffed against a
per-user cursor read from the same `notifications/{uid}/items` collection
it writes to (the cursor is simply "the newest item already written," not
a second stored value).

## 4. Access

**One new rule, owner-only:**

```
match /notifications/{uid}/items/{itemId} {
  allow read, write: if request.auth.uid == uid;
}
```

No `get()` lookups into `theses`, `defences`, or any other collection are
needed — because every write is self-authored from data the writer
already has standing read access to, there is no cross-user fact for a
rule to verify.

## 5. Screens

**The bell** lives in `app_shell_host.dart`'s top bar, next to the theme
toggle. Badged with a live unread count (`read == false`); zero unread
renders no badge at all, not a "0" — the same "0 is indistinguishable
from loading/absent" discipline §4/§9 already established elsewhere in
this project, applied here to mean *no badge* rather than a badge reading
zero.

**The list screen** shows items newest-first: message, relative
timestamp, an unread dot. Tapping an item marks it read and navigates to
the relevant thesis/defence/chapter — mode-switching first per D75 when
needed. An app-bar action marks every item read at once.

## 6. Error handling

Per D73, a detector whose source stream errors logs and stops
contributing new items; it does not surface an error state to the badge
or list screen, and does not block the other detectors from continuing.
The list screen itself still needs a genuine error state for the case
where reading the user's own `notifications/{uid}/items` collection
fails — that read has nothing else backing it up.

## 7. Documentation debt

None new. §6.5's "background push to a closed app is not woken" limitation
was already recorded against Scope and Limitations at the original
design's writing; this milestone does not change that boundary.

## 8. Out of scope

- **Tray/system notifications** — §9.3's reduction, spent directly (D74).
- **Background push to a closed app** — needs Cloud Functions/FCM,
  excluded by D8 since the walking-skeleton design.
- **Per-type notification preferences or muting** — no prior spec asked
  for it, and five trigger categories is not yet enough to need it.
- **Pruning or expiry of old notifications** — accepted limitation (D76).
