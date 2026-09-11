import 'package:flutter_test/flutter_test.dart';

import 'package:niim_blue_flutter_example/main.dart';

void main() {
  testWidgets('renders the printer controls', (WidgetTester tester) async {
    await tester.pumpWidget(const MyApp());

    expect(find.text('NiimBlueLibRN'), findsOneWidget);
    expect(find.text('Status: Disconnected'), findsOneWidget);
    expect(find.textContaining('Connect to Printer'), findsOneWidget);
  });
}
