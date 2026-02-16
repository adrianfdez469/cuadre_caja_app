import 'package:flutter/foundation.dart';
import '../services/sync_service.dart';

class SyncProvider extends ChangeNotifier {
  final SyncService _syncService;

  ConnectionStatus _connectionStatus = ConnectionStatus.offline;
  String _lastMessage = '';
  int _pendingVentas = 0;
  bool _isSyncing = false;

  SyncProvider(this._syncService) {
    _syncService.onConnectionChanged = (status) {
      _connectionStatus = status;
      notifyListeners();
    };

    _syncService.onSyncEvent = (message) {
      _lastMessage = message;
      notifyListeners();
      _refreshPendingCount();
    };
  }

  ConnectionStatus get connectionStatus => _connectionStatus;
  bool get isOnline => _connectionStatus == ConnectionStatus.online;
  String get lastMessage => _lastMessage;
  int get pendingVentas => _pendingVentas;
  bool get isSyncing => _isSyncing;

  Future<void> startMonitoring() => _syncService.startMonitoring();
  void stopMonitoring() => _syncService.stopMonitoring();

  Future<void> fullSync(String tiendaId) async {
    _isSyncing = true;
    notifyListeners();

    await _syncService.fullSync(tiendaId);
    await _refreshPendingCount();

    _isSyncing = false;
    notifyListeners();
  }

  Future<void> _refreshPendingCount() async {
    _pendingVentas = await _syncService.getPendingCount();
    notifyListeners();
  }
}
