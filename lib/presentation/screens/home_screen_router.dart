import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:receiptnest/presentation/providers/providers.dart';
import 'package:receiptnest/presentation/screens/premium_receipt_home_screen.dart';
import 'package:receiptnest/presentation/screens/receipt_list_screen.dart';

class HomeScreenRouter extends ConsumerWidget {
  const HomeScreenRouter({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final uid = ref.watch(currentUidProvider);
    if (uid == null) {
      return const ReceiptListScreen();
    }

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .snapshots(),
      builder: (
        BuildContext context,
        AsyncSnapshot<DocumentSnapshot<Map<String, dynamic>>> snapshot,
      ) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError || !snapshot.hasData || !snapshot.data!.exists) {
          return const ReceiptListScreen();
        }

        final data = snapshot.data?.data();
        final accountStatus = (data?['accountStatus'] as String?)?.toLowerCase();
        final subscriptionStatus =
            (data?['subscriptionStatus'] as String?)?.toLowerCase();
        final isPremium =
            accountStatus == 'trial' || subscriptionStatus == 'active';

        return isPremium
            ? const PremiumReceiptHomeScreen()
            : const ReceiptListScreen();
      },
    );
  }
}

