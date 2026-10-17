import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/auth/auth_controller.dart';
import '../../core/auth/auth_state.dart';
import '../../core/auth/login_observation.dart';
import '../../core/auth/web_session_status.dart';
import '../../core/l10n/app_strings.dart';

final class LoginStatusScreen extends ConsumerWidget {
  const LoginStatusScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final zh = ref.watch(appLanguageProvider) == AppLanguage.zh;
    String t(String cn, String en) => zh ? cn : en;
    final web = ref.watch(loginObservationProvider(LoginChannel.web));
    final api = ref.watch(loginObservationProvider(LoginChannel.api));
    final auth = ref.watch(authControllerProvider);
    final verdict = ref.watch(webSessionStatusProvider);
    return Scaffold(
      appBar: AppBar(title: Text(t('登录状态', 'Login status'))),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            t(
              '推荐浏览和账号互动的登录状态可能不同。功能无法使用时，可以在这里检查，或打开登录页重新登录。以下显示最近一次检查结果。',
              'Browsing and account interactions may have different sign-in states. If a feature stops working, check its status here or sign in again. Results below reflect the most recent check.',
            ),
          ),
          const SizedBox(height: 16),
          LoginStatusCard(
            title: t('推荐与内容浏览', 'Recommendations and browsing'),
            observation: web,
            zh: zh,
            // The chain owns the current verdict; the observation only carries
            // the last attempt. A check the chain answers from a retained
            // healthy lease stamps no result, and rendering that as unknown
            // would contradict the verdict the app acts on.
            result: verdict.isLocked
                ? LoginCheckResult.challenge
                : verdict.isHealthy &&
                      web.result == LoginCheckResult.unavailable
                ? LoginCheckResult.authenticated
                : web.result,
            impact: t(
              '用于加载个性化推荐和需要登录才能查看的内容。',
              'Used for personalized recommendations and content that requires sign-in.',
            ),
            check: verdict.isLocked
                ? null
                : () => ref
                      .read(webSessionStatusProvider.notifier)
                      .checkLoginStatus(),
            recover: () =>
                _recover(context, zh, t('打开登录页', 'Open sign-in page')),
            recoveryLabel: t('打开登录页', 'Open sign-in page'),
            storage: true,
          ),
          const SizedBox(height: 16),
          LoginStatusCard(
            title: t('关注、收藏与通知', 'Following, favourites and notifications'),
            observation: api,
            zh: zh,
            result: auth.status == AuthStatus.signedOut
                ? LoginCheckResult.unauthenticated
                : api.result,
            impact: t(
              '用于关注画师、收藏作品和查看通知。',
              'Used to follow artists, favourite artworks and view notifications.',
            ),
            check: () =>
                ref.read(authControllerProvider.notifier).checkLoginStatus(),
            recover: () =>
                _recover(context, zh, t('打开登录页', 'Open sign-in page')),
            recoveryLabel: t('打开登录页', 'Open sign-in page'),
          ),
          const SizedBox(height: 16),
          Text(
            t(
              '检查后请等待 30 秒再试。如果提示需要验证，请打开登录页，按网页提示完成操作。',
              'Wait 30 seconds between checks. If verification is needed, open the sign-in page and follow the website instructions.',
            ),
          ),
        ],
      ),
    );
  }
}

Future<void> _recover(BuildContext context, bool zh, String title) async {
  final proceed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: Text(
        zh ? '请按网页提示登录或完成验证。完成后返回这里，查看两项登录状态是否恢复。' : 'Follow the website instructions to sign in or complete verification. Then return here to check both sign-in states.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: Text(zh ? '取消' : 'Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: Text(zh ? '打开登录页' : 'Open login page'),
        ),
      ],
    ),
  );
  if (proceed == true && context.mounted) await context.push('/web-login');
}

