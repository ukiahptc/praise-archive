import 'package:flutter_test/flutter_test.dart';

import 'package:praise_archive/main.dart';

void main() {
  testWidgets('App launches and shows title', (WidgetTester tester) async {
    await tester.pumpWidget(const PraiseArchiveApp());
    await tester.pump();

    expect(find.text('찬양 보관함'), findsWidgets);
  });
}
