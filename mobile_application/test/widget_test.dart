import 'package:flutter_test/flutter_test.dart';
import 'package:solace_mobile/main.dart';

void main() {
  testWidgets('bootstrap app renders', (tester) async {
    await tester.pumpWidget(const MainApp());

    expect(find.text('Hello World!'), findsOneWidget);
  });
}
