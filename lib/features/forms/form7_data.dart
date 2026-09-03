import 'package:ethesishub/data/models/thesis.dart';

/// Everything Form 7 knows how to fill in — the two identifying lines
/// ahead of its review table.
///
/// The table itself (Dean, Research Coordinator, Thesis Adviser, two
/// Members, a Grammarian and a Statistician, each with a name, an
/// "Approved" mark and remarks) is never filled from data, in a filled
/// letter or a blank one. Two of those seven roles — Grammarian and
/// Statistician — are not modelled anywhere in this app at all, and the
/// other five would need a per-row resolution this form's own printed
/// layout does not map cleanly onto `Thesis.panelistUids`. Rather than
/// fill five of seven rows and leave two conspicuously blank, every row
/// stays blank — which is also the more honest rendering of a document
/// whose whole purpose is to be signed by hand.
class Form7Data {
  const Form7Data({required this.presenterNames, required this.title});

  final List<String> presenterNames;
  final String title;

  factory Form7Data.assemble({required Thesis thesis, required String title}) {
    return Form7Data(presenterNames: thesis.memberNames, title: title);
  }
}
