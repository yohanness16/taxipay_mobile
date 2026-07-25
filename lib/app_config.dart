/// Central place to configure the backend URL once you deploy to Vercel.
class AppConfig {
  /// Replace with your deployed Vercel URL, e.g.
  /// "https://telebirr-driver-backend.vercel.app/api"
  static const String backendBaseUrl = String.fromEnvironment(
    'BACKEND_URL',
    defaultValue: 'https://taxipay-eight.vercel.app/api',
  );

  static const double monthlySubscriptionFeeEtb = 100.0;
  static const int subscriptionDurationDays = 30;
  static const int trialDays = 7;

  /// How many days before actual expiry to start showing a non-blocking
  /// "renew soon" warning. There is deliberately NO grace period after
  /// expiry -- the app locks the instant `expires` passes.
  static const int expiryWarningDays = 5;

  /// TODO: replace with the real Telebirr account drivers should pay their
  /// subscription fee to. Shown as-is on the payment screen.
  static const String businessTelebirrPhone = '+251900000000';
  static const String businessTelebirrName = 'Telebirr Driver Assistant';
}
