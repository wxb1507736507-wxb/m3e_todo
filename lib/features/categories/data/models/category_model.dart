import '../../domain/entities/category.dart';

/// Translates between [Category] and the JSON shape written to disk.
abstract final class CategoryModel {
  /// Version 1 is the first shape this document has had.
  static const int schemaVersion = 1;

  static Map<String, Object?> toJson(Category category) {
    return <String, Object?>{
      'id': category.id,
      'name': category.name,
      // Absent rather than null: "no colour" is the common case, and leaving the
      // key out keeps the file readable.
      if (category.color != null) 'color': category.color,
    };
  }

  /// Rebuilds a category, or returns `null` when the record is unusable.
  static Category? fromJson(Map<String, Object?> json) {
    final Object? id = json['id'];
    final Object? name = json['name'];
    if (id is! String || id.isEmpty || name is! String || name.trim().isEmpty) {
      return null;
    }
    final Object? color = json['color'];
    return Category(
      id: id,
      name: name,
      color: color is int ? color : null,
    );
  }
}
