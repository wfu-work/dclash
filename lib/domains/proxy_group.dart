class ProxyNode {
  const ProxyNode({
    required this.name,
    required this.type,
    this.delay,
    this.alive = true,
  });
  final String name, type;
  final int? delay;
  final bool alive;
}

class ProxyGroup {
  const ProxyGroup({
    required this.name,
    required this.type,
    required this.selected,
    required this.nodes,
  });
  final String name, type, selected;
  final List<ProxyNode> nodes;
  bool get selectable => type.toLowerCase() == 'selector';
}
