import 'package:flutter_test/flutter_test.dart';

import 'package:yes_claude/main.dart';

void main() {
  testWidgets('App renders without error', (WidgetTester tester) async {
    await tester.pumpWidget(const YesClaudeApp());
    // Just verify it renders — Firebase will fail without config
    // but the widget tree should be constructable
  });
}
