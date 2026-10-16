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
              '网页登录与官方 API 授权分别影响不同功能。上次验证成功不保证当前仍然有效。',
              'Website login and official API authorization serve different features. A past successful check does not prove the current session is valid.',
            ),
          ),
          const SizedBox(height: 16),
          LoginStatusCard(
            title: t('网页登录', 'Website login'),
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
              '影响推荐及依赖网页登录的内容。',
              'Affects recommendations and content requiring website login.',
            ),
            check: verdict.isLocked
                ? null
                : () => ref
                      .read(webSessionStatusProvider.notifier)
                      .checkLoginStatus(),
            recover: () =>
                _recover(context, zh, t('恢复网页登录', 'Restore website login')),
            recoveryLabel: t('恢复网页登录', 'Restore website login'),
            storage: true,
          ),
          const SizedBox(height: 16),
          LoginStatusCard(
            title: t('官方 API 登录', 'Official API login'),
            observation: api,
            zh: zh,
            result: auth.status == AuthStatus.signedOut
                ? LoginCheckResult.unauthenticated
                : api.result,
            impact: t(
              '影响关注、通知、收藏等官方 API 功能。',
              'Affects official API features such as follows, notifications and favourites.',
            ),
            check: () =>
                ref.read(authControllerProvider.notifier).checkLoginStatus(),
            recover: () => _recover(
              context,
              zh,
              t('恢复 API 授权', 'Restore API authorization'),
            ),
            recoveryLabel: t('恢复 API 授权', 'Restore API authorization'),
          ),
          const SizedBox(height: 16),
          Text(
            t(
              '检查操作会合并在途请求，30 秒内重复点击不会新增请求。网页挑战受限时，请先打开登录页完成验证或稍后重试。',
              'Checks join an existing request and are limited to once per 30 seconds. If website verification is restricted, open the login page or try again later.',
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
        zh ? '现有登录流程可能同时检查或恢复网页登录与 API 授权。不会预先退出账号或清除 Cookie；完成后请分别查看两种登录状态。' : 'The existing login flow may check or restore both website login and API authorization. It does not sign you out or clear cookies first. Review both statuses afterwards.',
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
    LoginCheckResult.unknown => t('尚未验证', 'Not yet verified'),
    LoginCheckResult.authenticated => t('已验证登录', 'Login verified'),
    LoginCheckResult.unauthenticated => t(
      '未登录或需要重新登录',
      'Signed out or sign-in required',
    ),
    LoginCheckResult.unavailable => t('暂时无法确认', 'Unable to confirm'),
    LoginCheckResult.challenge => t(
      '网页验证受限',
      'Website verification restricted',
    ),
  };
  String storageLabel(LoginStorageResult value) => switch (value) {
    LoginStorageResult.unknown => t('尚未检查', 'Not checked'),
    LoginStorageResult.saved => t('已保存并读回', 'Saved and read back'),
    LoginStorageResult.restoring => t('正在恢复', 'Restoring'),
    LoginStorageResult.restored => t(
      '已写入并读回身份',
      'Written and identity read back',
    ),
    LoginStorageResult.notNeeded => t('未执行恢复', 'No restore performed'),
    LoginStorageResult.failed => t('异常', 'Failed'),
  };
  String reason(String value) => switch (value) {
    'timeout' => t('请求超时', 'Request timed out'),
    'challenge' => t('网页挑战受限', 'Website challenge restricted'),
    'unauthenticated' => t('未确认有效登录', 'No valid login confirmed'),
    'read_failed' => t('存储读回失败', 'Storage read-back failed'),
    'write_failed' => t('保存或保存后的读回失败', 'Save or subsequent read-back failed'),
    'missing_identity' => t('读回未确认账号', 'Read-back did not confirm an account'),
    'missing_snapshot' => t('没有可用的保存快照', 'No usable saved snapshot'),
    'partial_restore' => t(
      '部分 Cookie 未能写入',
      'Some cookies could not be written',
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
          Text(
            '${t('最近成功验证', 'Last successful verification')}: ${date(observation.lastSuccess)}',
          ),
          Text(
            '${t('最近检查原因', 'Last check reason')}: ${reason(observation.reason)}',
          ),
          Text(impact),
          if (storage) ...[
            const Divider(),
            Text(
              '${t('最近保存结果', 'Last save result')}: ${storageLabel(observation.save)}',
            ),
            Text(
              '${t('最近恢复结果', 'Last restore result')}: ${storageLabel(observation.restore)}',
            ),
            Text(
              '${t('存储记录时间', 'Storage observation time')}: ${date(observation.storageAt)}',
            ),
            if (observation.storageReason.isNotEmpty)
              Text(reason(observation.storageReason)),
            if (observation.save == LoginStorageResult.failed ||
                observation.restore == LoginStorageResult.failed)
              Text(
                t(
                  '登录状态保存或恢复异常；即使当前会话可用，下次启动仍可能需要重新登录。',
                  'Saving or restoring the login state failed. Even if this session works, a later launch may require sign-in.',
                ),
              ),
            Text(
              t(
                '本地保存、写入与读回结果不代表服务器接受了登录身份。',
                'Local save, write and read-back results do not prove server authentication.',
              ),
            ),
          ],
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
