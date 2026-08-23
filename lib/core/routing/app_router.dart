import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:ethesishub/core/widgets/page_shell.dart';
import 'package:ethesishub/core/widgets/states.dart';
import 'package:ethesishub/data/models/chapter.dart';
import 'package:ethesishub/data/models/thesis_status.dart';
import 'package:ethesishub/data/models/user_role.dart';
import 'package:ethesishub/features/admin/faculty_invites_screen.dart';
import 'package:ethesishub/features/auth/login_screen.dart';
import 'package:ethesishub/features/auth/register_screen.dart';
import 'package:ethesishub/features/auth/verify_email_screen.dart';
import 'package:ethesishub/features/dashboard/coordinator_dashboard.dart';
import 'package:ethesishub/features/dashboard/dean_dashboard.dart';
import 'package:ethesishub/features/dashboard/faculty_dashboard.dart';
import 'package:ethesishub/features/dashboard/student_dashboard.dart';
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
String homeRouteFor(UserRole role) => switch (role) {
      UserRole.student => '/student',
      UserRole.faculty => '/faculty',
      UserRole.coordinator => '/coordinator',
      UserRole.dean => '/dean',
    };

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
              // it was never created, or was removed). Send them to /login,
              // which shows a "signed in as X — sign out" affordance so
              // they aren't stuck with no error and no escape.
              if (profile == null) {
                return onAuthScreen ? null : '/login';
              }

              final home = homeRouteFor(profile.role);
              if (onAuthScreen || location == '/verify-email') return home;

              // Prevent reaching another role's dashboard by typing its URL.
              final userDashboards =
                  UserRole.values.map(homeRouteFor).toList();
              if (userDashboards.contains(location) && location != home) {
                return home;
              }

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
              // The title defence panel is faculty, coordinators and the
              // dean — never the student whose titles are being judged.
              if (location.startsWith('/defence/') &&
                  profile.role == UserRole.student) {
                return home;
              }

              // '/thesis/nominate' and '/thesis/titles' both read their
              // thesis id from a required query parameter. A bare visit
              // (typed directly, or reached with no thesis context) falls
              // back to the signed-in leader's own thesis rather than
              // crashing on the route builder's null-check; a leader with no
              // thesis yet is sent to create one first.
              const bareVisitFallbackPaths = [
                '/thesis/nominate',
                '/thesis/titles',
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
            error: (_, _) => null,
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
      GoRoute(path: '/student', builder: (_, _) => const StudentDashboard()),
      GoRoute(path: '/faculty', builder: (_, _) => const FacultyDashboard()),
      GoRoute(
        path: '/coordinator',
        builder: (_, _) => const CoordinatorDashboard(),
      ),
      GoRoute(path: '/dean', builder: (_, _) => const DeanDashboard()),
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
            return const Scaffold(
              key: Key('nominateBareVisitLoading'),
              body: Center(child: CircularProgressIndicator()),
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
            return const Scaffold(
              key: Key('submitTitlesBareVisitLoading'),
              body: Center(child: CircularProgressIndicator()),
            );
          }
          return SubmitTitlesScreen(thesisId: id);
        },
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
            return Scaffold(
              appBar: AppBar(title: const Text('Chapters')),
              body: const PageShell(children: [
                EmptyState(
                  icon: Icons.link_off,
                  title: 'No thesis given',
                  message: 'Open your chapters from your thesis status page.',
                ),
              ]),
            );
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
            return Scaffold(
              appBar: AppBar(title: const Text('Chapter')),
              body: const PageShell(children: [
                EmptyState(
                  icon: Icons.search_off,
                  title: 'No such chapter',
                  message: 'There are five chapters, I through V.',
                ),
              ]),
            );
          }
          return ChapterDetailScreen(thesisId: id, chapter: chapter);
        },
      ),
    ],
  );
});
