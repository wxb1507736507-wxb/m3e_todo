/// A folder a todo — or a note — can be filed under.
///
/// Deliberately flat: one level, like the contact groups this is modelled on.
/// Nesting folders sounds more powerful and is, in practice, a filing system
/// nobody maintains; a single level is what people actually keep up.
class Category {
  const Category({required this.id, required this.name, this.color});

  /// Builds one from raw input, applying the domain's rules: the name is trimmed
  /// and must not be blank.
  factory Category.create({
    required String id,
    required String name,
    int? color,
  }) {
    final String normalized = name.trim();
    if (normalized.isEmpty) {
      throw const CategoryValidationException('A category needs a name.');
    }
    return Category(id: id, name: normalized, color: color);
  }

  final String id;
  final String name;

  /// ARGB32 accent, or `null` for the theme's own colour. Stored as an int so
  /// the domain stays free of Flutter imports.
  final int? color;

  Category edited({required String name, required int? color}) {
    final String normalized = name.trim();
    if (normalized.isEmpty) {
      throw const CategoryValidationException('A category needs a name.');
    }
    return Category(id: id, name: normalized, color: color);
  }

  @override
  bool operator ==(Object other) =>
      other is Category &&
      other.id == id &&
      other.name == name &&
      other.color == color;

  @override
  int get hashCode => Object.hash(id, name, color);

  @override
  String toString() => 'Category($id, "$name")';
}

/// Thrown when a category would break the rule that a name is required.
class CategoryValidationException implements Exception {
  const CategoryValidationException(this.message);

  final String message;

  @override
  String toString() => 'CategoryValidationException: $message';
}
