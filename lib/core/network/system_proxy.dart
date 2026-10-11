import 'dart:io';

import 'package:flutter/services.dart';

import '../diagnostics/app_logger.dart';

const MethodChannel _systemProxyChannel = MethodChannel(
  'daviewer/system_proxy',
);

final class SystemProxyConfig {
  const SystemProxyConfig({required this.host, required this.port});

  final String host;
  final int port;

  @override
  bool operator ==(Object other) =>
      other is SystemProxyConfig && other.host == host && other.port == port;

  @override
  int get hashCode => Object.hash(host, port);

  @override
  String toString() => '$host:$port';
}

Future<SystemProxyConfig?> detectSystemProxy() async {
  if (Platform.isAndroid) return _detectAndroidProxy(AppLogger.instance);
  final logger = AppLogger.instance;
  if (Platform.isMacOS) return _detectMacOsProxy(logger);
  if (Platform.isWindows) return _detectWindowsProxy(logger);
  return null;
}

Future<SystemProxyConfig?> _detectAndroidProxy(AppLogger logger) async {
  try {
    final result = await _systemProxyChannel.invokeMapMethod<String, Object?>(
      'getSystemProxy',
    );
    final host = result?['host'];
    final port = result?['port'];
    if (host is! String || host.trim().isEmpty || port is! int) {
      logger.info('proxy', 'Android: no system HTTP proxy configured');
      return null;
    }
    if (port <= 0 || port > 65535) {
      logger.warning('proxy', 'Android: invalid system proxy port');
      return null;
    }
    final proxy = SystemProxyConfig(host: host.trim(), port: port);
    logger.info('proxy', 'Android: detected $proxy');
    return proxy;
  } on MissingPluginException {
    logger.warning('proxy', 'Android system proxy bridge unavailable');
    return null;
  } on Object catch (error, stack) {
    logger.warning(
      'proxy',
      'Android system proxy detection failed',
      error,
      stack,
    );
    return null;
  }
}

Future<SystemProxyConfig?> _detectMacOsProxy(AppLogger logger) async {
  try {
    final result = await Process.run('scutil', const <String>['--proxy']);
    final output = (result.stdout as String? ?? '').split('\n');
    final values = <String, String>{};
    for (final line in output) {
      final separator = line.indexOf(':');
      if (separator <= 0) continue;
      final key = line.substring(0, separator).trim();
      final value = line.substring(separator + 1).trim();
      if (key.isNotEmpty && value.isNotEmpty) values[key] = value;
    }

    // macOS can expose HTTP and HTTPS proxies independently; prefer HTTPS.
    final httpsEnabled = values['HTTPSEnable'] == '1';
    final httpEnabled = values['HTTPEnable'] == '1';
    final host = httpsEnabled
        ? values['HTTPSProxy']
        : httpEnabled
        ? values['HTTPProxy']
        : null;
    if (host == null || host.isEmpty) {
      logger.info('proxy', 'macOS: no static proxy configured');
      return null;
    }

    final port = int.tryParse(
      httpsEnabled ? values['HTTPSPort'] ?? '' : values['HTTPPort'] ?? '',
    );
    if (port == null || port <= 0 || port > 65535) {
      logger.warning('proxy', 'macOS: invalid proxy port, ignoring');
      return null;
    }
    logger.info('proxy', 'macOS: detected $host:$port');
    return SystemProxyConfig(host: host, port: port);
  } on Object catch (error, stack) {
    logger.warning('proxy', 'macOS proxy detection failed', error, stack);
    return null;
  }
}

Future<SystemProxyConfig?> _detectWindowsProxy(AppLogger logger) async {
  try {
    final enabledResult = await Process.run('reg', const <String>[
      'query',
      r'HKCU\Software\Microsoft\Windows\CurrentVersion\Internet Settings',
      '/v',
      'ProxyEnable',
    ]);
    final enabledOutput = enabledResult.stdout as String? ?? '';
    if (!enabledOutput.contains('0x1')) {
      logger.info('proxy', 'Windows: proxy disabled');
      return null;
    }

    final serverResult = await Process.run('reg', const <String>[
      'query',
      r'HKCU\Software\Microsoft\Windows\CurrentVersion\Internet Settings',
      '/v',
      'ProxyServer',
    ]);
    final serverOutput = serverResult.stdout as String? ?? '';
    final match = RegExp(r'ProxyServer\s+REG_SZ\s+([^\r\n]+)')
        .firstMatch(serverOutput);
    final server = match?.group(1)?.trim();
    if (server == null || server.isEmpty) {
      logger.info('proxy', 'Windows: no proxy server value');
      return null;
    }

    final parsed = parseWindowsProxyServer(server);
    if (parsed == null) {
      logger.warning('proxy', 'Windows: invalid proxy server "$server"');
      return null;
    }
    logger.info('proxy', 'Windows: detected $parsed');
    return parsed;
  } on Object catch (error, stack) {
    logger.warning('proxy', 'Windows proxy detection failed', error, stack);
    return null;
  }
}

/// Parses both Windows' single `host:port` value and its protocol-specific
/// `http=host:port;https=host:port` form. HTTPS takes precedence because all
/// DeviantArt endpoints are HTTPS.
SystemProxyConfig? parseWindowsProxyServer(String value) {
  var candidate = value.trim();
  if (candidate.contains('=')) {
    final entries = <String, String>{};
    for (final part in candidate.split(';')) {
      final separator = part.indexOf('=');
      if (separator <= 0) continue;
      entries[part.substring(0, separator).trim().toLowerCase()] = part
          .substring(separator + 1)
          .trim();
    }
    candidate = entries['https'] ?? entries['http'] ?? '';
  }
  if (candidate.isEmpty) return null;
  final uri = Uri.tryParse(
    candidate.contains('://') ? candidate : 'http://$candidate',
  );
  if (uri == null || uri.host.isEmpty || uri.userInfo.isNotEmpty) return null;
  final port = uri.hasPort ? uri.port : 8080;
  if (port <= 0 || port > 65535) return null;
  return SystemProxyConfig(host: uri.host, port: port);
}
