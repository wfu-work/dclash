abstract final class HealthTranslations {
  static const en = <String, String>{
    'healthTitle': 'Network health check',
    'healthHelp':
        'Check the service, local proxy, system DNS, and URL connectivity in one run.',
    'healthScope':
        'URL checks run inside the core. They do not verify traffic capture for every app. System DNS uses this device’s resolver; TUN capture is not verified here. Direct tests bypass proxy nodes but still use the core’s DNS settings.',
    'healthCopy': 'Copy diagnostic results',
    'healthHistory': 'Diagnostic history',
    'healthHistoryHelp':
        'Completed reports are stored locally on this device. The newest 20 reports are kept.',
    'healthHistoryEmpty': 'No completed reports yet',
    'healthHistoryEmptyHelp':
        'Run a network health check to save its results here.',
    'healthHistoryClear': 'Clear history',
    'healthHistoryClearConfirm':
        'Clear all locally stored network diagnostic reports? This cannot be undone.',
    'healthHistoryCleared': 'Diagnostic history cleared',
    'healthHistorySaveFailed':
        'This diagnostic finished, but its local report could not be saved.',
    'healthReport': 'Diagnostic report',
    'healthExport': 'Export report',
    'healthCheckedAt': 'Checked at @time',
    'healthEmpty': 'Run a check to locate connection problems',
    'healthPreview': 'Preview mode: live network checks are disabled.',
    'healthPassed': 'All checks passed',
    'healthAttention': 'Check complete — review the items below',
    'healthCounts': '@failed failed · @warnings need attention',
    'healthCheck_core': 'Core service',
    'healthCheck_listener': 'Local proxy listener',
    'healthCheck_systemProxy': 'System proxy',
    'healthCheck_dns': 'System DNS',
    'healthCheck_direct': 'Direct URL connection',
    'healthCheck_routing': 'Current routing rules',
    'healthStatus_checking': 'Testing',
    'healthStatus_passed': 'Passed',
    'healthStatus_warning': 'Needs attention',
    'healthStatus_failed': 'Failed',
    'healthStatus_skipped': 'Skipped',
    'healthCoreRunning': 'The core is running.',
    'healthCoreStopped':
        'The core is not running. Select a profile and connect from Overview.',
    'healthListenerPassed':
        'The configured local TCP port accepts connections.',
    'healthListenerFailed':
        'The local proxy port is unreachable. Check the port setting and service logs.',
    'healthProxyPassed':
        'The OS HTTP and HTTPS proxy settings point to this app’s local port.',
    'healthProxyMismatch':
        'The actual system proxy differs from the requested local proxy. Check Network settings.',
    'healthProxyCoreStopped':
        'The system proxy points to the local port while the core is stopped.',
    'healthProxyUnsupported':
        'This platform’s system proxy cannot be verified automatically. Check Network settings.',
    'healthTunUnverified':
        'TUN is enabled in settings. Its traffic capture is not verified by this check.',
    'healthProxyOther':
        'The system uses a different proxy or automatic configuration. Check whether this is intended.',
    'healthProxyOff':
        'No system proxy is active. Apps must use an explicit proxy or a working TUN connection.',
    'healthProxyReadFailed':
        'Could not read the actual system proxy. Check it in the OS network settings.',
    'healthDnsIp': 'The URL uses an IP address; no DNS lookup is needed.',
    'healthDnsPassed': 'The system resolver returned addresses in @ms ms.',
    'healthDnsFailed':
        'System DNS lookup failed. Check the device’s DNS and network connection.',
    'healthDnsEmpty': 'The system resolver returned no addresses.',
    'healthHttpResponse':
        'HTTP @code · @ms ms. Error responses can indicate site restrictions.',
    'healthRequestFailed':
        'No usable HTTP response. Open URL diagnostics to inspect the route.',
    'healthRoutingFailedAdvice':
        'Direct access works, but current routing failed. Inspect the matched rule and selected proxy in URL diagnostics.',
    'healthRemoteDnsAdvice':
        'System DNS failed while current routing works. The two checks can use different DNS paths; inspect the system DNS settings.',
    'healthDirectFailedAdvice':
        'Current routing works while direct access failed. This target may require a proxy on your network.',
    'healthBothFailedAdvice':
        'Both URL routes failed. Check the network, target URL, DNS, and service logs.',
    'healthAction_overview': 'Open Overview',
    'healthAction_profiles': 'Select a profile',
    'healthAction_networkSettings': 'Open Network settings',
    'healthAction_urlDiagnostics': 'Inspect URL and routes',
    'healthAction_logs': 'View service logs',
  };

  static const zh = <String, String>{
    'healthTitle': '一键网络诊断',
    'healthHelp': '一次检查核心服务、本地代理、系统 DNS 和网址连通性。',
    'healthScope':
        '网址检测由内核发起，不能代表所有应用均已接管。系统 DNS 使用设备解析路径；本页不验证 TUN 接管状态。直连检测绕过代理节点，但仍使用内核的 DNS 配置。',
    'healthCopy': '复制诊断结果',
    'healthHistory': '诊断历史',
    'healthHistoryHelp': '诊断报告仅保存在本设备，最多保留最近 20 条。',
    'healthHistoryEmpty': '暂无已完成的诊断报告',
    'healthHistoryEmptyHelp': '完成一次一键网络诊断后，结果会保存在这里。',
    'healthHistoryClear': '清空历史',
    'healthHistoryClearConfirm': '清空所有本地保存的网络诊断报告？此操作无法撤销。',
    'healthHistoryCleared': '诊断历史已清空',
    'healthHistorySaveFailed': '本次诊断已完成，但未能保存本地报告。',
    'healthReport': '诊断报告',
    'healthExport': '导出报告',
    'healthCheckedAt': '检测时间：@time',
    'healthEmpty': '开始诊断，定位连接问题',
    'healthPreview': '预览模式下不执行实际网络检测。',
    'healthPassed': '所有检查均已通过',
    'healthAttention': '诊断完成，请查看下方待处理项',
    'healthCounts': '@failed 项失败 · @warnings 项需关注',
    'healthCheck_core': '核心服务',
    'healthCheck_listener': '本地代理监听',
    'healthCheck_systemProxy': '系统代理',
    'healthCheck_dns': '系统 DNS',
    'healthCheck_direct': '网址直连',
    'healthCheck_routing': '当前分流规则',
    'healthStatus_checking': '正在检测',
    'healthStatus_passed': '通过',
    'healthStatus_warning': '需关注',
    'healthStatus_failed': '失败',
    'healthStatus_skipped': '已跳过',
    'healthCoreRunning': '核心服务正在运行。',
    'healthCoreStopped': '核心服务尚未运行，请选择配置并在仪表盘连接。',
    'healthListenerPassed': '配置的本地 TCP 端口可接受连接。',
    'healthListenerFailed': '无法连接本地代理端口，请检查端口设置和服务日志。',
    'healthProxyPassed': '系统 HTTP 和 HTTPS 代理均指向本应用的本地端口。',
    'healthProxyMismatch': '实际系统代理与设置的本地代理不一致，请检查网络设置。',
    'healthProxyCoreStopped': '核心已停止，但系统代理仍指向本地端口。',
    'healthProxyUnsupported': '当前平台暂不支持自动核验系统代理，请检查网络设置。',
    'healthTunUnverified': '设置中已启用 TUN，本项尚未验证其实际流量接管状态。',
    'healthProxyOther': '系统正在使用其他代理或自动配置，请确认是否符合预期。',
    'healthProxyOff': '系统代理未启用，应用需手动指定代理，或通过正常运行的 TUN 接管。',
    'healthProxyReadFailed': '无法读取实际系统代理，请在系统网络设置中检查。',
    'healthDnsIp': '网址使用 IP 地址，无需解析域名。',
    'healthDnsPassed': '系统解析成功，耗时 @ms ms。',
    'healthDnsFailed': '系统 DNS 解析失败，请检查设备 DNS 和网络连接。',
    'healthDnsEmpty': '系统解析未返回地址。',
    'healthHttpResponse': 'HTTP @code · @ms ms。错误响应可能来自站点访问限制。',
    'healthRequestFailed': '未获得有效 HTTP 响应，可进入网址诊断查看具体线路。',
    'healthRoutingFailedAdvice': '直连可用，但当前路由请求失败。请进入网址诊断检查命中规则和所选节点。',
    'healthRemoteDnsAdvice':
        '系统 DNS 解析失败，但当前路由仍可访问。两者可能使用不同的 DNS 路径，请检查系统 DNS 设置。',
    'healthDirectFailedAdvice': '当前路由可用，但直连失败。此网址在当前网络下可能需要代理。',
    'healthBothFailedAdvice': '两条线路请求均失败，请检查网络、目标网址、DNS 和服务日志。',
    'healthAction_overview': '前往仪表盘',
    'healthAction_profiles': '选择配置',
    'healthAction_networkSettings': '打开网络设置',
    'healthAction_urlDiagnostics': '查看网址与线路',
    'healthAction_logs': '查看服务日志',
  };
}
