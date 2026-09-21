import 'package:flutter_test/flutter_test.dart';
import 'package:solace_mobile/main.dart';

void main() {
  testWidgets('bootstrap app renders', (tester) async {
    await tester.pumpWidget(const MainApp());

    expect(find.text('Good to see you'), findsOneWidget);
    expect(find.text('Today'), findsOneWidget);
    expect(find.text('Journal'), findsOneWidget);
    expect(find.text('Insights'), findsOneWidget);
    expect(find.text('You'), findsOneWidget);
  });
}
