import 'package:flutter/material.dart';

import 'package:ethesishub/core/theme/app_tokens.dart';
import 'package:ethesishub/data/models/defence.dart';

/// The one place a [DefenceStatus] becomes words.
///
/// Shared by [DefencesList] and the calendar view so "cancelled" cannot end
/// up with two labels that drift apart.
String defenceStatusLabel(DefenceStatus status) => switch (status) {
      DefenceStatus.scheduled => 'Scheduled',
      DefenceStatus.inProgress => 'In progress',
      DefenceStatus.completed => 'Completed',
      DefenceStatus.cancelled => 'Cancelled',
    };

/// The one place a [DefenceStatus] becomes a colour.
///
/// Shared by [DefencesList] and the calendar view -- both a status chip and
/// a calendar dot must agree on what colour "cancelled" is.
Color defenceStatusColor(DefenceStatus status, Brightness brightness) {
  final light = brightness == Brightness.light;
  return switch (status) {
    DefenceStatus.scheduled =>
      light ? AppTokens.awaiting : AppTokens.awaitingDark,
    DefenceStatus.inProgress =>
      light ? AppTokens.endorsed : AppTokens.endorsedDark,
    DefenceStatus.completed =>
      light ? AppTokens.inkMuted : AppTokens.inkMutedDark,
    // Same muted ink as completed: neither is waiting on anyone. Kept
    // visible rather than hidden so a coordinator can see what became of
    // the one they called off.
    DefenceStatus.cancelled =>
      light ? AppTokens.inkMuted : AppTokens.inkMutedDark,
  };
}
