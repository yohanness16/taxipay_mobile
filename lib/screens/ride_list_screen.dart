import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/ride.dart';
import '../services/auth_service.dart';
import '../services/ride_manager.dart';
import '../theme/app_theme.dart';
import '../widgets/modern_widgets.dart';

class RideListScreen extends StatefulWidget {
  const RideListScreen({super.key, this.showAppBar = true});

  final bool showAppBar;

  @override
  State<RideListScreen> createState() => _RideListScreenState();
}

class _RideListScreenState extends State<RideListScreen> {
  List<Ride> _rides = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final rides = await context.read<RideManager>().getRideHistory();
    if (!mounted) return;
    setState(() {
      _rides = rides;
      _loading = false;
    });
  }

  Future<void> _createRide() async {
    final distanceCtrl = TextEditingController();
    final notesCtrl = TextEditingController();

    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          left: 20, right: 20, top: 20,
          bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2))),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                const IconBadge(icon: Icons.add_road_rounded, color: Colors.blue),
                const SizedBox(width: 12),
                Text('New ride', style: Theme.of(ctx).textTheme.titleLarge),
              ],
            ),
            const SizedBox(height: 20),
            TextField(
              controller: distanceCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Estimated distance (km)', prefixIcon: Icon(Icons.route)),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: notesCtrl,
              decoration: const InputDecoration(labelText: 'Notes (optional)', prefixIcon: Icon(Icons.notes)),
              maxLines: 2,
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(ctx, false),
                    child: const Text('Cancel'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: () => Navigator.pop(ctx, true),
                    child: const Text('Save ride'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );

    if (saved != true) return;

    final phone = await context.read<AuthService>().phone;
    final ride = Ride(
      driverPhone: phone ?? '',
      startTime: DateTime.now(),
      distanceKm: double.tryParse(distanceCtrl.text) ?? 0,
      notes: notesCtrl.text.trim().isEmpty ? null : notesCtrl.text.trim(),
    );
    await context.read<RideManager>().createRide(ride);
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: widget.showAppBar ? AppBar(title: const Text('Rides')) : null,
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'ride_fab',
        onPressed: _createRide,
        icon: const Icon(Icons.add),
        label: const Text('New ride'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _rides.isEmpty
              ? const EmptyState(
                  icon: Icons.local_taxi_outlined,
                  title: 'No rides yet',
                  subtitle: 'Tap "New ride" to start tracking one.',
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: _rides.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, i) {
                      final ride = _rides[i];
                      final active = ride.endTime == null;
                      return FadeSlideIn(
                        index: i,
                        child: Card(
                          child: ListTile(
                            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                            leading: IconBadge(
                              icon: Icons.local_taxi_rounded,
                              color: active ? AppTheme.primaryDark : Colors.blueGrey,
                            ),
                            title: Text(
                              DateFormat.yMMMd().add_jm().format(ride.startTime),
                              style: const TextStyle(fontWeight: FontWeight.w600),
                            ),
                            subtitle: Text(
                              ride.notes ?? (ride.distanceKm > 0 ? '${ride.distanceKm.toStringAsFixed(1)} km' : 'No notes'),
                            ),
                            trailing: active
                                ? _LiveBadge(
                                    onEnd: () async {
                                      await context.read<RideManager>().endRide(ride.id!);
                                      await _load();
                                    },
                                  )
                                : const Icon(Icons.check_circle, color: AppTheme.primaryDark),
                          ),
                        ),
                      );
                    },
                  ),
                ),
    );
  }
}

/// A small pulsing "live" dot + End button for the currently in-progress
/// ride, so it's visually obvious at a glance which row (if any) is active.
class _LiveBadge extends StatefulWidget {
  const _LiveBadge({required this.onEnd});
  final VoidCallback onEnd;

  @override
  State<_LiveBadge> createState() => _LiveBadgeState();
}

class _LiveBadgeState extends State<_LiveBadge> with SingleTickerProviderStateMixin {
  late final AnimationController _controller =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 900))..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        FadeTransition(
          opacity: Tween(begin: 0.3, end: 1.0).animate(_controller),
          child: const Icon(Icons.circle, color: Colors.redAccent, size: 10),
        ),
        const SizedBox(width: 6),
        TextButton(onPressed: widget.onEnd, child: const Text('End ride')),
      ],
    );
  }
}
