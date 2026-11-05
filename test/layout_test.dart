import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:marketpeek/app/app_scope.dart';
import 'package:marketpeek/app/theme.dart';
import 'package:marketpeek/data/quote_repository.dart';
import 'package:marketpeek/state/app_state.dart';
import 'package:marketpeek/ui/settings/settings_screen.dart';
import 'package:marketpeek/ui/widgets_tab/widget_guide_screen.dart';
import 'package:marketpeek/widget_bridge/widget_sync.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _NoopSync extends WidgetSync {
  @override
  Future<void> push(AppState state) async {}
}

/// 작은 아이폰(SE, 375x667) 폭에서 넘침(overflow) 없는지 확인.
void main() {
  setUpAll(() => initializeDateFormatting('ko_KR'));
  setUp(() => SharedPreferences.setMockInitialValues({}));

  for (final (name, screen) in [
    ('설정', const SettingsScreen()),
    ('위젯 추가 방법', const WidgetGuideScreen()),
  ]) {
    testWidgets('$name 화면이 작은 화면에서 넘치지 않는다', (tester) async {
      tester.view.physicalSize = const Size(375, 667);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final s = AppState(repository: MockQuoteRepository(), widgetSync: _NoopSync());
      await tester.pumpWidget(AppScope(
        state: s,
        child: MaterialApp(theme: buildTheme(), home: screen),
      ));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }
}
