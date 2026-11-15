import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ethesishub/data/models/app_notification.dart';
import 'package:ethesishub/data/models/chapter.dart';
import 'package:ethesishub/data/models/defence.dart';
import 'package:ethesishub/data/models/evaluation.dart';
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

/// Zero when there is nothing unread OR the feed has not resolved yet,
/// the badge renders no chip at all for zero (D: see , "no badge
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
  final unreadIds = <String>[
    for (final i in items)
      if (!i.read) i.id,
  ];
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
/// idempotent per source key: this is not a "first emission only"
/// cursor, and does not need to be one.
///
/// Failures are logged, not surfaced: a missed notification is a
/// degraded convenience, not a hidden fact: the source event is still
/// visible wherever it actually lives, but a silent swallow with zero
/// trace makes a rules misconfiguration or malformed document
/// undiagnosable, so the error still reaches debug output.
///
/// ONE ACCOUNT only. [uid] is the account the calling detector was built
/// for (each detector watches [signedInUidProvider], so it is torn down and
/// rebuilt (with every listener it opened) whenever the account changes).
/// Two guards keep one account's events out of another account's feed,
/// which happened when someone signed out and into a different account in
/// the same app session:
/// - Only a SETTLED value is acted on. A provider rebuilding after an
///   account change passes through loading and error states that still
///   carry the PREVIOUS account's value (`valueOrNull` returns it), and
///   writing that under the new uid is exactly the leak.
/// - Only while [uid] is still the signed-in account, in case an emission
///   lands between the account changing and this detector being rebuilt.
void _detect<T>(
  Ref ref,
  String uid,
  ProviderListenable<AsyncValue<T>> source,
  Future<void> Function(T value, NotificationRepository repo, String uid)
  onValue,
) {
  ref.listen<AsyncValue<T>>(source, (previous, next) {
    if (next is! AsyncData<T> || next.isLoading) return;
    if (ref.read(signedInUidProvider) != uid) return;
    final value = next.value;
    if (value == null) return;
    onValue(value, ref.read(notificationRepositoryProvider), uid).catchError((
      e,
    ) {
      debugPrint('notification detector failed: $e');
    });
  }, fireImmediately: true);
}

