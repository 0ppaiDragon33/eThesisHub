import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ethesishub/core/config/app_config.dart';
import 'package:ethesishub/core/theme/app_theme.dart';
import 'package:ethesishub/core/widgets/institutional_domain_notice.dart';
import 'package:ethesishub/core/widgets/responsive_scaffold.dart';
import 'package:ethesishub/core/widgets/states.dart';
import 'package:ethesishub/core/widgets/status_chip.dart';
import 'package:ethesishub/data/models/thesis_status.dart';

Widget wrap(Widget child, {Brightness brightness = Brightness.light}) =>
    MaterialApp(
      theme: brightness == Brightness.light ? AppTheme.light : AppTheme.dark,
      home: Scaffold(body: child),
    );

void main() {
  group('StatusChip', () {
    test('every status has a label and a next-step sentence', () {
      // A status added later without wording here would surface as a raw
      // enum name on the student's screen, so the switch must stay
      // exhaustive. Dart enforces that at compile time for the switches
      // themselves; this asserts the output is actually usable text.
      for (final s in ThesisStatus.values) {
        expect(StatusChip.labelFor(s), isNotEmpty, reason: '$s has no label');
        expect(StatusChip.detailFor(s), isNotEmpty, reason: '$s has no detail');
        expect(StatusChip.labelFor(s), isNot(contains('nomination')),
            reason: '$s leaks the enum name into the interface');
      }
    });

    test('labels name the desk the paper is on, not the state machine', () {
      // The vocabulary students and faculty actually use. If these ever
      // become "Pending coordinator review" the interface has drifted back
      // to describing itself rather than the office.
      expect(StatusChip.labelFor(ThesisStatus.nominationPendingCoordinator),
          'With the Coordinator');
      expect(StatusChip.labelFor(ThesisStatus.nominationPendingDean),
          'With the Dean');
    });

    testWidgets('renders its label in both themes', (tester) async {
      for (final brightness in Brightness.values) {
        await tester.pumpWidget(wrap(
          const StatusChip(ThesisStatus.nominationApproved),
          brightness: brightness,
        ));
        await tester.pumpAndSettle();
        expect(find.text('Approved'), findsOneWidget);
      }
    });

    testWidgets('an approved thesis and a waiting one are not the same colour',
        (tester) async {
      // The whole point of the chip is telling them apart down a list of
      // thirty. Same colour would make it decoration.
      await tester.pumpWidget(wrap(const Column(children: [
        StatusChip(ThesisStatus.nominationApproved),
        StatusChip(ThesisStatus.nominationPendingDean),
      ])));
      await tester.pumpAndSettle();

      final texts = tester.widgetList<Text>(find.byType(Text)).toList();
      expect(texts, hasLength(2));
      expect(texts[0].style?.color, isNot(texts[1].style?.color));
    });
  });

  group('ResponsiveScaffold', () {
    testWidgets('hides its navigation below two destinations', (tester) async {
      // A tab that goes nowhere reads as a broken app rather than an
      // unfinished one. Dashboards declare only destinations that resolve,
      // so the bar must disappear rather than show a single lonely tab.
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.light,
        home: const ResponsiveScaffold(
          title: 'eThesisHub',
          destinations: [],
          selectedIndex: 0,
          onDestinationSelected: _ignore,
          body: Text('body'),
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.byType(NavigationBar), findsNothing);
      expect(find.byType(NavigationRail), findsNothing);
      expect(find.text('body'), findsOneWidget);
    });

    testWidgets('shows navigation at two destinations', (tester) async {
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.light,
        home: const ResponsiveScaffold(
          title: 'eThesisHub',
          destinations: [
            NavDestination(label: 'Theses', icon: Icons.folder_outlined),
            NavDestination(label: 'Faculty', icon: Icons.badge_outlined),
          ],
          selectedIndex: 0,
          onDestinationSelected: _ignore,
          body: Text('body'),
        ),
      ));
      await tester.pumpAndSettle();

      // Narrow by default in tests, so the bottom bar is the one that shows.
      expect(find.byType(NavigationBar), findsOneWidget);
    });
  });

  group('states', () {
    testWidgets('an empty state always offers a way forward', (tester) async {
      await tester.pumpWidget(wrap(EmptyState(
        title: 'No thesis group yet',
        message: 'Create your group to get started.',
        action: FilledButton(onPressed: () {}, child: const Text('Create')),
      )));
      await tester.pumpAndSettle();

      expect(find.text('No thesis group yet'), findsOneWidget);
      expect(find.text('Create'), findsOneWidget);
    });

    testWidgets('an error state says what happened and offers a retry',
        (tester) async {
      var retried = false;
      await tester.pumpWidget(wrap(ErrorState(
        message: 'Could not load the review queue.',
        onRetry: () => retried = true,
      )));
      await tester.pumpAndSettle();

      expect(find.text('Could not load the review queue.'), findsOneWidget);
      await tester.tap(find.text('Try again'));
      expect(retried, isTrue);
    });
  });

  group('InstitutionalDomainNotice', () {
    testWidgets('shows exactly when the domain restriction is relaxed',
        (tester) async {
      // The notice exists so a relaxation cannot be forgotten. Tying the
      // assertion to the flag is deliberate here — the claim being made is
      // that the two always agree, in whichever state the flag is left.
      await tester.pumpWidget(wrap(const InstitutionalDomainNotice()));
      await tester.pumpAndSettle();

      final finder = find.byKey(const Key('domainEnforcementOff'));
      if (AppConfig.enforceInstitutionalDomain) {
        expect(finder, findsNothing,
            reason: 'enforcement is on, so nothing should be announced');
      } else {
        expect(finder, findsOneWidget,
            reason: 'enforcement is off and must say so on screen');
        expect(find.textContaining('any email address'), findsOneWidget);
      }
    });
  });

  group('AppTheme', () {
    test('both themes define the full surface set rather than inheriting', () {
      // A half-defined dark theme is how a screen ends up with light text on
      // a light background: the seed generates something for every slot, so
      // the failure is silent.
      for (final theme in [AppTheme.light, AppTheme.dark]) {
        expect(theme.scaffoldBackgroundColor, theme.colorScheme.surface);
        expect(theme.appBarTheme.backgroundColor, isNotNull);
        expect(theme.textTheme.headlineSmall?.fontWeight, FontWeight.w700);
      }
    });

    test('light and dark do not share ink or paper', () {
      expect(AppTheme.light.colorScheme.onSurface,
          isNot(AppTheme.dark.colorScheme.onSurface));
      expect(AppTheme.light.scaffoldBackgroundColor,
          isNot(AppTheme.dark.scaffoldBackgroundColor));
    });
  });
}

void _ignore(int _) {}
