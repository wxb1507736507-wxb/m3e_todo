/// How urgent a todo is.
///
/// [rank] exists so sorting does not depend on declaration order: if the enum
/// is ever reordered for readability, the "priority first" sort keeps working.
/// Higher ranks are more urgent.
enum TodoPriority {
  low(0),
  normal(1),
  high(2);

  const TodoPriority(this.rank);

  /// Sort weight; higher sorts earlier.
  final int rank;
}
