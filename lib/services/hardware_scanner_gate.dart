/// Bloquea temporalmente el escáner de hardware (pistola BT/USB) en ciertos
/// estados de UI, alineado con la web.
class HardwareScannerGate {
  HardwareScannerGate._();

  static final HardwareScannerGate instance = HardwareScannerGate._();

  final Set<String> _blockedReasons = {};

  bool get isEnabled => _blockedReasons.isEmpty;

  void block(String reason) => _blockedReasons.add(reason);

  void unblock(String reason) => _blockedReasons.remove(reason);
}
