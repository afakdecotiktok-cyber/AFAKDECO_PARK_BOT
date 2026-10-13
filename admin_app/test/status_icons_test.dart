import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:afakdeco_admin/widgets/status_icons.dart';

void main() {
  testWidgets('status icons render accident and pending states', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: StatusIcons(icons: ['accident', 'pending']),
        ),
      ),
    );

    expect(find.byIcon(Icons.warning_rounded), findsOneWidget);
    expect(find.byIcon(Icons.hourglass_top_rounded), findsOneWidget);
  });
}