/// Conforme requests, coordinator recommendation, dean nomination approval,
/// and the title defence title-round verdict: every thesis-status-driven event a
/// nominee or a group leader needs to know about.
final nominationLifecycleDetectorProvider = Provider<void>((ref) {
  // Built per account: see _detect. Nothing is detected while signed out.
  final uid = ref.watch(signedInUidProvider);
  if (uid == null) return;
  _detect<List<({String thesisId, Nomination nomination})>>(
    ref,
    uid,
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

  _detect<Thesis?>(ref, uid, myThesisProvider, (thesis, repo, uid) async {
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

    // Keyed by when it was returned, so a second return is a new item.
    final returnedAt = thesis.nominationReturnedAt;
    if (returnedAt != null && (thesis.nominationReturnReason ?? '').isNotEmpty) {
      final who = thesis.nominationReturnedRole == 'dean'
          ? 'The Dean'
          : 'The Research Coordinator';
      await repo.upsertIfAbsent(
        uid,
        AppNotification(
          id: notificationId(NotificationType.nominationReturned,
              '${thesis.id}_${returnedAt.millisecondsSinceEpoch}'),
          type: NotificationType.nominationReturned,
          thesisId: thesis.id,
          message: '$who returned your nomination: '
              '${thesis.nominationReturnReason}',
          read: false,
          createdAt: returnedAt,
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
      final type = approved
          ? NotificationType.titleApproved
          : NotificationType.titleRejected;
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

/// New feedback on any of the reader's own manuscripts (and, for a thesis
/// from before manuscripts, its chapters), from anyone but
/// themselves.
///
/// A nested fan-in (the chapter source is only known once [myThesisProvider]
/// resolves), the same shape `facultyNeedsYouProvider`'s own doc comment in
/// `needs_you_providers.dart` describes for its chapter source: the five
/// per-chapter feedback subscriptions are opened once the thesis id is
/// known, not fixed at provider-build time.
final chapterFeedbackDetectorProvider = Provider<void>((ref) {
  // Built per account: see _detect. Nothing is detected while signed out.
  final uid = ref.watch(signedInUidProvider);
  if (uid == null) return;
  final registeredThesisIds = <String>{};

  _detect<Thesis?>(ref, uid, myThesisProvider, (thesis, repo, uid) async {
    if (thesis == null) return;
    if (!registeredThesisIds.add(thesis.id)) return;

    // A standing subscription per document, not a one-shot read: opened
    // once the thesis id is known and kept alive for the life of that
    // thesis, so new feedback arriving mid-session notifies without
    // waiting for `myThesisProvider` to re-emit for an unrelated reason.
    // `registeredThesisIds` guards against re-registering every
    // document's listeners on a later `myThesisProvider` re-emission for
    // the same thesis.
    for (final chapter in ChapterId.values) {
      _detect<List<ChapterFeedback>>(
        ref,
        uid,
        chapterFeedbackProvider((thesisId: thesis.id, chapter: chapter)),
        (entries, repo, uid) async {
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
        },
      );
    }
  });
});

/// The scheduling line, worded for the reader's own relationship to the
/// defence, because a detector runs on each recipient's own client, so it
/// already knows whether `uid` is the student group leader, the adviser, or
/// a panelist. "Your defence" is right for the group but reads as if a
/// faculty member were a student, which is the whole point of not sending
/// every party the same student-voiced sentence.
String _scheduledMessage(Defence defence, String uid, {UserRole? role}) {
  final at = defence.scheduledAt!;
  final when = '${defence.venue} on ${at.day}/${at.month}/${at.year}';
  // The Research Coordinator and the Dean grade every defense (2026-10-01),
  // so each is a party to all of them without being on any one panel.
  if (role == UserRole.coordinator || role == UserRole.dean) {
    final office =
        role == UserRole.dean ? 'the Dean' : 'the Research Coordinator';
    return 'A defense is scheduled for $when. You grade it as $office.';
  }
  if (defence.leaderUid == uid) {
    return 'Your defense is scheduled for $when.';
  }
  if (defence.adviserUid == uid) {
    return 'A defense you advise is scheduled for $when.';
  }
  if (defence.panelUids.contains(uid)) {
    return 'A defense you are on the panel for is scheduled for $when.';
  }
  // Not a party by any snapshot: unreachable via myDefencesProvider, but a
  // neutral sentence beats an assumption if the data ever disagrees.
  return 'A defense is scheduled for $when.';
}

/// What happened on every defense the reader is party to: it was scheduled
/// or rescheduled, it was cancelled, the panel's verdict was recorded (for
/// the group leader), and the panel's highlights were released (for the
/// group leader).
///
/// Students, faculty, and the Research Coordinator and the Dean. The last
/// two used to be left out because `myDefencesProvider` returns every
/// defense in the college for them and this is about a defense's own
/// parties. They grade every defense since 2026-10-01, so each is a party
/// to all of them, but because their list is the whole college's, they are
/// told only about defenses still to come, never the ones already past, and
/// never about what they did themselves.
///
/// The role check is read fresh with `ref.read` INSIDE the `_detect`
/// callback, not with `ref.watch` at the top of the provider body. A
/// `ref.watch` there would capture `currentUserProvider`'s value at the
/// moment this provider first builds: almost always still loading, since
/// `currentUserProvider` is itself async, and a plain `Provider` does not
/// eagerly re-run its body just because a watched dependency later
/// resolves; nothing here re-reads it, so `_detect` would never end up
/// registered at all. Reading it inside the callback is safe because
/// `myDefencesProvider` cannot emit before `currentUserProvider` resolves
/// it awaits `currentUserProvider.future` itself before choosing a
/// query, so by the time this callback runs, the role is already known.
final defenceDetectorProvider = Provider<void>((ref) {
  // Built per account: see _detect. Nothing is detected while signed out.
  final uid = ref.watch(signedInUidProvider);
  if (uid == null) return;

  _detect<List<Defence>>(ref, uid, myDefencesProvider, (
    defences,
    repo,
    uid,
  ) async {
    final role = ref.read(currentUserProvider).valueOrNull?.role;
    final isOffice = role == UserRole.coordinator || role == UserRole.dean;
    if (role != UserRole.student && role != UserRole.faculty && !isOffice) {
      return;
    }

    for (final defence in defences) {
      // The Research Coordinator and the Dean grade every defense, so they
      // are told about each one that is coming, but only the coming ones.
      // Their list is the whole college's, history included, and a first
      // launch must not turn every past defense into a bell item. The
      // Coordinator who scheduled it is not told what they just did.
      final officeSkips = isOffice &&
          (defence.status != DefenceStatus.scheduled ||
              defence.createdBy == uid);
      if (defence.scheduledAt != null && !officeSkips) {
        final key =
            '${defence.id}_${defence.scheduledAt!.millisecondsSinceEpoch}_${defence.venue}';
        await repo.upsertIfAbsent(
          uid,
          AppNotification(
            id: notificationId(NotificationType.defenceScheduled, key),
            type: NotificationType.defenceScheduled,
            thesisId: defence.thesisId,
            defenceId: defence.id,
            message: _scheduledMessage(defence, uid, role: role),
            read: false,
            createdAt: defence.scheduledAt!,
          ),
        );
      }

      // A cancellation reaches the defense's own parties: the group, the
      // adviser and the panel: who would otherwise turn up to an empty
      // room. Not the office holders: their list is the whole college's, so
      // every old cancellation would arrive at once, and the Coordinator is
      // the one who cancels.
      if (defence.status == DefenceStatus.cancelled && !isOffice) {
        final at = defence.scheduledAt;
        await repo.upsertIfAbsent(
          uid,
          AppNotification(
            id: notificationId(NotificationType.defenceCancelled, defence.id),
            type: NotificationType.defenceCancelled,
            thesisId: defence.thesisId,
            defenceId: defence.id,
            message: at == null
                ? 'The ${defence.label.toLowerCase()} was cancelled.'
                : 'The ${defence.label.toLowerCase()} on '
                    '${at.day}/${at.month}/${at.year} was cancelled.',
            read: false,
            createdAt: at ?? DateTime.now(),
          ),
        );
      }

      // The group is told its result the moment the adviser records it:
      // it decides what they do next (the full manuscript opens on a pass).
      final verdict = defence.panelVerdict;
      if (defence.leaderUid == uid && verdict != null) {
        await repo.upsertIfAbsent(
          uid,
          AppNotification(
            id: notificationId(NotificationType.verdictRecorded, defence.id),
            type: NotificationType.verdictRecorded,
            thesisId: defence.thesisId,
            defenceId: defence.id,
            message: verdict == PassFail.pass
                ? 'The panel passed your ${defence.label.toLowerCase()}.'
                : 'The panel did not pass your '
                    '${defence.label.toLowerCase()}.',
            read: false,
            createdAt: defence.verdictRecordedAt ?? DateTime.now(),
          ),
        );
      }

      // The panel's highlights reach the group leader alone, once the
      // adviser releases them (`consolidatedAt`). The faculty made or saw
      // them live in the room and need no bell. `myDefencesProvider`
      // re-emits when the defence document changes, so a release arriving
      // mid-session is seen without any extra listener. Keyed by the
      // defence, so it is said once.
      final releasedAt = defence.consolidatedAt;
      if (defence.leaderUid == uid && releasedAt != null) {
        await repo.upsertIfAbsent(
          uid,
          AppNotification(
            id: notificationId(NotificationType.highlightsReleased, defence.id),
            type: NotificationType.highlightsReleased,
            thesisId: defence.thesisId,
            defenceId: defence.id,
            message: "The panel's highlights on your "
                '${defence.label.toLowerCase()} are ready to read.',
            read: false,
            createdAt: releasedAt,
          ),
        );
      }

      // The panel's written remarks reach the group the same way, on the
      // adviser's release of the evaluations (`evaluationsReleasedAt`),
      // the remarks only, never the scores. Keyed by the defence, so it is
      // said once.
      final gradesAt = defence.evaluationsReleasedAt;
      if (defence.leaderUid == uid && gradesAt != null) {
        await repo.upsertIfAbsent(
          uid,
          AppNotification(
            id: notificationId(NotificationType.remarksReleased, defence.id),
            type: NotificationType.remarksReleased,
            thesisId: defence.thesisId,
            defenceId: defence.id,
            message: "The panel's remarks on your "
                '${defence.label.toLowerCase()} are ready to read.',
            read: false,
            createdAt: gradesAt,
          ),
        );
      }
    }
  });
});

/// A completed defence where the reader sits on the panel but has not yet
/// filed their Form 5c. Only "awaits" is covered (not "submitted"),
/// brainstorming found no concrete recipient for a submission event that
/// is not already covered by one of the other four categories, and adding
/// one with no real use case would be exactly the kind of speculative
/// scope the spec's Out of Scope section already rules out.
///
/// The role check is read fresh with `ref.read` INSIDE the `_detect`
/// callback: see [defenceDetectorProvider]'s doc comment for why a
/// `ref.watch` at the top of the provider body would never actually run
/// this detector, and why reading it here (after `myDefencesProvider` has
/// already awaited `currentUserProvider.future` internally) is safe.
final evaluationAwaitsDetectorProvider = Provider<void>((ref) {
  // Built per account: see _detect. Nothing is detected while signed out.
  final uid = ref.watch(signedInUidProvider);
  if (uid == null) return;
  _detect<List<Defence>>(ref, uid, myDefencesProvider, (
    defences,
    repo,
    uid,
  ) async {
    final role = ref.read(currentUserProvider).valueOrNull?.role;
    // The Research Coordinator and the Dean grade every defense too, so each
    // has a Form 5c owed on all of them, and the adviser cannot release
    // the grades until it is in.
    final isOffice = role == UserRole.coordinator || role == UserRole.dean;
    if (role != UserRole.faculty && !isOffice) return;

    for (final defence in defences) {
      if (defence.status != DefenceStatus.completed) continue;
      if (isOffice) {
        // Only sheets still open: their list is the whole college's, and a
        // released defense is long settled.
        if (defence.evaluationsReleased) continue;
      } else if (!defence.panelUids.contains(uid)) {
        continue;
      }

      final mine = await ref.read(myEvaluationProvider(defence.id).future);
      if (mine != null) continue;

      await repo.upsertIfAbsent(
        uid,
        AppNotification(
          id: notificationId(NotificationType.evaluationAwaits, defence.id),
          type: NotificationType.evaluationAwaits,
          thesisId: defence.thesisId,
          defenceId: defence.id,
          message: 'A defense has completed and is waiting on your Form 5c.',
          read: false,
          createdAt: defence.createdAt ?? DateTime.now(),
        ),
      );
    }
  });
});

/// Tells the adviser when every grader (the panel, the Coordinator and the
/// Dean) has submitted their Form 5c on a closed defence they advise, so they
/// can release the grades. Watches the defence itself, which each grader
/// records their submission on, so the last sheet coming in is what fires
/// it. Once per defence.
final evaluationsCompleteDetectorProvider = Provider<void>((ref) {
  final uid = ref.watch(signedInUidProvider);
  if (uid == null) return;
  final defences = ref.watch(myDefencesProvider).valueOrNull ?? const <Defence>[];
  final repo = ref.read(notificationRepositoryProvider);
  for (final d in defences) {
    if (d.adviserUid != uid) continue;
    if (d.status != DefenceStatus.completed || d.evaluationsReleased) continue;
    // The defence's own record of who has submitted, the same list the
    // rules lock the release on. Who, not just how many: a notice saying
    // "release the grades" while a panelist has not graded would invite
    // the adviser to open a button that is still locked.
    if (!d.canReleaseEvaluations) continue;
    repo
        .upsertIfAbsent(
          uid,
          AppNotification(
            id: notificationId(NotificationType.evaluationsComplete, d.id),
            type: NotificationType.evaluationsComplete,
            thesisId: d.thesisId,
            defenceId: d.id,
            message: 'Every grader has submitted their Form 5c. You can '
                'release the grades.',
            read: false,
            createdAt: DateTime.now(),
          ),
        )
        .catchError((Object e) {
      debugPrint('notification detector failed: $e');
    });
  }
});

/// The reader's own thesis appearing in the archive.
///
/// Scoped to the group leader only (via [myThesisProvider]) for this first
/// pass: notifying the adviser and panel too would mean resolving "which
/// theses is this faculty member attached to" from [myAdviseesProvider]
/// and [myDefencesProvider] and cross-referencing both against
/// [archiveProvider], which is a second, more expensive fan-in for an
/// event advisers and panelists already see reflected on their own
/// dashboards the moment it happens. The group leader has no such standing
/// view, which is why they are the one this detector covers.
final archivePublishedDetectorProvider = Provider<void>((ref) {
  // Built per account: see _detect. Nothing is detected while signed out.
  final uid = ref.watch(signedInUidProvider);
  if (uid == null) return;
  _detect<Thesis?>(ref, uid, myThesisProvider, (thesis, repo, uid) async {
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
/// something watches this: see `AppShellHost.build`, the one place that
/// does, for the whole life of a signed-in session.
final notificationDetectorsProvider = Provider<void>((ref) {
  ref.watch(nominationLifecycleDetectorProvider);
  ref.watch(chapterFeedbackDetectorProvider);
  ref.watch(defenceDetectorProvider);
  ref.watch(evaluationAwaitsDetectorProvider);
  ref.watch(evaluationsCompleteDetectorProvider);
  ref.watch(archivePublishedDetectorProvider);
});
