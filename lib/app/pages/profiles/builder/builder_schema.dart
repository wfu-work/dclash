import 'builder_fields.dart';
import 'profile_builder_draft.dart';

List<BuilderFieldSpec> builderSchema(
  BuilderSection section,
  Map<String, dynamic> data,
) {
  final type = data['type'] is String ? data['type'] as String : '';
  const name = BuilderFieldSpec('name', 'builderName', required: true);
  const port = BuilderFieldSpec(
    'port',
    'builderPort',
    kind: BuilderFieldKind.integer,
    required: true,
    min: 1,
    max: 65535,
  );
  const password = BuilderFieldSpec(
    'password',
    'builderPassword',
    required: true,
    secret: true,
  );
  const tls = [
    BuilderFieldSpec('tls', 'builderTls', kind: BuilderFieldKind.boolean),
    BuilderFieldSpec(
      'skip-cert-verify',
      'builderSkipCertVerify',
      kind: BuilderFieldKind.boolean,
    ),
  ];
  if (section == BuilderSection.proxies) {
    if (!ProfileBuilderDraft.proxyTypes.contains(type)) return [name];
    return [
      name,
      const BuilderFieldSpec('server', 'builderServer', required: true),
      port,
      if (type == 'ss') ...[
        const BuilderFieldSpec(
          'cipher',
          'builderCipher',
          required: true,
          kind: BuilderFieldKind.choice,
          choices: [
            'aes-128-gcm',
            'aes-256-gcm',
            'chacha20-ietf-poly1305',
            'xchacha20-ietf-poly1305',
            '2022-blake3-aes-128-gcm',
            '2022-blake3-aes-256-gcm',
            '2022-blake3-chacha20-poly1305',
            'none',
          ],
        ),
        BuilderFieldSpec(
          'password',
          'builderPassword',
          required: data['cipher'] != 'none',
          secret: true,
        ),
      ],
      if (['vmess', 'vless'].contains(type)) ...[
        const BuilderFieldSpec(
          'uuid',
          'builderUuid',
          required: true,
          secret: true,
        ),
        if (type == 'vmess') ...[
          const BuilderFieldSpec(
            'alterId',
            'builderAlterId',
            kind: BuilderFieldKind.integer,
            min: 0,
            max: 65535,
          ),
          const BuilderFieldSpec(
            'cipher',
            'builderCipher',
            kind: BuilderFieldKind.choice,
            choices: [
              'auto',
              'aes-128-gcm',
              'chacha20-poly1305',
              'none',
              'zero',
            ],
          ),
        ],
        if (type == 'vless')
          const BuilderFieldSpec(
            'flow',
            'builderFlow',
            kind: BuilderFieldKind.choice,
            choices: ['xtls-rprx-vision'],
          ),
        const BuilderFieldSpec(
          'network',
          'builderTransport',
          kind: BuilderFieldKind.choice,
          choices: ['tcp', 'ws', 'grpc', 'http', 'h2'],
        ),
        const BuilderFieldSpec('servername', 'builderServerName'),
        ...tls,
        if (data['network'] == 'ws') ...[
          const BuilderFieldSpec('ws-opts.path', 'builderWsPath'),
          const BuilderFieldSpec('ws-opts.headers.Host', 'builderWsHost'),
        ],
        if (data['network'] == 'grpc')
          const BuilderFieldSpec(
            'grpc-opts.grpc-service-name',
            'builderGrpcService',
          ),
      ],
      if (['trojan', 'hysteria2'].contains(type)) ...[
        password,
        const BuilderFieldSpec('sni', 'builderServerName'),
        const BuilderFieldSpec(
          'skip-cert-verify',
          'builderSkipCertVerify',
          kind: BuilderFieldKind.boolean,
        ),
      ],
      if (type == 'hysteria2') ...[
        const BuilderFieldSpec(
          'obfs',
          'builderObfs',
          kind: BuilderFieldKind.choice,
          choices: ['salamander'],
        ),
        const BuilderFieldSpec(
          'obfs-password',
          'builderObfsPassword',
          secret: true,
        ),
      ],
      if (['socks5', 'http'].contains(type)) ...[
        const BuilderFieldSpec('username', 'builderUsername', secret: true),
        const BuilderFieldSpec('password', 'builderPassword', secret: true),
        ...tls,
        const BuilderFieldSpec('sni', 'builderServerName'),
      ],
      const BuilderFieldSpec(
        'udp',
        'builderUdp',
        kind: BuilderFieldKind.boolean,
      ),
    ];
  }
  if (section == BuilderSection.groups) {
    return [
      name,
      if (['url-test', 'fallback', 'load-balance'].contains(type)) ...[
        const BuilderFieldSpec('url', 'builderTestUrl', required: true),
        const BuilderFieldSpec(
          'interval',
          'builderInterval',
          kind: BuilderFieldKind.integer,
          min: 1,
          max: 2147483647,
        ),
        const BuilderFieldSpec(
          'lazy',
          'builderLazy',
          kind: BuilderFieldKind.boolean,
        ),
      ],
      if (type == 'url-test')
        const BuilderFieldSpec(
          'tolerance',
          'builderTolerance',
          kind: BuilderFieldKind.integer,
          min: 0,
          max: 65535,
        ),
      if (type == 'load-balance')
        const BuilderFieldSpec(
          'strategy',
          'builderStrategy',
          kind: BuilderFieldKind.choice,
          choices: ['consistent-hashing', 'round-robin', 'sticky-sessions'],
        ),
      const BuilderFieldSpec(
        'include-all-proxies',
        'builderIncludeAllProxies',
        kind: BuilderFieldKind.boolean,
      ),
      const BuilderFieldSpec(
        'include-all-providers',
        'builderIncludeAllProviders',
        kind: BuilderFieldKind.boolean,
      ),
    ];
  }
  return [
    if (type == 'http') ...[
      const BuilderFieldSpec('url', 'builderProviderUrl', required: true),
      const BuilderFieldSpec(
        'interval',
        'builderInterval',
        kind: BuilderFieldKind.integer,
        min: 1,
        max: 2147483647,
      ),
    ],
    if (type != 'inline')
      const BuilderFieldSpec(
        'path',
        'builderProviderPath',
        required: true,
        hint: './providers/example.yaml',
      ),
    if (section == BuilderSection.ruleProviders) ...[
      const BuilderFieldSpec(
        'behavior',
        'builderBehavior',
        required: true,
        kind: BuilderFieldKind.choice,
        choices: ['domain', 'ipcidr', 'classical'],
      ),
      const BuilderFieldSpec(
        'format',
        'builderFormat',
        kind: BuilderFieldKind.choice,
        choices: ['yaml', 'text', 'mrs'],
      ),
    ],
    if (section == BuilderSection.proxyProviders) ...[
      const BuilderFieldSpec(
        'health-check.enable',
        'builderHealthCheck',
        kind: BuilderFieldKind.boolean,
      ),
      const BuilderFieldSpec('health-check.url', 'builderTestUrl'),
      const BuilderFieldSpec(
        'health-check.interval',
        'builderHealthInterval',
        kind: BuilderFieldKind.integer,
        min: 1,
        max: 2147483647,
      ),
    ],
  ];
}
