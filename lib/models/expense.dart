enum ExpenseCategory { fuel, maintenance, insurance, other }

extension ExpenseCategoryLabel on ExpenseCategory {
  String get label {
    switch (this) {
      case ExpenseCategory.fuel:
        return 'Fuel';
      case ExpenseCategory.maintenance:
        return 'Maintenance';
      case ExpenseCategory.insurance:
        return 'Insurance';
      case ExpenseCategory.other:
        return 'Other';
    }
  }

  static ExpenseCategory fromLabel(String label) {
    return ExpenseCategory.values.firstWhere(
      (e) => e.label.toLowerCase() == label.toLowerCase(),
      orElse: () => ExpenseCategory.other,
    );
  }
}

class Expense {
  final int? id;
  final ExpenseCategory category;
  final double amount;
  final String? description;
  final DateTime expenseDate;
  final DateTime createdAt;
  final bool synced;

  Expense({
    this.id,
    required this.category,
    required this.amount,
    this.description,
    required this.expenseDate,
    DateTime? createdAt,
    this.synced = false,
  }) : createdAt = createdAt ?? DateTime.now();

  Map<String, dynamic> toMap() => {
        'id': id,
        'category': category.label,
        'amount': amount,
        'description': description,
        'expense_date': expenseDate.toIso8601String(),
        'created_at': createdAt.toIso8601String(),
        'synced': synced ? 1 : 0,
      };

  factory Expense.fromMap(Map<String, dynamic> map) => Expense(
        id: map['id'] as int?,
        category: ExpenseCategoryLabel.fromLabel(map['category'] as String? ?? 'Other'),
        amount: (map['amount'] as num).toDouble(),
        description: map['description'] as String?,
        expenseDate: DateTime.parse(map['expense_date'] as String),
        createdAt: DateTime.parse(map['created_at'] as String),
        synced: (map['synced'] as int? ?? 0) == 1,
      );
}
