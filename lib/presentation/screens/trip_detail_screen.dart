import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:receiptnest/core/theme/app_colors.dart';
import 'package:receiptnest/domain/entities/trip.dart';
import 'package:receiptnest/presentation/providers/providers.dart';
import 'package:receiptnest/presentation/screens/create_trip_screen.dart';
import 'package:receiptnest/presentation/widgets/receipt_list.dart';

class TripDetailScreen extends ConsumerWidget {
  const TripDetailScreen({
    super.key,
    required this.tripId,
  });

  final String tripId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hasAccess = ref.watch(premiumTripAccessProvider);
    final tripAsync = ref.watch(tripStreamProvider(tripId));
    final receiptsAsync = ref.watch(tripReceiptsStreamProvider(tripId));

    return Scaffold(
      appBar: AppBar(
        title: tripAsync.maybeWhen(
          data: (trip) => Text(
            trip?.name ?? 'Trip',
            style: const TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w700,
              color: AppColors.primaryNavy,
            ),
          ),
          orElse: () => const Text(
            'Trip',
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w700,
              color: AppColors.primaryNavy,
            ),
          ),
        ),
        actions: [
          tripAsync.maybeWhen(
            data: (trip) {
              if (trip == null || !hasAccess) {
                return const SizedBox.shrink();
              }

              return IconButton(
                icon: const Icon(Icons.edit_outlined),
                tooltip: 'Edit trip',
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute<void>(
                      builder: (_) => CreateTripScreen(trip: trip),
                    ),
                  );
                },
              );
            },
            orElse: () => const SizedBox.shrink(),
          ),
        ],
      ),
      body: SafeArea(
        child: !hasAccess
            ? const _TripAccessDenied()
            : tripAsync.when(
                data: (trip) {
                  if (trip == null) {
                    return const Center(
                      child: Text('Trip not found.'),
                    );
                  }

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _TripSummaryCard(trip: trip),
                      const Padding(
                        padding: EdgeInsets.fromLTRB(16, 8, 16, 8),
                        child: Text(
                          'Receipts',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                            color: AppColors.primaryNavy,
                          ),
                        ),
                      ),
                      Expanded(
                        child: receiptsAsync.when(
                          data: (receipts) {
                            if (receipts.isEmpty) {
                              return const Center(
                                child: Text('No receipts in this trip yet'),
                              );
                            }

                            return ReceiptList(receipts: receipts);
                          },
                          loading: () =>
                              const Center(child: CircularProgressIndicator()),
                          error: (error, _) => Center(
                            child: Text(
                              'Failed to load receipts: $error',
                            ),
                          ),
                        ),
                      ),
                    ],
                  );
                },
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (error, _) => Center(
                  child: Text('Failed to load trip: $error'),
                ),
              ),
      ),
    );
  }
}

class _TripSummaryCard extends StatelessWidget {
  const _TripSummaryCard({required this.trip});

  final Trip trip;

  @override
  Widget build(BuildContext context) {
    final dateRange = _formatTripDateRange(trip);
    final updatedAt = DateFormat.yMMMd().format(trip.updatedAt);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                trip.type == TripType.work ? 'Work' : 'Personal',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textSecondary,
                ),
              ),
              if (dateRange != null) ...[
                const SizedBox(height: 8),
                Text(
                  dateRange,
                  style: const TextStyle(
                    fontSize: 15,
                    color: AppColors.textPrimary,
                  ),
                ),
              ],
              if (trip.notes != null && trip.notes!.trim().isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(
                  trip.notes!,
                  style: const TextStyle(
                    fontSize: 15,
                    color: AppColors.textPrimary,
                  ),
                ),
              ],
              const SizedBox(height: 12),
              Text(
                'Updated $updatedAt',
                style: const TextStyle(
                  fontSize: 13,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TripAccessDenied extends StatelessWidget {
  const _TripAccessDenied();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(24),
        child: Text(
          'Trips are available on an active trial or subscription.',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: AppColors.primaryNavy,
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
