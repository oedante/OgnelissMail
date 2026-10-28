import 'package:flutter_test/flutter_test.dart';
import 'package:ogneliss/core/utils/category_colors.dart';

void main() {
  test('стандартные категории Outlook — цвет по названию', () {
    final red = CategoryColors.of(['Красная категория']);
    expect(red, isNotNull);
    expect(CategoryColors.of(['Red category']), red);
    expect(CategoryColors.of(['Kategorie Rot']), red);
    expect(CategoryColors.of(['Синяя категория']), CategoryColors.of(['Blue category']));
  });

  test('своя категория — постоянный цвет; без категорий — null', () {
    expect(CategoryColors.of(['Проект Н-102']), CategoryColors.of(['проект н-102']));
    expect(CategoryColors.of(const []), isNull);
    expect(CategoryColors.of(['  ']), isNull);
    // «Ordered» не «red», «Advertising» не «vert».
    expect(CategoryColors.of(['Ordered']), isNot(CategoryColors.of(['Red category'])));
  });
}
