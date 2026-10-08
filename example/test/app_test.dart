import 'package:flutter_test/flutter_test.dart';
import 'package:gaiadesk_embed_example/main.dart';

void main() {
  testWidgets('Acme Bank renders its card, Buy and Get help', (tester) async {
    await tester.pumpWidget(const AcmeBankApp());
    expect(find.text('4111 1111 1111 1111'), findsOneWidget);
    expect(find.text('Buy'), findsOneWidget);
    expect(find.text('Get help'), findsOneWidget);
    await tester.tap(find.text('Get help'));
    await tester.pump();
    expect(find.textContaining('Paste an embed token'), findsOneWidget);
  });
}
