import 'core_rpc.dart';

/// A small, stable set of categories used in user-facing core errors.
enum CoreErrorCategory {
  configuration,
  permission,
  process,
  systemProxy,
  tun,
  timeout,
  connection,
  profile,
  maintenance,
  unsupported,
  unknown,
}

extension CoreErrorCategoryLabels on CoreErrorCategory {
  String get labelKey => switch (this) {
    CoreErrorCategory.configuration => 'coreErrorConfiguration',
    CoreErrorCategory.permission => 'coreErrorPermission',
    CoreErrorCategory.process => 'coreErrorProcess',
    CoreErrorCategory.systemProxy => 'coreErrorSystemProxy',
    CoreErrorCategory.tun => 'coreErrorTun',
    CoreErrorCategory.timeout => 'coreErrorTimeout',
    CoreErrorCategory.connection => 'coreErrorConnection',
    CoreErrorCategory.profile => 'coreErrorProfile',
    CoreErrorCategory.maintenance => 'coreErrorMaintenance',
    CoreErrorCategory.unsupported => 'coreErrorUnsupported',
    CoreErrorCategory.unknown => 'coreErrorUnknown',
  };
}

CoreErrorCategory classifyCoreError(Object error) {
  final code = error is CoreException ? error.code.toLowerCase() : '';
  final text = '$code ${error.toString()}'.toLowerCase();
  if (code == 'profile_required' || text.contains('profile')) {
    return CoreErrorCategory.profile;
  }
  if (code == 'maintenance' || code == 'core_busy') {
    return CoreErrorCategory.maintenance;
  }
  if (code == 'unsupported' || code == 'preview') {
    return CoreErrorCategory.unsupported;
  }
  if (code == 'system_proxy' || text.contains('system proxy')) {
    return CoreErrorCategory.systemProxy;
  }
  if (code == 'approval_required' ||
      code == 'permission' ||
      code == 'access_denied' ||
      code == 'login_item' ||
      text.contains('permission') ||
      text.contains('administrator') ||
      text.contains('vpn permission')) {
    return CoreErrorCategory.permission;
  }
  if (code.startsWith('helper_') ||
      code == 'tun' ||
      code == 'android_init' ||
      code == 'android_start' ||
      code == 'android_state' ||
      code == 'android_stop' ||
      text.contains('tun')) {
    return CoreErrorCategory.tun;
  }
  if (code == 'timeout' || text.contains('timed out')) {
    return CoreErrorCategory.timeout;
  }
  if (code == 'missing_core' ||
      code == 'process_exit' ||
      code == 'crash' ||
      text.contains('core process') ||
      text.contains('core exited')) {
    return CoreErrorCategory.process;
  }
  if (code == 'config' ||
      code == 'core_error' ||
      code == 'mode' ||
      code == 'update_failed' ||
      code == 'invalid_config' ||
      text.contains('config') ||
      text.contains('yaml')) {
    return CoreErrorCategory.configuration;
  }
  if (code == 'disconnected' ||
      code == 'not_ready' ||
      code == 'closed' ||
      code == 'busy' ||
      code.startsWith('android_')) {
    return CoreErrorCategory.connection;
  }
  return CoreErrorCategory.unknown;
}

String coreErrorMessage(Object error) =>
    error is CoreException ? error.message : error.toString();
