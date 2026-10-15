import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:afakdeco_admin/l10n/strings.dart';
import 'package:afakdeco_admin/services/api.dart';
import 'package:afakdeco_admin/theme/app_theme.dart';
import 'package:afakdeco_admin/widgets/app_widgets.dart';

void main() {
  test('friendlyError maps common server failures to Arabic', () {
    expect(
      friendlyError(const ApiRequestException(403, 'forbidden')),
      'ليست لديك الصلاحية لتنفيذ هذا الإجراء.',
    );
    expect(
      friendlyError(const ApiRequestException(409, 'يجب إضافة تعليق أولاً')),
      'يجب إضافة تعليق أولاً',
    );
    expect(
      friendlyError(const ApiRequestException(503, 'internal server error')),
      'الخادم يواجه مشكلة مؤقتة. حاول لاحقاً.',
    );
  });

  testWidgets('StatusChip is accessible and app theme supports both brightnesses', (tester) async {
    for (final brightness in [Brightness.light, Brightness.dark]) {
      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(brightness),
          home: const Scaffold(
            body: Center(child: StatusChip(status: AppStrings.waiting)),
          ),
        ),
      );
      expect(find.text(AppStrings.waiting), findsOneWidget);
      expect(find.byTooltip(AppStrings.waiting), findsOneWidget);
    }
  });
}
