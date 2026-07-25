import 'package:flutter/foundation.dart';

import '../services/driver_settings_service.dart';

/// Deliberately lightweight -- a plain string-key lookup covering the main
/// screens rather than full Flutter l10n/ARB tooling. Fully wired through:
/// Dashboard, Settings, Onboarding, Subscription/Payment screen, and common
/// dialog actions. Ride list / Expense / Reports / Payment history /
/// Registration screens still have some English-only strings -- add more
/// keys here and swap the matching hardcoded Text() calls for strings.t()
/// the same way, screen by screen.
class AppStrings extends ChangeNotifier {
  AppStrings({required this.settings}) {
    _load();
  }

  final DriverSettingsService settings;
  String _languageCode = 'en';

  String get languageCode => _languageCode;

  Future<void> _load() async {
    _languageCode = await settings.getLanguageCode();
    notifyListeners();
  }

  Future<void> setLanguage(String code) async {
    _languageCode = code;
    await settings.setLanguageCode(code);
    notifyListeners();
  }

  String t(String key) => _strings[key]?[_languageCode] ?? _strings[key]?['en'] ?? key;

  static final Map<String, Map<String, String>> _strings = {
    // --- Dashboard ---
    'greeting_morning': {'en': 'Good morning', 'am': 'እንደምን አደሩ'},
    'greeting_afternoon': {'en': 'Good afternoon', 'am': 'እንደምን ዋሉ'},
    'greeting_evening': {'en': 'Good evening', 'am': 'እንደምን አመሹ'},
    'todays_earnings': {'en': "Today's earnings", 'am': 'የዛሬ ገቢ'},
    'net_profit': {'en': 'Net profit today', 'am': 'የዛሬ ተጣራ ትርፍ'},
    'rides': {'en': 'Rides', 'am': 'ጉዞዎች'},
    'expenses': {'en': 'Expenses', 'am': 'ወጪዎች'},
    'expenses_today': {'en': 'Expenses today', 'am': 'የዛሬ ወጪ'},
    'daily_goal': {'en': 'Daily goal', 'am': 'የቀን ግብ'},
    'quick_actions': {'en': 'Quick actions', 'am': 'ፈጣን ተግባራት'},
    'new_ride': {'en': 'New ride', 'am': 'አዲስ ጉዞ'},
    'add_expense': {'en': 'Add expense', 'am': 'ወጪ ጨምር'},
    'payment_history': {'en': 'Payment history', 'am': 'የክፍያ ታሪክ'},
    'reports': {'en': 'Reports', 'am': 'ሪፖርቶች'},
    'recent_payments': {'en': 'Recent payments', 'am': 'የቅርብ ጊዜ ክፍያዎች'},
    'view_all': {'en': 'View all', 'am': 'ሁሉንም ይመልከቱ'},
    'offline_mode': {'en': "You're offline — data will sync when connected", 'am': 'ከመስመር ውጭ ነዎት — ሲገናኙ ይዘምናል'},
    'service_due': {'en': 'Vehicle service may be due', 'am': 'የተሽከርካሪ አገልግሎት ጊዜው ደርሷል ሊሆን ይችላል'},
    'settings': {'en': 'Settings', 'am': 'ቅንብሮች'},
    'log_out': {'en': 'Log out', 'am': 'ውጣ'},
    'language': {'en': 'Language', 'am': 'ቋንቋ'},
    'export_backup': {'en': 'Export / backup data', 'am': 'ውሂብ ላክ / ምትኬ'},
    'scan_inbox': {'en': 'Scan inbox now', 'am': 'የመልእክት ሳጥን አሁን ቃኝ'},
    'dashboard': {'en': 'Dashboard', 'am': 'ዳሽቦርድ'},
    'menu': {'en': 'Menu', 'am': 'ምናሌ'},

    // --- Cash fare quick-log ---
    'log_cash_fare': {'en': 'Log cash fare', 'am': 'ጥሬ ገንዘብ ክፍያ መዝግብ'},
    'cash_fare_logged': {'en': 'Cash fare added to today\'s earnings', 'am': 'ጥሬ ገንዘብ ክፍያ ወደ ዛሬ ገቢ ታክሏል'},
    'cash': {'en': 'Cash', 'am': 'ጥሬ ገንዘብ'},
    'telebirr': {'en': 'Telebirr', 'am': 'ቴሌብር'},
    'amount': {'en': 'Amount', 'am': 'መጠን'},
    'note_optional': {'en': 'Note (optional)', 'am': 'ማስታወሻ (አማራጭ)'},

    // --- Common actions ---
    'cancel': {'en': 'Cancel', 'am': 'ይቅር'},
    'save': {'en': 'Save', 'am': 'አስቀምጥ'},
    'continue_label': {'en': 'Continue', 'am': 'ቀጥል'},
    'skip_for_now': {'en': 'Skip for now', 'am': 'አሁን ለፍ'},
    'next': {'en': 'Next', 'am': 'ቀጣይ'},
    'allow_and_continue': {'en': 'Allow & continue', 'am': 'ፍቀድ እና ቀጥል'},
    'retry': {'en': 'Retry', 'am': 'እንደገና ሞክር'},

    // --- Onboarding ---
    'onboarding_sms_title': {'en': 'Read payment SMS', 'am': 'የክፍያ መልእክት አንብብ'},
    'onboarding_sms_body': {
      'en': 'Captures every Telebirr payment (127) the instant it arrives.',
      'am': 'ከ127 የሚደርሱ የቴሌብር ክፍያዎችን ወዲያውኑ ይመዘግባል።',
    },
    'onboarding_notif_title': {'en': 'Payment sound alerts', 'am': 'የክፍያ ድምጽ ማንቂያዎች'},
    'onboarding_notif_body': {
      'en': 'A sound and alert fire the moment a payment lands, screen on or off.',
      'am': 'ክፍያ እንደደረሰ ወዲያውኑ ድምጽና ማሳወቂያ ይሰማል፣ ስክሪን ቢጠፋም እንኳ።',
    },
    'onboarding_overlay_title': {'en': 'Floating payment bubble', 'am': 'ተንሳፋፊ የክፍያ አረፋ'},
    'onboarding_overlay_body': {
      'en': 'Shows live earnings over any app. Switch it on in the next screen, then come back here.',
      'am': 'በማንኛውም መተግበሪያ ላይ ገቢዎን ያሳያል። በሚቀጥለው ገጽ ላይ ያብሩና ወደዚህ ይመለሱ።',
    },

    // --- Subscription / payment screen ---
    'subscription_expired_with_date': {'en': 'Your subscription expired on', 'am': 'የደንበኝነት ምዝገባዎ ያለቀው በ'},
    'trial_ended': {'en': 'Your free trial has ended.', 'am': 'ነጻ የሙከራ ጊዜዎ አልቋል።'},
    'pay_to_unlock': {'en': 'Pay to unlock ride tracking, payments, and expenses for another 30 days.', 'am': 'ለሌላ 30 ቀናት የጉዞ ክትትል፣ ክፍያዎች እና ወጪዎችን ለመክፈት ይክፈሉ።'},
    'send_payment_telebirr': {'en': 'Send payment via Telebirr', 'am': 'በቴሌብር ክፍያ ይላኩ'},
    'send_to': {'en': 'Send to', 'am': 'ላክ ወደ'},
    'confirm_sent': {'en': "Confirm you've sent it", 'am': 'መላካቸውን ያረጋግጡ'},
    'ive_sent_payment': {'en': "I've sent the payment", 'am': 'ክፍያውን ልኬያለሁ'},
    'watching_for_sms': {'en': 'Watching for payment SMS…', 'am': 'የክፍያ መልእክት በመጠበቅ ላይ…'},
    'paste_sms_manually': {'en': 'Or paste the SMS manually', 'am': 'ወይም መልእክቱን በእጅ ይለጥፉ'},
    'submit_for_verification': {'en': 'Submit for verification', 'am': 'ለማረጋገጫ ላክ'},
    'payments_pending': {'en': 'payment(s) pending verification', 'am': 'ክፍያ(ዎች) ማረጋገጫ በመጠበቅ ላይ'},

    // --- Ride / expense / reports (partial coverage) ---
    'start_ride': {'en': 'Start ride', 'am': 'ጉዞ ጀምር'},
    'end_ride': {'en': 'End ride', 'am': 'ጉዞ አጠናቅቅ'},
    'delete': {'en': 'Delete', 'am': 'ሰርዝ'},
    'edit': {'en': 'Edit', 'am': 'አርም'},
  };
}
