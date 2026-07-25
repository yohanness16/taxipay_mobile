import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';

/// Thin banner shown at the top of a screen whenever the device has no
/// network connection. The rest of the app (rides, payments, expenses,
/// cached subscription status) all keep working underneath it — this is
/// purely a reassurance/status indicator, not a blocker.
class OfflineBanner extends StatefulWidget {
  const OfflineBanner({super.key, required this.message});
  final String message;

  @override
  State<OfflineBanner> createState() => _OfflineBannerState();
}

class _OfflineBannerState extends State<OfflineBanner> {
  bool _offline = false;

  @override
  void initState() {
    super.initState();
    _check();
    Connectivity().onConnectivityChanged.listen((result) {
      if (!mounted) return;
      setState(() => _offline = result.contains(ConnectivityResult.none));
    });
  }

  Future<void> _check() async {
    final result = await Connectivity().checkConnectivity();
    if (!mounted) return;
    setState(() => _offline = result.contains(ConnectivityResult.none));
  }

  @override
  Widget build(BuildContext context) {
    if (!_offline) return const SizedBox.shrink();
    return Container(
      width: double.infinity,
      color: Colors.orange.shade100,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Icon(Icons.cloud_off, size: 16, color: Colors.orange.shade800),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              widget.message,
              style: TextStyle(color: Colors.orange.shade900, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}
