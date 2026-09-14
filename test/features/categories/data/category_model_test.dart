import 'package:flutter_test/flutter_test.dart';
import 'package:m3e_todo/features/categories/data/models/category_model.dart';
import 'package:m3e_todo/features/categories/domain/entities/category.dart';

void main() {
  group('round trip', () {
    test('preserves every field', () {
      final Category original = Category.create(
        id: 'c1',
        name: '工作',
        color: 0xFF1E88E5,
      );

      final Map<String, Object?> json = CategoryModel.toJson(original);

      expect(json['name'], '工作');
      expect(json['color'], 0xFF1E88E5);
      expect(CategoryModel.fromJson(json), original);
    });

    test('leaves the colour out when there is none', () {
      final Map<String, Object?> json =
          CategoryModel.toJson(Category.create(id: 'c1', name: '生活'));
      expect(json.containsKey('color'), isFalse);
      expect(CategoryModel.fromJson(json)?.color, isNull);
    });
  });

  group('resilience', () {
    test('rejects a record with no id', () {
      expect(
        CategoryModel.fromJson(<String, Object?>{'name': '工作'}),
        isNull,
      );
    });

    test('rejects a blank name', () {
      expect(
        CategoryModel.fromJson(<String, Object?>{'id': 'c1', 'name': '   '}),
        isNull,
      );
    });

    test('ignores a colour that is not a number', () {
      expect(
        CategoryModel.fromJson(<String, Object?>{
          'id': 'c1',
          'name': '工作',
          'color': 'blue',
        })?.color,
        isNull,
      );
    });
  });

  group('editing', () {
    test('keeps identity and applies every field', () {
      final Category edited =
          Category.create(id: 'c1', name: '工作').edited(name: '工作事务', color: 0xFFE53935);
      expect(edited.id, 'c1');
      expect(edited.name, '工作事务');
      expect(edited.color, 0xFFE53935);
    });

    test('rejects a blank name', () {
      expect(
        () => Category.create(id: 'c1', name: '工作').edited(name: ' ', color: null),
        throwsA(isA<CategoryValidationException>()),
      );
    });
  });
}
