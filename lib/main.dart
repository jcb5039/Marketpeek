import 'package:flutter/material.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'app/app_scope.dart';
import 'app/theme.dart';
import 'data/quote_repository.dart';
import 'data/server_quote_repository.dart';
import 'data/upbit_quote_repository.dart';
import 'state/app_state.dart';
import 'ui/root_shell.dart';

/// 시세 서버 주소. 빌드할 때 `--dart-define=API_BASE_URL=https://...workers.dev`로 넣는다.
/// 비어 있으면 미국주식·환율·이슈는 예시 값(MockQuoteRepository)을 쓴다.
const apiBaseUrl = String.fromEnvironment('API_BASE_URL');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('ko_KR');
  // 코인은 업비트 실시세, 미국주식·환율·이슈는 서버(없으면 예시 값).
  final QuoteRepository others = apiBaseUrl.isEmpty
      ? MockQuoteRepository()
      : ServerQuoteRepository(baseUrl: apiBaseUrl);
  final upbit = UpbitQuoteRepository(fallback: others);
  final state = AppState(
    repository: upbit,
    coinListLoader: upbit.fetchCoinList,
  );
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
