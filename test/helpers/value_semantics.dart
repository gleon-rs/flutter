import 'package:flutter_test/flutter_test.dart';

/// Checks that [value] equals [equal] (with the same hash code), differs
/// from [different] and has a non-empty description.
void expectValueSemantics<T extends Object>(
  T value, {
  required T equal,
  required T different,
}) {
  expect(value, equal);
  expect(value.hashCode, equal.hashCode);
  expect(value, isNot(different));
  expect('$value', isNotEmpty);
}
