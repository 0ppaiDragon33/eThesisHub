import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ethesishub/core/widgets/sign_out_button.dart';
import 'package:ethesishub/features/auth/deactivated_screen.dart';
import 'package:ethesishub/providers/auth_providers.dart';

void main() {
  testWidgets('renders at a phone width and at a desktop width',
      (tester) async {
    for (final size in [const Size(400, 900), const Size(1200, 900)]) {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            firebaseAuthProvider.overrideWithValue(MockFirebaseAuth()),
          ],
          child: const MaterialApp(home: DeactivatedScreen()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Account deactivated'), findsWidgets);
      expect(find.byType(SignOutButton), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
  });
}
