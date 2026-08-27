import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:ethesishub/core/widgets/app_shell_host.dart';
import 'package:ethesishub/core/widgets/page_shell.dart';
import 'package:ethesishub/core/widgets/states.dart';
import 'package:ethesishub/data/models/chapter.dart';
import 'package:ethesishub/data/models/thesis_status.dart';
import 'package:ethesishub/data/models/user_role.dart';
import 'package:ethesishub/features/admin/faculty_invites_screen.dart';
import 'package:ethesishub/features/auth/login_screen.dart';
import 'package:ethesishub/features/auth/no_profile_screen.dart';
import 'package:ethesishub/features/auth/register_screen.dart';
import 'package:ethesishub/features/auth/verify_email_screen.dart';
import 'package:ethesishub/features/dashboard/advisees_screen.dart';
import 'package:ethesishub/features/dashboard/approvals_screen.dart';
import 'package:ethesishub/features/dashboard/overview_screen.dart';
import 'package:ethesishub/features/dashboard/panels_screen.dart';
import 'package:ethesishub/features/dashboard/readiness_screen.dart';
import 'package:ethesishub/features/dashboard/recommendations_screen.dart';
import 'package:ethesishub/features/dashboard/title_defences_screen.dart';
import 'package:ethesishub/features/defence/consolidated_defence_screen.dart';
import 'package:ethesishub/features/defence/defence_room_screen.dart';
import 'package:ethesishub/features/defence/defences_screen.dart';
import 'package:ethesishub/features/defence/schedule_defence_screen.dart';
import 'package:ethesishub/features/documents/chapter_detail_screen.dart';
import 'package:ethesishub/features/documents/chapters_screen.dart';
import 'package:ethesishub/features/nomination/nomination_inbox_screen.dart';
import 'package:ethesishub/features/nomination/review_queue_screen.dart';
import 'package:ethesishub/features/thesis/create_thesis_screen.dart';
import 'package:ethesishub/features/thesis/nominate_screen.dart';
import 'package:ethesishub/features/thesis/thesis_status_screen.dart';
import 'package:ethesishub/features/titles/submit_titles_screen.dart';
import 'package:ethesishub/features/titles/title_defence_screen.dart';
import 'package:ethesishub/providers/auth_providers.dart';
import 'package:ethesishub/providers/thesis_providers.dart';

/// Simple ChangeNotifier that allows external code to trigger notifications.
class _RouterRefreshNotifier extends ChangeNotifier {
  void notify() => notifyListeners();
}

/// Home route for each account role.
///
/// One route for all four now. Each role used to land on a dashboard of
/// its own — '/student', '/faculty', '/coordinator', '/dean' — which is
/// also why navigation existed on exactly those four screens and nowhere
/// else. `/overview` renders the same per-role overview inside the one
/// shell that now wraps every signed-in route, so leaving it no longer
/// strands anybody.
///
/// The four old paths are not deleted; they redirect here (see
/// [oldHomeRoutes]), because they have been bookmarkable URLs for two
/// milestones.
String homeRouteFor(UserRole role) => '/overview';

/// The four pre-shell dashboard paths, kept alive as redirects.
///
/// A bookmark, a browser history entry or a link pasted into a chat is not
/// a thing this app gets to invalidate quietly: a 404 or a blank page is
/// indistinguishable from the app being broken.
const oldHomeRoutes = ['/student', '/faculty', '/coordinator', '/dean'];

