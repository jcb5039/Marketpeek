import 'package:flutter/widgets.dart';

import '../state/app_state.dart';

/// 위젯 트리에 [AppState]를 내려주는 InheritedNotifier.
class AppScope extends InheritedNotifier<AppState> {
  const AppScope({super.key, required AppState state, required super.child})
      : super(notifier: state);

  static AppState of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AppScope>()!.notifier!;

  /// 리빌드 구독 없이 액션만 호출할 때.
  static AppState read(BuildContext context) =>
      context.getInheritedWidgetOfExactType<AppScope>()!.notifier!;
}
