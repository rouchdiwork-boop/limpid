/// The tables that may hold the formula of the accounts.
///
/// The formula belongs to the module that owns the plans: the back-office
/// probes the tables and ignores the accounts whose formula it cannot read,
/// rather than failing. The tables are tried in this order, and the formulas
/// they hold are merged.
const List<String> adminPlanTables = <String>['subscriptions', 'account_plans'];

/// The columns that may hold the identifier of the account.
const List<String> adminPlanAccountColumns = <String>['user_id', 'account_id'];

/// The column that holds the formula.
const String adminPlanColumn = 'plan';

/// The column that holds the state of the formula.
const String adminPlanStatusColumn = 'status';

/// The states of a formula that do not grant anything.
const List<String> adminInactivePlanStatuses = <String>[
  'canceled',
  'cancelled',
  'expired',
  'incomplete',
  'incomplete_expired',
  'unpaid',
];

/// The column holding the identifier of the account, `null` when the table
/// has none.
String? adminPlanAccountColumnOf(Set<String> columns) {
  for (final String candidate in adminPlanAccountColumns) {
    if (columns.contains(candidate)) return candidate;
  }
  return null;
}

/// Whether the row describes a formula that grants something.
///
/// A row without a state grants something: the module that owns the plans
/// decides which rows are active, and a table that does not carry a state
/// carries no cancelled formula.
bool isActiveAdminPlan(Map<String, Object?> row, bool hasStatus) {
  if (!hasStatus) return true;
  final Object? status = row[adminPlanStatusColumn];
  if (status is! String) return true;
  return !adminInactivePlanStatuses.contains(status.toLowerCase());
}
