import '../db/database_helper.dart';
import '../models/expense.dart';

class ExpenseTracker {
  final DatabaseHelper _dbHelper = DatabaseHelper.instance;

  Future<int> addExpense(Expense expense) async {
    final db = await _dbHelper.database;
    return db.insert('expenses', expense.toMap()..remove('id'));
  }

  Future<List<Expense>> getExpenses({DateTime? from, DateTime? to}) async {
    final db = await _dbHelper.database;
    final where = <String>[];
    final args = <Object?>[];
    if (from != null) {
      where.add('expense_date >= ?');
      args.add(from.toIso8601String());
    }
    if (to != null) {
      where.add('expense_date <= ?');
      args.add(to.toIso8601String());
    }
    final rows = await db.query(
      'expenses',
      where: where.isEmpty ? null : where.join(' AND '),
      whereArgs: args.isEmpty ? null : args,
      orderBy: 'expense_date DESC',
    );
    return rows.map(Expense.fromMap).toList();
  }

  Future<double> getTotalExpenses(DateTime start, DateTime end) async {
    final expenses = await getExpenses(from: start, to: end);
    return expenses.fold<double>(0.0, (sum, e) => sum + e.amount);
  }

  Future<Map<ExpenseCategory, double>> getTotalsByCategory(DateTime start, DateTime end) async {
    final expenses = await getExpenses(from: start, to: end);
    final totals = <ExpenseCategory, double>{};
    for (final e in expenses) {
      totals[e.category] = (totals[e.category] ?? 0) + e.amount;
    }
    return totals;
  }

  Future<void> deleteExpense(int id) async {
    final db = await _dbHelper.database;
    await db.delete('expenses', where: 'id = ?', whereArgs: [id]);
  }
}
