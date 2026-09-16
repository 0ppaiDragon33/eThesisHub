import 'package:flutter/material.dart';

import 'package:ethesishub/core/theme/app_tokens.dart';

/// The app's mark: a mortarboard inside a rounded square.
///
/// Drawn in code rather than shipped as an image (D81) so it stays sharp at
/// every size it appears — 56px on the entry brand pane, 40px on the card,
/// 26px in the app bar — and so it can take the dark-mode seal without a
/// second asset.
///
/// Seal blue, not the purple of the reference image: every primary button,
/// link and active destination in this app keys off `seal`, and a mark in a
/// colour used nowhere else reads as borrowed rather than designed.
class BrandEmblem extends StatelessWidget {
  const BrandEmblem({
    super.key,
    this.size = 44,
    this.foreground,
    this.background,
  });

  final double size;
  final Color? foreground;
  final Color? background;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: background ?? (dark ? AppTokens.sealDark : AppTokens.seal),
        borderRadius: BorderRadius.circular(size * 0.28),
      ),
      child: Icon(
        Icons.school,
        size: size * 0.52,
        color: foreground ?? Colors.white,
      ),
    );
  }
}
