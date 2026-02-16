import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../providers/sync_provider.dart';

class ConnectionIndicator extends StatelessWidget {
  const ConnectionIndicator({super.key});

  @override
  Widget build(BuildContext context) {
    final sync = context.watch<SyncProvider>();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Tooltip(
        message: sync.isOnline ? 'Conectado' : 'Sin conexión',
        child: Icon(
          sync.isOnline ? Icons.wifi : Icons.wifi_off,
          color: sync.isOnline ? Colors.greenAccent : Colors.orangeAccent,
          size: 20,
        ),
      ),
    );
  }
}
