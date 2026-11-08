import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:intl/date_symbol_data_local.dart';

import 'app/app_scope.dart';
import 'app/theme.dart';
import 'data/catalog.dart';
import 'data/kis_quote_repository.dart';
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
  await Catalog.loadStockAssets(rootBundle); // 국내·미국 전체 종목 (검색용)
  // 코인은 업비트, 주식은 한국투자증권(설정에서 내 키를 넣었을 때), 환율·이슈는 서버.
  // 서버 주소가 없으면 환율·이슈와 (키 없을 때의) 주식은 예시 값.
  final QuoteRepository others = apiBaseUrl.isEmpty
      ? MockQuoteRepository()
      : ServerQuoteRepository(baseUrl: apiBaseUrl);
  final kis = KisQuoteRepository(fallback: others, store: SecureKisCredentialStore());
  final upbit = UpbitQuoteRepository(fallback: kis);
  final state = AppState(
    repository: upbit,
    coinListLoader: upbit.fetchCoinList,
    kis: kis,
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
