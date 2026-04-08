import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:receiptnest/core/theme/app_colors.dart';
import 'package:receiptnest/domain/entities/trip.dart';
import 'package:receiptnest/presentation/providers/providers.dart';
import 'package:receiptnest/presentation/screens/create_trip_screen.dart';
import 'package:receiptnest/presentation/screens/trip_detail_screen.dart';

class TripsListScreen extends ConsumerWidget {
  const TripsListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tripsAsync = ref.watch(tripsStreamProvider);
    final hasAccess = ref.watch(premiumTripAccessProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Trips',
          style: TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.w700,
            color: AppColors.primaryNavy,
          ),
        ),
      ),
      body: SafeArea(
        child: !hasAccess
            ? const _TripsLockedView()
            : tripsAsync.when(
                data: (trips) {
                  if (trips.isEmpty) {
                    return _TripsEmptyState(
                      onCreate: () => _openCreateTrip(context),
                    );
                  }

                  return RefreshIndicator(
                    onRefresh: () async {
                      ref.refresh(tripsStreamProvider);
                      await ref.read(tripsStreamProvider.future);
                    },
                    child: ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
                      itemCount: trips.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 12),
                      itemBuilder: (context, index) {
                        final trip = trips[index];
                        return _TripCard(
                          trip: trip,
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute<void>(
                                builder: (_) =>
                                    TripDetailScreen(tripId: trip.id),
                              ),
                            );
                          },
                        );
                      },
                    ),
                  );
                },
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (error, _) =>
                    Center(child: Text('Failed to load trips: $error')),
              ),
      ),
      floatingActionButton: hasAccess
          ? FloatingActionButton.extended(
              onPressed: () => _openCreateTrip(context),
              icon: const Icon(Icons.add),
              label: const Text('Create Trip'),
            )
          : null,
    );
  }

  void _openCreateTrip(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => const CreateTripScreen(),
      ),
    );
  }
}

class _TripCard extends StatelessWidget {
  const _TripCard({
    required this.trip,
    required this.onTap,
  });

  final Trip trip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final dateRange = _formatTripDateRange(trip);

    return Card(
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 12,
        ),
        onTap: onTap,
        title: Text(
          trip.name,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 4),
            Text(
              trip.type == TripType.work ? 'Work' : 'Personal',
              style: const TextStyle(color: AppColors.textSecondary),
            ),
            if (dateRange != null) ...[
              const SizedBox(height: 4),
              Text(
                dateRange,
                style: const TextStyle(color: AppColors.textSecondary),
              ),
            ],
          ],
        ),
        trailing: const Icon(Icons.chevron_right),
      ),
    );
  }
}

class _TripsEmptyState extends StatelessWidget {
  const _TripsEmptyState({required this.onCreate});

  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'No trips yet',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w700,
                color: AppColors.primaryNavy,
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'Create your first trip to organise related receipts in one place.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 15,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: onCreate,
              icon: const Icon(Icons.add),
              label: const Text('Create Trip'),
            ),
          ],
        ),
      ),
    );
  }
}

class _TripsLockedView extends StatelessWidget {
  const _TripsLockedView();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(24),
        child: Card(
          child: Padding(
            padding: EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.workspace_premium_outlined,
                  size: 36,
                  color: AppColors.primaryNavy,
                ),
                SizedBox(height: 12),
                Text(
                  'Trips are available on an active trial or subscription.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: AppColors.primaryNavy,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

String? _formatTripDateRange(Trip trip) {
  if (trip.startDate == null && trip.endDate == null) {
    return null;
  }

  final formatter = DateFormat.yMMMd();
  final startText =
      trip.startDate == null ? 'Any start' : formatter.format(trip.startDate!);
  final endText =
      trip.endDate == null ? 'Any end' : formatter.format(trip.endDate!);
  return '$startText - $endText';
}
