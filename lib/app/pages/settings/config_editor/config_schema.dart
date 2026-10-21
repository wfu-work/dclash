enum ConfigFieldKind { toggle, text, number, list, choice }

class ConfigField {
  const ConfigField(
    this.key,
    this.label,
    this.kind, {
    this.section = 'cfgGeneral',
    this.options = const [],
    this.hint,
    this.minimum,
    this.maximum,
    this.numericList = false,
  });
  final String key, label, section;
  final ConfigFieldKind kind;
  final List<String> options;
  final String? hint;
  final int? minimum, maximum;
  final bool numericList;
  List<String> get path => key.split('.');
}

abstract final class ConfigSchemas {
  static const supported = {
    'dnsOverride',
    'tunOverride',
    'snifferOverride',
    'ntpOverride',
  };
  static List<ConfigField> forSetting(String setting) => switch (setting) {
    'dnsOverride' => dns,
    'tunOverride' => tun,
    'snifferOverride' => sniffer,
    'ntpOverride' => ntp,
    _ => const [],
  };

  static const dns = [
    ConfigField('enable', 'cfgEnabled', ConfigFieldKind.toggle),
    ConfigField('ipv6', 'cfgDnsIpv6', ConfigFieldKind.toggle),
    ConfigField(
      'listen',
      'cfgDnsListen',
      ConfigFieldKind.text,
      hint: '127.0.0.1:1053',
    ),
    ConfigField(
      'enhanced-mode',
      'cfgDnsMode',
      ConfigFieldKind.choice,
      options: ['fake-ip', 'redir-host'],
    ),
    ConfigField(
      'fake-ip-range',
      'cfgFakeIpRange',
      ConfigFieldKind.text,
      hint: '198.18.0.1/16',
    ),
    ConfigField('use-hosts', 'cfgUseHosts', ConfigFieldKind.toggle),
    ConfigField(
      'use-system-hosts',
      'cfgUseSystemHosts',
      ConfigFieldKind.toggle,
    ),
    ConfigField('respect-rules', 'cfgRespectRules', ConfigFieldKind.toggle),
    ConfigField(
      'default-nameserver',
      'cfgDefaultNameserver',
      ConfigFieldKind.list,
      section: 'cfgDnsServers',
      hint: '1.1.1.1\n223.5.5.5',
    ),
    ConfigField(
      'nameserver',
      'cfgNameserver',
      ConfigFieldKind.list,
      section: 'cfgDnsServers',
      hint: 'https://dns.alidns.com/dns-query',
    ),
    ConfigField(
      'proxy-server-nameserver',
      'cfgProxyNameserver',
      ConfigFieldKind.list,
      section: 'cfgDnsServers',
    ),
    ConfigField(
      'direct-nameserver',
      'cfgDirectNameserver',
      ConfigFieldKind.list,
      section: 'cfgDnsServers',
    ),
    ConfigField(
      'fallback',
      'cfgFallbackNameserver',
      ConfigFieldKind.list,
      section: 'cfgDnsServers',
    ),
    ConfigField(
      'fake-ip-filter',
      'cfgFakeIpFilter',
      ConfigFieldKind.list,
      section: 'cfgDnsServers',
      hint: '*.lan\n+.local',
    ),
  ];

  static const tun = [
    ConfigField('device', 'cfgTunDevice', ConfigFieldKind.text, hint: 'utun'),
    ConfigField(
      'mtu',
      'cfgTunMtu',
      ConfigFieldKind.number,
      minimum: 576,
      maximum: 65535,
    ),
    ConfigField('auto-route', 'cfgAutoRoute', ConfigFieldKind.toggle),
    ConfigField(
      'auto-detect-interface',
      'cfgAutoDetectInterface',
      ConfigFieldKind.toggle,
    ),
    ConfigField('strict-route', 'cfgStrictRoute', ConfigFieldKind.toggle),
    ConfigField(
      'endpoint-independent-nat',
      'cfgEndpointNat',
      ConfigFieldKind.toggle,
    ),
    ConfigField(
      'udp-timeout',
      'cfgUdpTimeout',
      ConfigFieldKind.number,
      minimum: 0,
      maximum: 86400,
    ),
    ConfigField(
      'dns-hijack',
      'cfgDnsHijack',
      ConfigFieldKind.list,
      section: 'cfgTunRoutes',
      hint: 'any:53\ntcp://any:53',
    ),
    ConfigField(
      'route-address',
      'cfgRouteAddress',
      ConfigFieldKind.list,
      section: 'cfgTunRoutes',
      hint: '0.0.0.0/1\n128.0.0.0/1',
    ),
    ConfigField(
      'route-exclude-address',
      'cfgRouteExclude',
      ConfigFieldKind.list,
      section: 'cfgTunRoutes',
      hint: '192.168.0.0/16',
    ),
  ];

  static const sniffer = [
    ConfigField('enable', 'cfgEnabled', ConfigFieldKind.toggle),
    ConfigField(
      'force-dns-mapping',
      'cfgForceDnsMapping',
      ConfigFieldKind.toggle,
    ),
    ConfigField('parse-pure-ip', 'cfgParsePureIp', ConfigFieldKind.toggle),
    ConfigField(
      'override-destination',
      'cfgOverrideDestination',
      ConfigFieldKind.toggle,
    ),
    ConfigField(
      'sniff.HTTP.ports',
      'cfgHttpPorts',
      ConfigFieldKind.list,
      section: 'cfgSniffProtocols',
      numericList: true,
      hint: '80\n8080-8880',
    ),
    ConfigField(
      'sniff.HTTP.override-destination',
      'cfgHttpOverride',
      ConfigFieldKind.toggle,
      section: 'cfgSniffProtocols',
    ),
    ConfigField(
      'sniff.TLS.ports',
      'cfgTlsPorts',
      ConfigFieldKind.list,
      section: 'cfgSniffProtocols',
      numericList: true,
      hint: '443\n8443',
    ),
    ConfigField(
      'sniff.QUIC.ports',
      'cfgQuicPorts',
      ConfigFieldKind.list,
      section: 'cfgSniffProtocols',
      numericList: true,
      hint: '443',
    ),
    ConfigField(
      'force-domain',
      'cfgForceDomain',
      ConfigFieldKind.list,
      section: 'cfgSniffFilters',
      hint: '+.example.com',
    ),
    ConfigField(
      'skip-domain',
      'cfgSkipDomain',
      ConfigFieldKind.list,
      section: 'cfgSniffFilters',
    ),
    ConfigField(
      'skip-src-address',
      'cfgSkipSource',
      ConfigFieldKind.list,
      section: 'cfgSniffFilters',
    ),
    ConfigField(
      'skip-dst-address',
      'cfgSkipDestination',
      ConfigFieldKind.list,
      section: 'cfgSniffFilters',
    ),
  ];

  static const ntp = [
    ConfigField('enable', 'cfgEnabled', ConfigFieldKind.toggle),
    ConfigField(
      'server',
      'cfgNtpServer',
      ConfigFieldKind.text,
      hint: 'time.apple.com',
    ),
    ConfigField(
      'port',
      'cfgNtpPort',
      ConfigFieldKind.number,
      minimum: 1,
      maximum: 65535,
    ),
    ConfigField(
      'interval',
      'cfgNtpInterval',
      ConfigFieldKind.number,
      minimum: 1,
      maximum: 86400,
    ),
    ConfigField('write-to-system', 'cfgNtpWriteSystem', ConfigFieldKind.toggle),
  ];
}
