import 'package:connectivity_plus/connectivity_plus.dart';

import 'subscription_manager.dart';
import 'subscription_payment_queue.dart';

/// Per the backend scope, rides/payments/expenses are local-only — the
/// backend only tracks registration + subscription state. "Syncing" here
/// means refreshing the cached subscription status, and flushing any
/// queued subscription-payment SMS confirmations, whenever connectivity
/// returns, so the lockout/countdown stays accurate and no payment proof
/// is left stranded on-device forever.
class SyncManager {
  SyncManager({required this.subscriptionManager});

  final SubscriptionManager subscriptionManager;

  Future<bool> isOnline() async {
    final result = await Connectivity().checkConnectivity();
    return !result.contains(ConnectivityResult.none);
  }

  /// Call on app resume / connectivity-restored / pull-to-refresh.
  Future<SubscriptionSnapshot> syncWithServer(String phone) async {
    await SubscriptionPaymentQueue.instance.flush();
    return subscriptionManager.checkSubscriptionStatus(phone);
  }

  /// Listen for connectivity changes and auto-refresh subscription status.
  Stream<SubscriptionSnapshot> watch(String phone) async* {
    await for (final result in Connectivity().onConnectivityChanged) {
      if (!result.contains(ConnectivityResult.none)) {
        yield await syncWithServer(phone);
      }
    }
  }
}
