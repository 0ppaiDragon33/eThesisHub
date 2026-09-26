import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ethesishub/data/models/defence.dart';
import 'package:ethesishub/data/models/thesis.dart';
import 'package:ethesishub/providers/defence_providers.dart';
import 'package:ethesishub/providers/title_providers.dart';

/// The four stages the Defences page switches between (spec 2026-09-25
/// §6.1), in the order a thesis meets them.
enum DefenceStage {
  title('title', 'Title defence', 'Title', Icons.forum_outlined),
  preOral('preOral', 'Pre-oral', 'Pre-oral', Icons.record_voice_over_outlined),
  finalDefence('final', 'Final defence', 'Final', Icons.school_outlined),
  redefence('redefence', 'Re-defence', 'Re-defence', Icons.replay_outlined);

  const DefenceStage(this.param, this.label, this.shortLabel, this.icon);

  /// The `?stage=` value. Stored in links, so it never changes.
  final String param;
  final String label;

  /// The label on a phone, where four full labels do not fit.
  final String shortLabel;
  final IconData icon;

  /// A missing or unknown value is the first stage, never an error: a stale
  /// or hand-typed link still lands somewhere useful.
  static DefenceStage fromParam(String? raw) {
    for (final s in values) {
      if (s.param == raw) return s;
    }
    return title;
  }

  String get route => '/defences?stage=$param';

  /// Whether [d] belongs on this stage. The title defence is not a
  /// `defenses` document, so it holds none.
  bool includes(Defence d) => switch (this) {
    title => false,
    preOral => d.type == DefenceType.preOral && !d.isRedefence,
    finalDefence => d.type == DefenceType.final_ && !d.isRedefence,
    redefence => d.isRedefence,
  };

  String labelFor(int count, {required bool compact}) {
    final base = compact ? shortLabel : label;
    return count > 0 ? '$base ($count)' : base;
  }
}

/// What still needs attention on each stage, for the switch's labels:
/// - Title: every title defence the reader can open.
/// - Pre-oral and Final: defences scheduled or in progress.
/// - Re-defence: open re-defences plus failed defences awaiting one.
///
/// A total of every defence ever held would only grow.
final defenceStageCountsProvider = Provider<Map<DefenceStage, int>>((ref) {
  final defences =
      ref.watch(myDefencesProvider).valueOrNull ?? const <Defence>[];
  final titles =
      ref.watch(myTitleDefencesProvider).valueOrNull ?? const <Thesis>[];

  bool open(Defence d) =>
      d.status == DefenceStatus.scheduled ||
      d.status == DefenceStatus.inProgress;
  int openOn(DefenceStage s) =>
      defences.where((d) => s.includes(d) && open(d)).length;

  return {
    DefenceStage.title: titles.length,
    DefenceStage.preOral: openOn(DefenceStage.preOral),
    DefenceStage.finalDefence: openOn(DefenceStage.finalDefence),
    DefenceStage.redefence:
        openOn(DefenceStage.redefence) + awaitingRedefence(defences).length,
  };
});

/// The first stage, in the order a thesis meets them, with something open;
/// Title when none has (spec 2026-09-25 §6.1, as amended).
DefenceStage firstStageWithSomethingOpen(Map<DefenceStage, int> counts) {
  for (final s in DefenceStage.values) {
    if ((counts[s] ?? 0) > 0) return s;
  }
  return DefenceStage.title;
}

/// The stage a bare '/defences' (the sidebar) opens on: wherever the reader
/// has something open, rather than always Title — a group past its title
/// defence would otherwise land on an empty tab every time.
///
/// Loading until both lists behind the counts have arrived, so the choice is
/// made on real numbers and the page does not jump from Title to another
/// stage a moment later. A list that failed to load counts as empty, so the
/// page still opens; that stage shows its own error.
final defaultDefenceStageProvider = Provider<AsyncValue<DefenceStage>>((ref) {
  bool settled(AsyncValue<Object?> a) => a.hasValue || a.hasError;
  if (!settled(ref.watch(myDefencesProvider)) ||
      !settled(ref.watch(myTitleDefencesProvider))) {
    return const AsyncLoading();
  }
  return AsyncData(
      firstStageWithSomethingOpen(ref.watch(defenceStageCountsProvider)));
});
