import 'package:flutter/material.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'app/app_scope.dart';
import 'app/theme.dart';
import 'data/quote_repository.dart';
import 'state/app_state.dart';
import 'ui/root_shell.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('ko_KR');
  final state = AppState(repository: MockQuoteRepository());
  runApp(MarketPeekApp(state: state));
  await state.load();
}

class MarketPeekApp extends StatelessWidget {
  const MarketPeekApp({super.key, required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    return AppScope(
      state: state,
      child: MaterialApp(
        title: 'MarketPeek',
        debugShowCheckedModeBanner: false,
        theme: buildTheme(),
        home: const RootShell(),
      ),
    );
  }
}
