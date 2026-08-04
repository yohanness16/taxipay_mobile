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
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppTheme.rXl)),
      ),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          left: AppTheme.s5,
          right: AppTheme.s5,
          top: AppTheme.s3,
          bottom: MediaQuery.of(ctx).viewInsets.bottom + AppTheme.s5,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 44,
                height: 4,
                decoration: BoxDecoration(
                  color: ctx.faintText.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(AppTheme.s1),
                ),
              ),
            ),
            const SizedBox(height: AppTheme.s5),
            Row(
              children: [
                const IconBadge(icon: Icons.add_road_rounded, color: AppTheme.info),
                const SizedBox(width: AppTheme.s3),
                Text('New ride', style: Theme.of(ctx).textTheme.titleLarge),
              ],
            ),
            const SizedBox(height: AppTheme.s5),
            TextField(
              controller: distanceCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'Estimated distance (km)',
                prefixIcon: Icon(Icons.route),
              ),
            ),
            const SizedBox(height: AppTheme.s3),
            TextField(
              controller: notesCtrl,
              decoration: const InputDecoration(labelText: 'Notes (optional)', prefixIcon: Icon(Icons.notes)),
              maxLines: 2,
            ),
            const SizedBox(height: AppTheme.s5),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(ctx, false),
                    child: const Text('Cancel'),
                  ),
                ),
                const SizedBox(width: AppTheme.s3),
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
    if (!mounted) return;

    final phone = await context.read<AuthService>().phone;
    if (!mounted) return;

    final ride = Ride(
      driverPhone: phone ?? '',
      startTime: DateTime.now(),
      distanceKm: double.tryParse(distanceCtrl.text) ?? 0,
      notes: notesCtrl.text.trim().isEmpty ? null : notesCtrl.text.trim(),
    );
    await context.read<RideManager>().createRide(ride);
    await _load();
  }

  /// Flattens the rides into a render list where a day header is emitted
  /// whenever the calendar day changes. Purely presentational -- the order
  /// the manager returned is preserved exactly.
  List<Object> _sectioned() {
    final items = <Object>[];
    DateTime? currentDay;
    for (final r in _rides) {
      final day = DateTime(r.startTime.year, r.startTime.month, r.startTime.day);
      if (currentDay == null || day != currentDay) {
        currentDay = day;
        items.add(day);
      }
      items.add(r);
    }
    return items;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: widget.showAppBar ? AppBar(title: const Text('Rides')) : null,
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'ride_fab',
        onPressed: _createRide,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppTheme.rMd)),
        icon: const Icon(Icons.add),
        label: const Text('New ride'),
      ),
      body: _loading
          ? const _RideListSkeleton()
          : _rides.isEmpty
              ? const EmptyState(
                  icon: Icons.local_taxi_outlined,
                  title: 'No rides yet',
                  subtitle: 'Tap "New ride" to start tracking one.',
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  child: Builder(
                    builder: (context) {
                      final items = _sectioned();
                      return ListView.builder(
                        padding:
                            const EdgeInsets.fromLTRB(AppTheme.s4, AppTheme.s2, AppTheme.s4, AppTheme.s8 * 3),
                        itemCount: items.length,
                        itemBuilder: (context, i) {
                          final item = items[i];
                          if (item is DateTime) {
                            return FadeSlideIn(
                              index: i,
                              child: Padding(
                                padding: EdgeInsets.only(
                                  top: i == 0 ? 0 : AppTheme.s4,
                                  bottom: AppTheme.s1,
                                ),
                                child: SectionHeader(title: DateFormat.yMMMEd().format(item)),
                              ),
                            );
                          }
                          final ride = item as Ride;
                          return FadeSlideIn(
                            index: i,
                            child: Padding(
                              padding: const EdgeInsets.only(bottom: AppTheme.s2),
                              child: _RideRow(
                                ride: ride,
                                active: ride.endTime == null,
                                onEnd: () async {
                                  await context.read<RideManager>().endRide(ride.id!);
                                  await _load();
                                },
                              ),
                            ),
                          );
                        },
                      );
                    },
                  ),
                ),
    );
  }
}

/// One ride in the history list. The in-progress ride gets a tinted card so
/// it separates itself from the settled rows without needing a label.
class _RideRow extends StatelessWidget {
  const _RideRow({required this.ride, required this.active, required this.onEnd});

  final Ride ride;
  final bool active;
  final Future<void> Function() onEnd;

  @override
  Widget build(BuildContext context) {
    final brand = context.isDark ? AppTheme.primary : AppTheme.primaryDark;

    return SoftCard(
      accent: active ? brand : null,
      padding: const EdgeInsets.fromLTRB(AppTheme.s3, AppTheme.s3, AppTheme.s3, AppTheme.s3),
      child: Row(
        children: [
          IconBadge(
            icon: Icons.local_taxi_rounded,
            color: active ? brand : context.subtleText,
            size: 42,
          ),
          const SizedBox(width: AppTheme.s3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  DateFormat.yMMMd().add_jm().format(ride.startTime),
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5, letterSpacing: -0.2),
                ),
                const SizedBox(height: 3),
                Text(
                  ride.notes ?? (ride.distanceKm > 0 ? '${ride.distanceKm.toStringAsFixed(1)} km' : 'No notes'),
                  style: TextStyle(color: context.subtleText, fontSize: 12.5, height: 1.3),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppTheme.s2),
          if (active)
            _LiveBadge(onEnd: onEnd)
          else
            Padding(
              padding: const EdgeInsets.only(right: AppTheme.s1),
              child: Icon(Icons.check_circle_rounded, color: brand.withValues(alpha: 0.85), size: 22),
            ),
        ],
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
        Container(
          width: 20,
          height: 20,
          decoration: BoxDecoration(
            color: context.tintedSurface(AppTheme.danger),
            shape: BoxShape.circle,
          ),
          alignment: Alignment.center,
          child: FadeTransition(
            opacity: Tween(begin: 0.3, end: 1.0).animate(_controller),
            child: const Icon(Icons.circle, color: AppTheme.danger, size: 9),
          ),
        ),
        const SizedBox(width: AppTheme.s1),
        TextButton(
          onPressed: widget.onEnd,
          style: TextButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: AppTheme.s2, vertical: AppTheme.s1),
            minimumSize: const Size(0, 34),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppTheme.rSm)),
          ),
          child: const Text('End ride'),
        ),
      ],
    );
  }
}

/// Placeholder rows shown while history loads -- keeps the list's rhythm on
/// screen instead of collapsing to a lone centred spinner.
class _RideListSkeleton extends StatelessWidget {
  const _RideListSkeleton();

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(AppTheme.s4, AppTheme.s4, AppTheme.s4, AppTheme.s8 * 3),
      itemCount: 6,
      physics: const NeverScrollableScrollPhysics(),
      separatorBuilder: (_, __) => const SizedBox(height: AppTheme.s2),
      itemBuilder: (context, i) => FadeSlideIn(
        index: i,
        child: SoftCard(
          padding: const EdgeInsets.all(AppTheme.s3),
          child: Row(
            children: [
              const SkeletonBox(height: 42, width: 42, radius: 21),
              const SizedBox(width: AppTheme.s3),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: const [
                    SkeletonBox(height: 12, width: 150, radius: AppTheme.s1),
                    SizedBox(height: AppTheme.s2),
                    SkeletonBox(height: 10, width: 90, radius: AppTheme.s1),
                  ],
                ),
              ),
              const SizedBox(width: AppTheme.s2),
              const SkeletonBox(height: 22, width: 22, radius: 11),
            ],
          ),
        ),
      ),
    );
  }
}
