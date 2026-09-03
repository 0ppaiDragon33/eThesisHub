import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ethesishub/data/models/app_notification.dart';
import 'package:ethesishub/data/models/archive_entry.dart';
import 'package:ethesishub/data/models/chapter.dart';
import 'package:ethesishub/data/models/defence.dart';
import 'package:ethesishub/data/models/nomination.dart';
import 'package:ethesishub/data/models/thesis.dart';
import 'package:ethesishub/data/models/thesis_status.dart';
import 'package:ethesishub/data/models/user_role.dart';
import 'package:ethesishub/data/repositories/notification_repository.dart';
import 'package:ethesishub/providers/archive_providers.dart';
import 'package:ethesishub/providers/auth_providers.dart';
import 'package:ethesishub/providers/defence_providers.dart';
import 'package:ethesishub/providers/document_providers.dart';
import 'package:ethesishub/providers/thesis_providers.dart';

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

/// Marks a single notification as read. Accepts both `Ref` (from `WidgetRef` in UI)
/// and `ProviderContainer` (from tests), though Dart's type system requires `dynamic`
/// due to ProviderContainer not explicitly implementing the `Ref` interface despite
/// having compatible methods.
Future<void> markNotificationRead(dynamic ref, String itemId) async {
  final uid = ref.read(signedInUidProvider);
  if (uid == null) return;
  await ref.read(notificationRepositoryProvider).markRead(uid, itemId);
}

/// Marks all notifications as read. See [markNotificationRead] for type annotation note.
Future<void> markAllNotificationsRead(dynamic ref) async {
  final uid = ref.read(signedInUidProvider);
  if (uid == null) return;
  final items = await ref.read(notificationsProvider.future);
  final unreadIds = <String>[for (final i in items) if (!i.read) i.id];
  if (unreadIds.isEmpty) return;
  await ref.read(notificationRepositoryProvider).markAllRead(uid, unreadIds);
}

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

/// New comments and schedule changes on every defence the reader is party
/// to.
///
/// Restricted to student and faculty readers. `myDefencesProvider` returns
/// EVERY defence in the college for a coordinator or dean (their own
/// `allow list` arm has no per-thesis restriction), and this detector is
/// about a defence's own parties knowing what happened on their defence,
/// not a college-wide comment firehose for the two roles who already have
/// a dedicated overview of every defence's status.
///
/// The role check is read fresh with `ref.read` INSIDE the `_detect`
/// callback, not with `ref.watch` at the top of the provider body. A
/// `ref.watch` there would capture `currentUserProvider`'s value at the
/// moment this provider first builds -- almost always still loading, since
/// `currentUserProvider` is itself async -- and a plain `Provider` does not
/// eagerly re-run its body just because a watched dependency later
/// resolves; nothing here re-reads it, so `_detect` would never end up
/// registered at all. Reading it inside the callback is safe because
/// `myDefencesProvider` cannot emit before `currentUserProvider` resolves
/// -- it awaits `currentUserProvider.future` itself before choosing a
/// query -- so by the time this callback runs, the role is already known.
final defenceDetectorProvider = Provider<void>((ref) {
  _detect<List<Defence>>(ref, myDefencesProvider, (defences, repo, uid) async {
    final role = ref.read(currentUserProvider).valueOrNull?.role;
    if (role != UserRole.student && role != UserRole.faculty) return;

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

/// A completed defence where the reader sits on the panel but has not yet
/// filed their Form 5c. Only "awaits" is covered (not "submitted") --
/// brainstorming found no concrete recipient for a submission event that
/// is not already covered by one of the other four categories, and adding
/// one with no real use case would be exactly the kind of speculative
/// scope the spec's Out of Scope section already rules out.
///
/// The role check is read fresh with `ref.read` INSIDE the `_detect`
/// callback -- see [defenceDetectorProvider]'s doc comment for why a
/// `ref.watch` at the top of the provider body would never actually run
/// this detector, and why reading it here (after `myDefencesProvider` has
/// already awaited `currentUserProvider.future` internally) is safe.
final evaluationAwaitsDetectorProvider = Provider<void>((ref) {
  _detect<List<Defence>>(ref, myDefencesProvider, (defences, repo, uid) async {
    final role = ref.read(currentUserProvider).valueOrNull?.role;
    if (role != UserRole.faculty) return;

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