final class LoginStatusCard extends StatelessWidget {
  const LoginStatusCard({
    super.key,
    required this.title,
    required this.observation,
    required this.result,
    required this.impact,
    required this.zh,
    required this.check,
    required this.recover,
    required this.recoveryLabel,
    this.storage = false,
  });
  final String title;
  final LoginObservation observation;
  final LoginCheckResult result;
  final String impact;
  final bool zh;
  final Future<void> Function()? check;
  final VoidCallback recover;
  final String recoveryLabel;
  final bool storage;
  String t(String cn, String en) => zh ? cn : en;
  String date(DateTime? value) => value == null
      ? t('暂无记录', 'No record')
      : value.toLocal().toString().split('.').first;
  String get label => switch (result) {
    LoginCheckResult.unknown => t('还未检查', 'Not checked yet'),
    LoginCheckResult.authenticated => t('上次检查：已登录', 'Last check: signed in'),
    LoginCheckResult.unauthenticated => t(
      '需要登录，请打开登录页',
      'Sign-in needed. Open the sign-in page.',
    ),
    LoginCheckResult.unavailable => t(
      '暂时无法检查，请稍后重试',
      'Unable to check. Try again later.',
    ),
    LoginCheckResult.challenge => t(
      '需要网页验证，请打开登录页',
      'Verification needed. Open the sign-in page.',
    ),
  };
  String storageLabel(LoginStorageResult value) => switch (value) {
    LoginStorageResult.unknown => t('尚未检查', 'Not checked'),
    LoginStorageResult.saved => t('已保存登录信息', 'Sign-in details saved'),
    LoginStorageResult.restoring => t('正在恢复', 'Restoring'),
    LoginStorageResult.restored => t(
      '已恢复保存的登录信息',
      'Saved sign-in details restored',
    ),
    LoginStorageResult.notNeeded => t('无需恢复', 'No restore needed'),
    LoginStorageResult.failed => t('异常', 'Failed'),
  };
  String reason(String value) => switch (value) {
    'timeout' => t('请求超时', 'Request timed out'),
    'challenge' => t(
      '请在登录页完成网页验证',
      'Complete verification on the sign-in page',
    ),
    'unauthenticated' => t('请重新登录', 'Please sign in again'),
    'read_failed' => t('无法读取保存的登录信息', 'Could not read saved sign-in details'),
    'write_failed' => t(
      '无法保存或读取登录信息',
      'Could not save or read sign-in details',
    ),
    'missing_identity' => t(
      '保存的登录信息中没有找到账号',
      'No account found in saved sign-in details',
    ),
    'missing_snapshot' => t(
      '没有可恢复的登录信息',
      'No saved sign-in details to restore',
    ),
    'partial_restore' => t(
      '登录信息未能完整恢复',
      'Sign-in details could not be fully restored',
    ),
    'unavailable' || 'network' => t(
      '网络、服务或本地存储暂时不可用',
      'Network, service or local storage unavailable',
    ),
    _ => t('无', 'None'),
  };

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          Text(label, key: ValueKey('$title-result')),
          if (observation.checking) ...[
            const SizedBox(height: 8),
            const LinearProgressIndicator(),
            Text(t('正在检查…', 'Checking…')),
          ],
          if (observation.owner.isNotEmpty)
            Text('${t('账号', 'Account')}: ${observation.owner}'),
          Text('${t('最近检查', 'Last check')}: ${date(observation.lastAttempt)}'),
          Text(impact),
          if (storage &&
              (observation.save == LoginStorageResult.failed ||
                  observation.restore == LoginStorageResult.failed))
            Text(
              t(
                '登录信息未能保存或恢复，下次打开应用时可能需要重新登录。',
                'Sign-in details could not be saved or restored. You may need to sign in again next time.',
              ),
            ),
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            title: Text(t('查看检查详情', 'Check details')),
            children: [
              Text(
                '${t('上次登录成功', 'Last successful sign-in check')}: ${date(observation.lastSuccess)}',
              ),
              if (observation.reason.isNotEmpty)
                Text(
                  '${t('检查说明', 'Check information')}: ${reason(observation.reason)}',
                ),
              if (storage) ...[
                Text(
                  '${t('最近保存结果', 'Last save result')}: ${storageLabel(observation.save)}',
                ),
                Text(
                  '${t('最近恢复结果', 'Last restore result')}: ${storageLabel(observation.restore)}',
                ),
                Text(
                  '${t('登录信息更新时间', 'Sign-in details updated')}: ${date(observation.storageAt)}',
                ),
                if (observation.storageReason.isNotEmpty)
                  Text(reason(observation.storageReason)),
                Text(
                  t(
                    '已保存登录信息不代表仍然处于登录状态，请以上方检查结果为准。',
                    'Saved sign-in details do not guarantee you are still signed in. Refer to the check result above.',
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              OutlinedButton(
                onPressed: observation.checking ? null : check,
                child: Text(t('检查登录状态', 'Check login status')),
              ),
              TextButton(
                onPressed: observation.checking ? null : recover,
                child: Text(recoveryLabel),
              ),
            ],
          ),
        ],
      ),
    ),
  );
}
