import 'dart:math';

/// Produces a unique identifier for a newly created todo.
///
/// Injectable so tests can supply a deterministic sequence instead of relying on
/// randomness and the wall clock.
typedef IdGenerator = String Function();

final Random _random = Random();

/// Default [IdGenerator]: creation time in microseconds (base 36) followed by
/// 32 random bits.
///
/// The time prefix makes ids naturally sortable by creation order, while the
/// random suffix makes collisions between ids created in the same microsecond
/// vanishingly unlikely. It needs no third-party package, unlike a UUID.
String generateTodoId() {
  final String time = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
  final String noise =
      _random.nextInt(1 << 32).toRadixString(36).padLeft(7, '0');
  return '$time-$noise';
}
