import 'package:flutter/material.dart';

/// A date, then a time, for a defence. Null if either picker is dismissed or
/// the screen goes away mid-pick. Shared by the defence and re-defence
/// scheduling screens.
Future<DateTime?> pickDefenceDateTime(
  BuildContext context,
  DateTime initial,
) async {
  final date = await showDatePicker(
    context: context,
    initialDate: initial,
    firstDate: DateTime(DateTime.now().year - 1),
    lastDate: DateTime(DateTime.now().year + 2),
  );
  if (date == null || !context.mounted) return null;
  final time = await showTimePicker(
    context: context,
    initialTime: TimeOfDay.fromDateTime(initial),
  );
  if (time == null || !context.mounted) return null;
  return DateTime(date.year, date.month, date.day, time.hour, time.minute);
}
