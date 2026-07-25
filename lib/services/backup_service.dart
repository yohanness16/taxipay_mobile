import 'dart:io';

import 'package:csv/csv.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'package:telebirr_driver_assistant/models/expense.dart';

import 'expense_tracker.dart';
import 'ride_manager.dart';

/// Exports local rides/payments/expenses to CSV and hands them to the
/// system share sheet — useful for drivers who want to back up their data,
/// send a summary to an accountant/family member, or keep records for a
/// loan/visa application. Everything here reads from the same local SQLite
/// database the rest of the app uses; nothing is uploaded anywhere.
class BackupService {
  BackupService({required this.rideManager, required this.expenseTracker});

  final RideManager rideManager;
  final ExpenseTracker expenseTracker;

  Future<File> _writeCsv(String filename, List<List<dynamic>> rows) async {
    final csv = const ListToCsvConverter().convert(rows);
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/$filename');
    return file.writeAsString(csv);
  }

  /// Exports payments in the given range (defaults to all-time) and opens
  /// the share sheet so the driver can save/send it wherever they like.
  Future<void> exportPaymentsCsv({DateTime? from, DateTime? to}) async {
    final payments = await rideManager.getAllPayments(from: from, to: to);
    final rows = <List<dynamic>>[
      ['Date', 'Time', 'Amount (ETB)', 'Payer phone', 'Ride ID'],
      for (final p in payments)
        [
          '${p.receivedAt.year}-${p.receivedAt.month.toString().padLeft(2, '0')}-${p.receivedAt.day.toString().padLeft(2, '0')}',
          '${p.receivedAt.hour.toString().padLeft(2, '0')}:${p.receivedAt.minute.toString().padLeft(2, '0')}',
          p.amount,
          p.payerPhone,
          p.rideId ?? '',
        ],
    ];
    final file = await _writeCsv('telebirr_payments.csv', rows);
    await SharePlus.instance.share(ShareParams(files: [XFile(file.path)], text: 'Telebirr payment history export'));
  }

  Future<void> exportExpensesCsv({DateTime? from, DateTime? to}) async {
    final expenses = await expenseTracker.getExpenses(from: from, to: to);
    final rows = <List<dynamic>>[
      ['Date', 'Category', 'Amount (ETB)', 'Description'],
      for (final e in expenses)
        [
          '${e.expenseDate.year}-${e.expenseDate.month.toString().padLeft(2, '0')}-${e.expenseDate.day.toString().padLeft(2, '0')}',
          e.category.label,
          e.amount,
          e.description ?? '',
        ],
    ];
    final file = await _writeCsv('telebirr_expenses.csv', rows);
    await SharePlus.instance.share(ShareParams(files: [XFile(file.path)], text: 'Telebirr expense export'));
  }

  /// Exports both payments and expenses as two separate CSVs in one share
  /// action — the common "back everything up" case.
  Future<void> exportAll({DateTime? from, DateTime? to}) async {
    final payments = await rideManager.getAllPayments(from: from, to: to);
    final expenses = await expenseTracker.getExpenses(from: from, to: to);

    final paymentRows = <List<dynamic>>[
      ['Date', 'Time', 'Amount (ETB)', 'Payer phone', 'Ride ID'],
      for (final p in payments)
        [
          '${p.receivedAt.year}-${p.receivedAt.month.toString().padLeft(2, '0')}-${p.receivedAt.day.toString().padLeft(2, '0')}',
          '${p.receivedAt.hour.toString().padLeft(2, '0')}:${p.receivedAt.minute.toString().padLeft(2, '0')}',
          p.amount,
          p.payerPhone,
          p.rideId ?? '',
        ],
    ];
    final expenseRows = <List<dynamic>>[
      ['Date', 'Category', 'Amount (ETB)', 'Description'],
      for (final e in expenses)
        [
          '${e.expenseDate.year}-${e.expenseDate.month.toString().padLeft(2, '0')}-${e.expenseDate.day.toString().padLeft(2, '0')}',
          e.category.label,
          e.amount,
          e.description ?? '',
        ],
    ];

    final paymentsFile = await _writeCsv('telebirr_payments.csv', paymentRows);
    final expensesFile = await _writeCsv('telebirr_expenses.csv', expenseRows);

    await SharePlus.instance.share(ShareParams(
      files: [XFile(paymentsFile.path), XFile(expensesFile.path)],
      text: 'Telebirr Driver Assistant — full data export',
    ));
  }
}