final goRouterProvider = Provider<GoRouter>((ref) {
  // Build the router once. Use a ChangeNotifier with ref.listen to re-evaluate
  // redirects when auth state changes, avoiding router reconstruction which would
  // drop navigation state. The redirect callback uses ref.read to get current values.
  final refreshNotifier = _RouterRefreshNotifier();

  ref.listen(authStateProvider, (_, _) {
    refreshNotifier.notify();
  });

  ref.listen(currentUserProvider, (_, _) {
    refreshNotifier.notify();
  });

  // Needed so the `/thesis/nominate` bare-visit fallback (below) gets a
  // second chance to redirect once the leader's thesis has actually loaded
  // — the first redirect evaluation can land before this stream's first
  // event arrives, same class of race documented on authStateProvider.
  ref.listen(myThesisProvider, (_, _) {
    refreshNotifier.notify();
  });

  ref.onDispose(refreshNotifier.dispose);

  return GoRouter(
    initialLocation: '/login',
    refreshListenable: refreshNotifier,
    redirect: (context, state) {
      final authStateAsync = ref.read(authStateProvider);
      final location = state.matchedLocation;
      final onAuthScreen = location == '/login' || location == '/register';

      // Distinguish loading from signed-out. While loading, stay put rather than
      // routing to login. Only a settled null means the user is signed out.
      return authStateAsync.when(
        data: (authState) {
          if (authState == null) {
            return onAuthScreen ? null : '/login';
          }
          if (!authState.emailVerified) {
            return location == '/verify-email' ? null : '/verify-email';
          }

          final profileAsync = ref.read(currentUserProvider);
          return profileAsync.when(
            data: (profile) {
              // currentUserProvider is a StreamProvider, and AsyncLoading
              // already covers the "still loading" case (handled below). A
              // settled `data(null)` here means the users/{uid} document
              // does not exist for this signed-in, verified account (e.g.
              // it was never created, or was removed).
              //
              // /no-profile, not /login: this account IS signed in, and
              // sending it to the sign-in screen said the opposite. The
              // screen it lands on now names the two causes apart — the
              // document is absent versus the read failed — and offers
              // Retry and Sign out (spec D25).
              if (profile == null) {
                return location == '/no-profile' ? null : '/no-profile';
              }

              final home = homeRouteFor(profile.role);
              if (onAuthScreen || location == '/verify-email') return home;

              // A profile that has come back (a retry that succeeded, or a
              // coordinator finishing the registration) must not leave the
              // reader parked on the dead end.
              if (location == '/no-profile') return home;

              // The four pre-shell dashboards. They are no longer screens,
              // but they are still URLs people hold, so each lands on the
              // one overview rather than nothing.
              if (oldHomeRoutes.contains(location)) return home;

              // M1a screens are role-scoped. A wrong-role user goes to their
              // own home rather than seeing an empty or forbidden screen.
              // This is a UX guard only — the real authorization boundary is
              // firestore.rules, which every screen's writes and reads still
              // go through regardless of what the client permits.
              //
              // '/thesis/chapters' is deliberately exempt from this list,
              // even though it starts with '/thesis': chapters are reviewed
              // by the adviser, not just uploaded by the student, and
              // faculty_dashboard.dart's own link into
              // '/thesis/chapters?id=...' would otherwise bounce every
              // adviser straight back to their dashboard before
              // ChaptersScreen ever built — the same class of "the link
              // exists but the route refuses the very role that needs it"
              // failure this whole task exists to close.
              //
              // (faculty_dashboard.dart itself is gone as of the app-shell
              // switchover; that link lives in advisees_screen.dart now and
              // points at the same path, so the exemption is load-bearing
              // exactly as before.)
              //
              // Exempt exactly the chapter routes, not everything sharing
              // the prefix: a future '/thesis/chaptersArchive' must not
              // inherit this exemption by accident. Chapters are the one
              // branch under /thesis that faculty need, because an adviser
              // reviews them. No query-string clause here: `location` above
              // is `state.matchedLocation`, which is the matched path only
              // — go_router strips the query string before this callback
              // ever sees it — so a clause checking for '/thesis/chapters?'
              // could never fire.
              final isChapterRoute = location == '/thesis/chapters' ||
                  location.startsWith('/thesis/chapters/');
              const studentOnly = [
                '/thesis',
                '/thesis/create',
                '/thesis/nominate',
                '/thesis/titles',
              ];
              if (studentOnly.any(location.startsWith) &&
                  !isChapterRoute &&
                  profile.role != UserRole.student) {
                return home;
              }
              // Open to faculty, coordinators and deans — a coordinator or
              // dean nominated as a panel member on someone else's thesis
              // still needs their own inbox.
              if (location.startsWith('/nominations') &&
                  profile.role == UserRole.student) {
                return home;
              }
              if (location.startsWith('/review') &&
                  profile.role != UserRole.coordinator &&
                  profile.role != UserRole.dean) {
                return home;
              }
              // The eight sidebar-destination routes (Task 6/7) each admit a
              // subset of roles per the M1a spec's permission table. All
              // eight are static single-segment paths -- see the comment
              // above their GoRoute registrations -- so none of them needs
              // an exemption the way '/thesis/chapters' and
              // '/defence/room/' do below: nothing dynamic ever shares
              // their prefix.
              //
              // '/overview' and '/defences' admit every signed-in role and
              // so need no guard here at all.
              //
              // '/advisees' and '/panels' admit faculty, coordinators AND
              // deans -- not just faculty -- for the same reason
              // '/nominations' above is open to all three: a coordinator or
              // dean nominated onto someone else's thesis genuinely holds
              // an adviser or panel position and needs their own list of
              // advisees or panels, same as a plain faculty member would.
              if ((location == '/advisees' || location == '/panels') &&
                  profile.role == UserRole.student) {
                return home;
              }
              // '/approvals' is the dean's queue alone.
              if (location == '/approvals' && profile.role != UserRole.dean) {
                return home;
              }
              // '/recommendations' is the coordinator's alone.
              if (location == '/recommendations' &&
                  profile.role != UserRole.coordinator) {
                return home;
              }
              // '/title-defences' and '/readiness' are coordinator and dean
              // destinations -- never faculty (who sit on individual title
              // defence panels via '/defence/:thesisId' instead, unguarded
              // by role here) and never the student whose own titles or
              // readiness are what these screens track.
              if ((location == '/title-defences' ||
                      location == '/readiness') &&
                  profile.role != UserRole.coordinator &&
                  profile.role != UserRole.dean) {
                return home;
              }
              // The title defence panel is faculty, coordinators and the
              // dean — never the student whose titles are being judged.
              //
              // '/defence/room/...' is deliberately exempt, even though it
              // starts with '/defence/': DefencesList is shared by all four
              // dashboards (see its own doc comment), including the
              // student's -- those four dashboards are now the one
              // '/defences' destination every role reaches through the app
              // shell, which changes nothing about who follows this link --
              // and its "Open" button sends the leader straight
              // into '/defence/room/${d.id}' to watch the log and, once the
              // adviser releases it, read the consolidated comments at
              // '/defence/room/${d.id}/consolidated' — ConsolidatedDefenceScreen
              // has its own isLeader-gated branch for exactly that reader.
              // A blanket prefix match here would bounce that same student
              // straight back home before either screen ever built — the
              // same class of "the link exists but the route refuses the
              // very role that needs it" failure the '/thesis/chapters'
              // exemption above already closed once for advisers.
              final isDefenceRoomRoute = location.startsWith('/defence/room/');
              if (location.startsWith('/defence/') &&
                  !isDefenceRoomRoute &&
                  profile.role == UserRole.student) {
                return home;
              }

              // '/thesis/nominate' and '/thesis/titles' both read their
              // thesis id from a required query parameter. A bare visit
              // (typed directly, or reached with no thesis context) falls
              // back to the signed-in leader's own thesis rather than
              // crashing on the route builder's null-check; a leader with no
              // thesis yet is sent to create one first.
              final bareVisitFallbackPaths = [
                '/thesis/nominate',
                '/thesis/titles',
                // The sidebar's Chapters destination is a bare
                // '/thesis/chapters': a destination is one fixed route and
                // cannot carry a query parameter only the signed-in
                // leader's own thesis can supply. The dashboard tab it
                // replaces passed that id in directly, so without this the
                // Chapters destination would land every student on "No
                // thesis given" -- a control that does nothing, which is
                // exactly what the destination list is curated to avoid.
                //
                // Students only. An adviser reaches chapters through
                // '/thesis/chapters?id=...' from their advisee list and
                // has no Chapters destination of their own, so falling
                // their bare visit back to "the leader's own thesis" would
                // resolve to a thesis they do not lead, or to
                // /thesis/create, neither of which is what they asked for.
                if (profile.role == UserRole.student) '/thesis/chapters',
              ];
              if (bareVisitFallbackPaths.contains(location) &&
                  state.uri.queryParameters['id'] == null) {
                // Distinguish "still loading" from "has no thesis" — reading
                // `.valueOrNull` here would treat an unsettled stream the
                // same as a settled `null`, misrouting a leader who genuinely
                // has a thesis to /thesis/create on first load (this bites
                // on Web, where a page reload re-runs this redirect before
                // myThesisProvider's first snapshot has arrived; in-app
                // navigation never sees it because the provider is already
                // warm by then). While loading, hold here (no redirect) —
                // the route builder below renders a brief loading state for
                // the bare-visit case, and the `ref.listen(myThesisProvider)`
                // above re-triggers this same redirect, at this same
                // location, once the stream settles.
                final myThesisAsync = ref.read(myThesisProvider);
                return myThesisAsync.when(
                  data: (myThesis) => myThesis == null
                      ? '/thesis/create'
                      : '$location?id=${myThesis.id}',
                  loading: () => null,
                  error: (_, _) => '/thesis/create',
                );
              }

              return null;
            },
            loading: () => null, // still loading profile, stay put
            // A FAILED profile read is not the same as a slow one, and it
            // used to be handled as though it were: returning null left
            // the reader wherever they happened to be, with no error and
            // no explanation, on a screen whose every query was about to
            // fail for the same reason. /no-profile shows the Firestore
            // code — the only place the reason surfaces in the field,
            // there being no server-side logs on Spark — plus Retry and
            // Sign out.
            error: (_, _) => location == '/no-profile' ? null : '/no-profile',
          );
        },
        loading: () => null, // still loading auth, stay put
        error: (_, _) => onAuthScreen ? null : '/login',
      );
    },
    routes: [
      GoRoute(path: '/login', builder: (_, _) => const LoginScreen()),
      GoRoute(path: '/register', builder: (_, _) => const RegisterScreen()),
      GoRoute(
        path: '/verify-email',
        builder: (_, _) => const VerifyEmailScreen(),
      ),
      // Everything below sits inside ONE shell. That is the whole point of
      // this milestone: navigation used to exist on exactly four screens
      // (the four dashboards, each carrying its own ResponsiveScaffold),
      // and every one of the sixteen screens you could reach from them was
      // a bare Scaffold. Leaving a dashboard left you with no sidebar, no
      // bottom bar and no way home — reported from the field as "I don't
      // see any back menu while navigating on screens."
      //
      // Login, register and verify-email stay OUTSIDE it, above: they are
      // the screens for someone who is not signed in, and a sidebar full
      // of destinations they cannot reach is worse than none. /no-profile
      // is inside, because that reader IS signed in — the shell renders
      // its app bar and simply offers no destinations, since
      // shellDestinationsProvider yields an empty list for an unknown role
      // rather than guessing one.
      ShellRoute(
        builder: (context, state, child) => AppShellHost(
          // Not `state.matchedLocation`: that field is the location
          // where this ShellRoute itself first matched, and go_router
          // does not recompute it for an imperative `push` onto a
          // sibling route already inside the shell -- it only advances
          // on a fresh `go`. `state.uri` DOES track the pushed leaf (see
          // `ShellRouteMatch.buildState` in go_router's own source,
          // which rebuilds `uri` from the imperative match but reuses
          // the old `matchedLocation` verbatim), so `.path` is the one
          // that is actually current after a deep-screen push. Task 9
          // needs this: without it, the shell keeps computing "deeper
          // than a destination" against the pre-push location and never
          // draws a back control on a pushed screen.
          location: state.uri.path,
          pathParameters: state.pathParameters,
          child: child,
        ),
        routes: [
      GoRoute(
        path: '/no-profile',
        builder: (_, _) => const NoProfileScreen(),
      ),
      // The eight sidebar-destination routes. The four old dashboard paths
      // ('/student', '/faculty', '/coordinator', '/dean') are gone as
      // screens and redirect here instead (see `oldHomeRoutes`). None of
      // these share a segment with any dynamic route below (they are all
      // single static segments), so there is no ordering hazard here the
      // way there is for '/defence/schedule' further down.
      GoRoute(path: '/overview', builder: (_, _) => const OverviewScreen()),
      GoRoute(path: '/defences', builder: (_, _) => const DefencesScreen()),
      GoRoute(path: '/advisees', builder: (_, _) => const AdviseesScreen()),
      GoRoute(path: '/panels', builder: (_, _) => const PanelsScreen()),
      GoRoute(
        path: '/approvals',
        builder: (_, _) => const ApprovalsScreen(),
      ),
      GoRoute(
        path: '/recommendations',
        builder: (_, _) => const RecommendationsScreen(),
      ),
      // NOT '/titles' -- '/thesis/titles' (below) already exists for
      // submitting a candidate title set. Two routes a character apart
      // meaning different things is exactly how '/faculty' came to be
      // registered twice in M1, leaving the invites screen permanently
      // unreachable (see '/invites' further down).
      GoRoute(
        path: '/title-defences',
        builder: (_, _) => const TitleDefencesScreen(),
      ),
      GoRoute(
        path: '/readiness',
        builder: (_, _) => const ReadinessScreen(),
      ),
      GoRoute(
        path: '/thesis/create',
        builder: (_, _) => const CreateThesisScreen(),
      ),
      GoRoute(
        path: '/thesis',
        builder: (_, _) => const ThesisStatusScreen(),
      ),
      GoRoute(
        path: '/thesis/nominate',
        builder: (context, state) {
          final id = state.uri.queryParameters['id'];
          if (id == null) {
            // Bare visit while the redirect above is still waiting on
            // myThesisProvider's first snapshot (see the redirect callback
            // for why it does not commit to a destination yet). Brief and
            // self-resolving: the moment that provider settles, the
            // refreshListenable fires and the redirect sends us to
            // /thesis/create or /thesis/nominate?id=... as appropriate.
            //
            // No Scaffold of its own: the shell above supplies it, and a
            // second one here would stack a second app bar.
            return const Center(
              key: Key('nominateBareVisitLoading'),
              child: CircularProgressIndicator(),
            );
          }
          return NominateScreen(thesisId: id);
        },
      ),
      GoRoute(
        path: '/thesis/titles',
        builder: (context, state) {
          // Same bare-visit fallback as /thesis/nominate: fall back to the
          // leader's own thesis rather than null-checking a missing query
          // parameter, and distinguish loading from absent while doing it.
          final id = state.uri.queryParameters['id'];
          if (id == null) {
            return const Center(
              key: Key('submitTitlesBareVisitLoading'),
              child: CircularProgressIndicator(),
            );
          }
          return SubmitTitlesScreen(thesisId: id);
        },
      ),
      // The three routes below are registered BEFORE '/defence/:thesisId'
      // on purpose. go_router matches a static segment before a dynamic one
      // at the same level, but this project has already lost a screen to a
      // route collision -- '/faculty' registered twice left the invites
      // screen unreachable, caught only because m2_routes_test.dart drove
      // the router rather than pumping the screen directly (see '/invites'
      // below). '/defence/schedule' is the one genuine collision risk here:
      // it has the same segment count as '/defence/:thesisId', so
      // 'schedule' would be swallowed as a thesisId if this route were
      // ever moved below it. m3_routes_test.dart's falsification test
      // proves this ordering is load-bearing, not merely conventional.
      GoRoute(
        path: '/defence/schedule',
        builder: (context, state) {
          final id = state.uri.queryParameters['id'];
          // No force-unwrap: a bare visit (typed directly, or a stale link)
          // must not crash into a blank screen with no way back -- same
          // failure mode '/thesis/chapters' avoids for a missing thesis id.
          if (id == null || id.isEmpty) {
            // The shell supplies the app bar (titled 'Schedule a defence',
            // see shellTitleFor) and the sidebar, so this refusal is
            // already somewhere the reader can leave from.
            return const PageShell(children: [
              EmptyState(
                icon: Icons.link_off,
                title: 'No thesis given',
                message: 'Open scheduling from a thesis you coordinate.',
              ),
            ]);
          }
          return ScheduleDefenceScreen(thesisId: id);
        },
      ),
      // '/defence/room/:defenceId' is registered before
      // '/defence/room/:defenceId/consolidated' only because that is
      // source order here, not because order matters between them: a
      // static 'consolidated' segment at position 3 can never be swallowed
      // by ':defenceId' at position 2 -- the segment counts differ, so
      // go_router never even considers the shorter route for the longer
      // path. DefenceRoomScreen and ConsolidatedDefenceScreen each render
      // their own "not found" state through the same `_framed` helper as
      // their loaded state -- a KeyedSubtree around a PageShell, carrying
      // the screen's own key, with no Scaffold and no AppBar of its own
      // since the shell above supplies both. So no wrapper is needed here
      // the way one is for the missing-id case above: an unknown defenceId
      // lands on a page that still has the app bar, the sidebar and the
      // back control, and never strands the reader.
      GoRoute(
        path: '/defence/room/:defenceId',
        builder: (context, state) => DefenceRoomScreen(
            defenceId: state.pathParameters['defenceId']!),
      ),
      GoRoute(
        path: '/defence/room/:defenceId/consolidated',
        builder: (context, state) => ConsolidatedDefenceScreen(
            defenceId: state.pathParameters['defenceId']!),
      ),
      GoRoute(
        path: '/defence/:thesisId',
        builder: (context, state) => TitleDefenceScreen(
            thesisId: state.pathParameters['thesisId']!),
      ),
      GoRoute(
        path: '/nominations',
        builder: (_, _) => const NominationInboxScreen(),
      ),
      GoRoute(
        path: '/review',
        builder: (context, state) {
          final profile = ref.read(currentUserProvider).value;
          final isDean = profile?.role == UserRole.dean;
          return ReviewQueueScreen(
            queue: isDean
                ? ThesisStatus.nominationPendingDean
                : ThesisStatus.nominationPendingCoordinator,
            isDean: isDean,
          );
        },
      ),
      // Coordinator-only in practice, but the guard here is UX, not
      // security: the rules deny `list` on facultyInvites and refuse the
      // write to anyone who is not a coordinator, so a student who typed
      // this path would reach a screen that can load nothing and save
      // nothing.
      // NOT '/faculty' — that path is already the faculty dashboard (above),
      // and go_router takes the first match, so registering it twice left
      // this screen unreachable: the coordinator's "Invite faculty" button
      // landed on the faculty dashboard instead.
      GoRoute(
        path: '/invites',
        builder: (_, _) => const FacultyInvitesScreen(),
      ),
      // '/thesis/chapters' (the list) is registered before
      // '/thesis/chapters/:chapterId' (one chapter's detail) only because
      // that is source order here, not because order matters between them:
      // go_router matches a static segment against a static path and a
      // dynamic ':chapterId' segment against everything else, so the two
      // can never shadow one another the way '/faculty' and '/invites'
      // once did. Tests m2_routes_test.dart 1 and 2 exercise both paths to
      // prove that in practice, not just by reading the matcher's rules.
      GoRoute(
        path: '/thesis/chapters',
        builder: (context, state) {
          final id = state.uri.queryParameters['id'];
          // No force-unwrap: a bare visit (typed directly, or a stale link
          // after a thesis id changes) must not crash into a blank screen
          // with no way back -- the same failure mode the chapter-detail
          // route below avoids for an unknown chapter id.
          if (id == null || id.isEmpty) {
            return const PageShell(children: [
              EmptyState(
                icon: Icons.link_off,
                title: 'No thesis given',
                message: 'Open your chapters from your thesis status page.',
              ),
            ]);
          }
          return ChaptersScreen(thesisId: id);
        },
      ),
      GoRoute(
        path: '/thesis/chapters/:chapterId',
        builder: (context, state) {
          final id = state.uri.queryParameters['id'];
          final chapter =
              ChapterId.fromString(state.pathParameters['chapterId']);
          // ChapterId.fromString returns null by design for an id that is
          // not one of the five chapters (see chapter.dart) rather than
          // defaulting to chapterI, so a route that force-unwrapped it here
          // would throw during build and hand the user a white error
          // screen with no AppBar and no way back. Both this and the
          // missing-id case share one refusal, framed the same as the list
          // route's, rather than `appBar: null`, which is exactly the
          // "stranded with no way back" bug this project already shipped
          // once (see the redirect callback's own history above).
          if (id == null || id.isEmpty || chapter == null) {
            return const PageShell(children: [
              EmptyState(
                icon: Icons.search_off,
                title: 'No such chapter',
                message: 'There are five chapters, I through V.',
              ),
            ]);
          }
          return ChapterDetailScreen(thesisId: id, chapter: chapter);
        },
      ),
        ],
      ),
    ],
  );
});
