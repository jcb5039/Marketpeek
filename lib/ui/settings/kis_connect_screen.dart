import 'package:flutter/material.dart';

import '../../app/app_scope.dart';
import '../../app/theme.dart';
import '../../data/kis_quote_repository.dart';

/// 한국투자증권 Open API 키 입력. 키는 기기 Keychain에만 저장하고 서버로 보내지 않는다.
/// 키 신청 방법은 저장소 루트 key.md.
class KisConnectScreen extends StatefulWidget {
  const KisConnectScreen({super.key});

  @override
  State<KisConnectScreen> createState() => _KisConnectScreenState();
}

class _KisConnectScreenState extends State<KisConnectScreen> {
  final _key = TextEditingController();
  final _secret = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _key.dispose();
    _secret.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final key = _key.text.trim();
    final secret = _secret.text.trim();
    if (key.isEmpty || secret.isEmpty) {
      setState(() => _error = 'App Key와 App Secret을 모두 넣어주세요');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await AppScope.read(context).connectKis(KisCredentials(appKey: key, appSecret: secret));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('연결됐어요')));
      Navigator.of(context).pop();
    } on KisApiException catch (e) {
      setState(() => _error = '연결하지 못했어요: ${e.message}');
    } catch (e) {
      setState(() => _error = '연결하지 못했어요. 네트워크를 확인해주세요 ($e)');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _disconnect() async {
    setState(() => _busy = true);
    await AppScope.read(context).disconnectKis();
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('증권사 연결')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
        children: [
          Text(
            s.kisConnected
                ? '한국투자증권에 연결돼 있어요. 주식 시세를 한국투자증권에서 받아와요.'
                : '한국투자증권 Open API 키를 넣으면 주식 시세를 받아와요. '
                    '키는 이 폰에만 저장되고 다른 곳으로 보내지 않아요.',
            style: TextStyles.sub.copyWith(height: 1.5),
          ),
          const SizedBox(height: 20),
          if (s.kisConnected)
            OutlinedButton(
              onPressed: _busy ? null : _disconnect,
              child: const Text('연결 해제'),
            )
          else ...[
            TextField(
              controller: _key,
              enabled: !_busy,
              autocorrect: false,
              enableSuggestions: false,
              decoration: const InputDecoration(labelText: 'App Key', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _secret,
              enabled: !_busy,
              obscureText: true,
              autocorrect: false,
              enableSuggestions: false,
              decoration: const InputDecoration(labelText: 'App Secret', border: OutlineInputBorder()),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: const TextStyle(fontSize: 13, color: AppColors.krUp)),
            ],
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _busy ? null : _save,
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.accent,
                minimumSize: const Size.fromHeight(50),
              ),
              child: _busy
                  ? const SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('저장하고 연결 확인'),
            ),
            const SizedBox(height: 12),
            const Text(
              '실전투자용 키를 넣어주세요. 이 키로 받은 시세는 본인만 볼 수 있어요.',
              style: TextStyles.caption,
            ),
          ],
        ],
      ),
    );
  }
}
