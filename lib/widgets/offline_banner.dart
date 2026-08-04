import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

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
      color: context.tintedSurface(AppTheme.accentAmber),
      padding: const EdgeInsets.symmetric(horizontal: AppTheme.s4, vertical: AppTheme.s2),
      child: Row(
        children: [
          const Icon(Icons.cloud_off, size: 16, color: AppTheme.accentAmber),
          const SizedBox(width: AppTheme.s2),
          Expanded(
            child: Text(
              widget.message,
              style: TextStyle(
                color: context.isDark ? Colors.white.withValues(alpha: 0.9) : Colors.black87,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
