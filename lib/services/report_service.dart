import 'dart:io';

import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';

import '../models/expense.dart';
import '../models/payment.dart';
import 'expense_tracker.dart';
import 'ride_manager.dart';

const _brandGreen = PdfColor.fromInt(0xFF00A651);

/// Builds a clean, printable earnings summary PDF -- the thing a driver
/// can hand to a vehicle owner, an accountant, or keep for a loan/visa
/// application, without needing to explain a spreadsheet. Everything here
/// reads from the same local SQLite data the rest of the app uses.
class ReportService {
  ReportService({required this.rideManager, required this.expenseTracker});

  final RideManager rideManager;
  final ExpenseTracker expenseTracker;

  Future<File> generateEarningsReport({
    required String driverName,
    required String driverPhone,
    required DateTime from,
    required DateTime to,
  }) async {
    final payments = await rideManager.getAllPayments(from: from, to: to);
    final expensesByCategory = await expenseTracker.getTotalsByCategory(from, to);
    final totalExpenses = await expenseTracker.getTotalExpenses(from, to);

    final telebirrTotal = payments
        .where((p) => p.method == PaymentMethod.telebirr)
        .fold<double>(0, (sum, p) => sum + p.amount);
    final cashTotal =
        payments.where((p) => p.method == PaymentMethod.cash).fold<double>(0, (sum, p) => sum + p.amount);
    final grossTotal = telebirrTotal + cashTotal;
    final netProfit = grossTotal - totalExpenses;

    final dateFmt = DateFormat.yMMMd();
    final doc = pw.Document();

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        build: (context) => [
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text('Telebirr Driver Assistant',
                      style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold, color: _brandGreen)),
                  pw.Text('Earnings report', style: const pw.TextStyle(fontSize: 12, color: PdfColors.grey700)),
                ],
              ),
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.end,
                children: [
                  pw.Text(driverName, style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                  pw.Text(driverPhone, style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700)),
                ],
              ),
            ],
          ),
          pw.SizedBox(height: 4),
          pw.Text('${dateFmt.format(from)} - ${dateFmt.format(to)}',
              style: const pw.TextStyle(fontSize: 11, color: PdfColors.grey700)),
          pw.Divider(height: 24),

          _summaryTable([
            ['Telebirr payments', '${telebirrTotal.toStringAsFixed(2)} ETB'],
            ['Cash fares', '${cashTotal.toStringAsFixed(2)} ETB'],
            ['Gross earnings', '${grossTotal.toStringAsFixed(2)} ETB'],
            ['Total expenses', '${totalExpenses.toStringAsFixed(2)} ETB'],
          ]),
          pw.SizedBox(height: 10),
          pw.Container(
            padding: const pw.EdgeInsets.all(10),
            decoration: pw.BoxDecoration(color: PdfColor.fromInt(0xFFEAF9F0), borderRadius: pw.BorderRadius.circular(6)),
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text('Net profit', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 13)),
                pw.Text('${netProfit.toStringAsFixed(2)} ETB',
                    style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 13, color: _brandGreen)),
              ],
            ),
          ),

          if (expensesByCategory.isNotEmpty) ...[
            pw.SizedBox(height: 20),
            pw.Text('Expenses by category', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 12)),
            pw.SizedBox(height: 6),
            _summaryTable([
              for (final entry in expensesByCategory.entries)
                [entry.key.label, '${entry.value.toStringAsFixed(2)} ETB'],
            ]),
          ],

          pw.SizedBox(height: 20),
          pw.Text('Payments (${payments.length})', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 12)),
          pw.SizedBox(height: 6),
          pw.Table(
            border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
            columnWidths: {
              0: const pw.FlexColumnWidth(2.2),
              1: const pw.FlexColumnWidth(2.6),
              2: const pw.FlexColumnWidth(1.6),
              3: const pw.FlexColumnWidth(1.4),
            },
            children: [
              _headerRow(['Date', 'From', 'Amount', 'Type']),
              for (final p in payments)
                pw.TableRow(children: [
                  _cell(DateFormat('MM/dd HH:mm').format(p.receivedAt)),
                  _cell(p.payerName != null ? '${p.payerName} (${p.payerPhone})' : p.payerPhone),
                  _cell('${p.amount.toStringAsFixed(0)} ETB'),
                  _cell(p.method == PaymentMethod.cash ? 'Cash' : 'Telebirr'),
                ]),
            ],
          ),
        ],
      ),
    );

    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/earnings_report_${DateFormat('yyyyMMdd').format(from)}.pdf');
    await file.writeAsBytes(await doc.save());
    return file;
  }

  Future<void> shareEarningsReport({
    required String driverName,
    required String driverPhone,
    required DateTime from,
    required DateTime to,
  }) async {
    final file = await generateEarningsReport(
      driverName: driverName,
      driverPhone: driverPhone,
      from: from,
      to: to,
    );
    await SharePlus.instance.share(
      ShareParams(files: [XFile(file.path)], text: 'Telebirr Driver Assistant — earnings report'),
    );
  }

  pw.Widget _summaryTable(List<List<String>> rows) {
    return pw.Table(
      columnWidths: {0: const pw.FlexColumnWidth(3), 1: const pw.FlexColumnWidth(2)},
      children: [
        for (final row in rows)
          pw.TableRow(children: [
            pw.Padding(
              padding: const pw.EdgeInsets.symmetric(vertical: 4),
              child: pw.Text(row[0], style: const pw.TextStyle(fontSize: 11)),
            ),
            pw.Padding(
              padding: const pw.EdgeInsets.symmetric(vertical: 4),
              child: pw.Text(row[1], style: const pw.TextStyle(fontSize: 11), textAlign: pw.TextAlign.right),
            ),
          ]),
      ],
    );
  }

  pw.TableRow _headerRow(List<String> labels) => pw.TableRow(
        decoration: const pw.BoxDecoration(color: PdfColor.fromInt(0xFFEAF9F0)),
        children: [for (final l in labels) _cell(l, bold: true)],
      );

  pw.Widget _cell(String text, {bool bold = false}) => pw.Padding(
        padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 5),
        child: pw.Text(text, style: pw.TextStyle(fontSize: 9, fontWeight: bold ? pw.FontWeight.bold : null)),
      );
}
