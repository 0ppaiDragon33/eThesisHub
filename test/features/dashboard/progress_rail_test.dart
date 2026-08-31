import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ethesishub/core/theme/app_theme.dart';
import 'package:ethesishub/core/theme/app_tokens.dart';
import 'package:ethesishub/core/widgets/stat_tile.dart';
import 'package:ethesishub/data/models/chapter.dart';
import 'package:ethesishub/data/models/defence.dart';
import 'package:ethesishub/data/models/thesis_status.dart';
import 'package:ethesishub/features/dashboard/progress_rail.dart';

Defence defence({
  DefenceType type = DefenceType.preOral,
  DefenceStatus status = DefenceStatus.scheduled,
}) =>
    Defence(
      id: 'd1',
      thesisId: 't1',
      type: type,
      venue: 'AVR',
      panelUids: const ['p1'],
      adviserUid: 'a1',
      leaderUid: 'l1',
      status: status,
      createdBy: 'c1',
      scheduledAt: DateTime(2026, 9, 1, 9),
    );

ThesisChapter chapter({
  ChapterId id = ChapterId.chapterI,
  ChapterStatus status = ChapterStatus.submitted,
}) =>
    ThesisChapter(id: id, currentVersion: 1, status: status);

void main() {
  group('stage derivation', () {
    // The rail used to take `hasDefence: defences.isNotEmpty`, so a FINAL
    // defence rendered as "Pre-oral" and RailStage.finalDefence was
    // unreachable dead code.
    test('a final defence reaches the final stage', () {
      expect(
        ProgressRail.stageFor(
          status: ThesisStatus.titleApproved,
          defences: [defence(type: DefenceType.final_)],
          chapters: [chapter(status: ChapterStatus.approved)],
        ),
        RailStage.finalDefence,
      );
    });

    test('a pre-oral defence reaches the pre-oral stage, not the final one',
        () {
      expect(
        ProgressRail.stageFor(
          status: ThesisStatus.titleApproved,
          defences: [defence(type: DefenceType.preOral)],
          chapters: [chapter()],
        ),
        RailStage.preOral,
      );
    });

    // A cancelled defence is a record struck out. It used to push the rail
    // to "Pre-oral" all the same, so a group whose pre-oral was called off
    // saw the same rail as one that had actually sat it.
    test('a cancelled defence does not advance the rail', () {
      expect(
        ProgressRail.stageFor(
          status: ThesisStatus.titleApproved,
          defences: [defence(status: DefenceStatus.cancelled)],
          chapters: [chapter()],
        ),
        RailStage.chapters,
      );
    });

    test('a cancelled final defence does not reach the final stage', () {
      expect(
        ProgressRail.stageFor(
          status: ThesisStatus.titleApproved,
          defences: [
            defence(type: DefenceType.final_, status: DefenceStatus.cancelled),
          ],
          chapters: [chapter()],
        ),
        RailStage.chapters,
      );
    });

    // A completed defence is the opposite of a cancelled one: proof the
    // stage was actually reached, so it must NOT send the rail backwards.
    test('a completed final defence keeps the final stage', () {
      expect(
        ProgressRail.stageFor(
          status: ThesisStatus.titleApproved,
          defences: [
            defence(type: DefenceType.final_, status: DefenceStatus.completed),
          ],
          chapters: [chapter(status: ChapterStatus.approved)],
        ),
        RailStage.finalDefence,
      );
    });

    test('chapters in progress show Chapters', () {
      expect(
        ProgressRail.stageFor(
          status: ThesisStatus.titleApproved,
          defences: const [],
          chapters: [
            chapter(status: ChapterStatus.approved),
            chapter(id: ChapterId.chapterII, status: ChapterStatus.submitted),
            chapter(id: ChapterId.chapterIII, status: ChapterStatus.revise),
          ],
        ),
        RailStage.chapters,
      );
    });

    test('a status before titleApproved ignores defence and chapter state',
        () {
      expect(
        ProgressRail.stageFor(
          status: ThesisStatus.titlePendingDefence,
          defences: [defence(type: DefenceType.final_)],
          chapters: [chapter()],
        ),
        RailStage.title,
      );
    });

    test('archived renders with all stages complete, not final as current', () {
      // An archived thesis should paint every stage as done, with nothing
      // marked as "here" (the current stage). The widget uses
      // `currentIndex = RailStage.values.indexOf(current)`, so if stageFor()
      // returns finalDefence for archived, the final stage paints as "here"
      // instead of "done". That is wrong: a finished thesis shows all stages
      // done, not the last one as "still happening". This test enforces that
      // special-case handling in build() treats archived as beyond the stages.
      expect(
        ProgressRail.stageFor(
          status: ThesisStatus.archived,
          defences: const [],
          chapters: const [],
        ),
        RailStage.finalDefence,
      );
    });
  });

  group('dark mode', () {
    // The tiles and the rail were the only surfaces in the app that ignored
    // brightness, while every pre-existing consumer (status_chip.dart,
    // defences_list.dart, needs_you_queue.dart) switched on it. The app
    // ships themeMode: ThemeMode.system, so a phone in dark mode drew a
    // near-white #DDE2E8 hairline around every stat tile on a dark card.
    testWidgets('the rail uses the dark tokens under AppTheme.dark',
        (tester) async {
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.dark,
        home: const Scaffold(
          body: ProgressRail(status: ThesisStatus.nominationApproved),
        ),
      ));
      await tester.pump();

      // Title is current, Draft and Nomination are behind it, Chapters ahead.
      final here = tester.widget<Container>(
        find.byKey(const Key('railCurrent-title')),
      );
      expect(
        (here.decoration! as BoxDecoration).color,
        AppTokens.sealDark,
        reason: 'the current step must use the dark seal',
      );

      final colours = tester
          .widgetList<Container>(find.descendant(
            of: find.byType(ProgressRail),
            matching: find.byType(Container),
          ))
          .map((c) => (c.decoration as BoxDecoration?)?.color)
          .whereType<Color>()
          .toSet();
      expect(colours, contains(AppTokens.endorsedDark));
      expect(colours, contains(AppTokens.ruleDark));
      expect(colours, isNot(contains(AppTokens.seal)));
      expect(colours, isNot(contains(AppTokens.endorsed)));
      expect(colours, isNot(contains(AppTokens.rule)));

      final label = tester.widget<Text>(find.text('Title'));
      expect(label.style!.color, AppTokens.sealDark);
    });

    testWidgets('a stat tile uses the dark rule and dark accent',
        (tester) async {
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.dark,
        home: Scaffold(
          body: Builder(
            builder: (context) => StatTile(
              label: 'Active theses',
              value: '12',
              icon: Icons.school_outlined,
              // What every overview now passes: the POSITION is a
              // compile-time constant, brightness only picks the variant.
              accent: AppTokens.accentFor(0, Theme.of(context).brightness),
              progress: 0.4,
            ),
          ),
        ),
      ));
      await tester.pump();

      final decorations = tester
          .widgetList<Container>(find.descendant(
            of: find.byType(StatTile),
            matching: find.byType(Container),
          ))
          .map((c) => c.decoration)
          .whereType<BoxDecoration>()
          .toList();

      final card = decorations.firstWhere((d) => d.border != null);
      expect(
        (card.border! as Border).top.color,
        AppTokens.ruleDark,
        reason: 'the card hairline must not be the light near-white rule',
      );

      final badge = decorations.firstWhere((d) => d.border == null);
      expect(badge.color, AppTokens.accentPlumDark);

      final bar = tester.widget<LinearProgressIndicator>(
        find.byType(LinearProgressIndicator),
      );
      expect(bar.backgroundColor, AppTokens.ruleDark);
    });
  });

  group('rendering', () {
    testWidgets('an archived thesis renders all stages as complete',
        (tester) async {
      // An archived thesis is terminal: it should show every stage complete,
      // with nothing marked "here". This is the critical assertion that the
      // widget test catches what the stage derivation alone does not: that
      // the build() method paints archived correctly.
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.light,
        home: const Scaffold(
          body: ProgressRail(status: ThesisStatus.archived),
        ),
      ));
      await tester.pump();

      // No stage should be marked as the current one ("here"). If one is,
      // it would have a Key like 'railCurrent-<stage-id>', which we should
      // not find.
      expect(
        find.byKey(const Key('railCurrent-draft')),
        findsNothing,
        reason: 'draft should not be marked as current',
      );
      expect(
        find.byKey(const Key('railCurrent-final')),
        findsNothing,
        reason: 'final should not be marked as current (even though it is the stage)',
      );

      // All stage dots should be the "done" colour (endorsed).
      final colours = tester
          .widgetList<Container>(find.descendant(
            of: find.byType(ProgressRail),
            matching: find.byType(Container),
          ))
          .map((c) => (c.decoration as BoxDecoration?)?.color)
          .whereType<Color>()
          .toSet();
      expect(
        colours,
        isNot(contains(AppTokens.seal)),
        reason: 'no stage should be painted "here" (seal colour)',
      );
      expect(
        colours,
        contains(AppTokens.endorsed),
        reason: 'all stages should be painted done (endorsed colour)',
      );
    });
  });
}
