import 'package:flutter_test/flutter_test.dart';
import 'package:ethesishub/app.dart';

void main() {
  testWidgets('app builds and shows its title', (tester) async {
    await tester.pumpWidget(const EThesisHubApp());
    expect(find.text('eThesisHub'), findsOneWidget);
  });
}