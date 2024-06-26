import 'package:dartnad0/src/time/time_control.dart';
import 'package:test/test.dart';

void main() {
  test('absolute time control is exceeded', () {
    final absolute = AbsoluteTimeControl(DateTime.now());
    absolute.constrain(null);
    expect(absolute.isExceeded(), isTrue);
  });

  test('absolute time control is not exceeded', () {
    final absolute =
        AbsoluteTimeControl(DateTime.now().add(const Duration(seconds: 1)));
    absolute.constrain(null);
    expect(absolute.isExceeded(), isFalse);
  });

  test('absolute time control will be exceeded', () {
    final beforeTime = DateTime.now().add(const Duration(seconds: 1));
    final endTime = DateTime.now().add(const Duration(seconds: 2));
    final pastTime = DateTime.now().add(const Duration(seconds: 3));
    final absolute = AbsoluteTimeControl(endTime);
    expect(absolute.isExceededFor(beforeTime), isFalse);
    expect(absolute.isExceededFor(endTime), isTrue);
    expect(absolute.isExceededFor(pastTime), isTrue);
  });

  test('absolute time control can be constrained', () {
    final beforeTime = DateTime.now().add(const Duration(seconds: 1));
    final originalTime = DateTime.now().add(const Duration(seconds: 3));
    final absolute = AbsoluteTimeControl(originalTime);
    absolute.constrain(const Duration(seconds: 2));
    expect(absolute.isExceededFor(beforeTime), isFalse);
    expect(absolute.isExceededFor(originalTime), isTrue);
    expect(
        absolute.isExceededFor(
            originalTime.subtract(const Duration(milliseconds: 500))),
        isTrue);
  });

  test('absolute time control cant be extended', () {
    final beforeTime = DateTime.now().add(const Duration(seconds: 1));
    final originalTime = DateTime.now().add(const Duration(seconds: 3));
    final absolute = AbsoluteTimeControl(originalTime);
    absolute.constrain(const Duration(seconds: 4));
    expect(absolute.isExceededFor(beforeTime), isFalse);
    expect(absolute.isExceededFor(originalTime), isTrue);
  });

  test('absolute time control to param', () {
    final absolute =
        AbsoluteTimeControl(DateTime.fromMillisecondsSinceEpoch(12345));
    expect(absolute.toQueryParameters(), {'time': '12345'});
  });

  test('absolute time control to param after constrain large', () {
    final absolute =
        AbsoluteTimeControl(DateTime.fromMillisecondsSinceEpoch(12345));
    absolute.constrain(const Duration(milliseconds: 2000));
    expect(absolute.toQueryParameters(), {'time': '12345'});
  });

  test('absolute time control to param after constrain small', () {
    final endTime = DateTime.now().add(const Duration(milliseconds: 150));
    final absolute = AbsoluteTimeControl(endTime);
    expect(absolute.toQueryParameters(),
        {'time': endTime.millisecondsSinceEpoch.toString()});
    absolute.constrain(const Duration(milliseconds: 100));
    expect(absolute.toQueryParameters(),
        isNot({'time': endTime.millisecondsSinceEpoch.toString()}));
    expect(absolute.toQueryParameters(),
        {'time': absolute.endTime.millisecondsSinceEpoch.toString()});
  });

  test('relative time control is exceeded', () {
    final relative = RelativeTimeControl(const Duration(seconds: 0));
    relative.constrain(null);
    expect(relative.isExceeded(), isTrue);
  });

  test('relative time control is not exceeded', () {
    final relative = RelativeTimeControl(const Duration(seconds: 1));
    relative.constrain(null);
    expect(relative.isExceeded(), isFalse);
  });

  test('relative time control will be exceeded', () {
    final beforeTime = DateTime.now().add(const Duration(seconds: 1));
    final endTime = DateTime.now().add(const Duration(seconds: 2));
    final pastTime = DateTime.now().add(const Duration(seconds: 3));
    final relative = RelativeTimeControl(const Duration(seconds: 2));
    relative.constrain(null);
    expect(relative.isExceededFor(beforeTime), isFalse);
    expect(relative.isExceededFor(endTime), isFalse);
    expect(
        relative.isExceededFor(endTime.add(const Duration(milliseconds: 100))),
        isTrue);
    expect(relative.isExceededFor(pastTime), isTrue);
  });

  test('relative time control can be constrained', () {
    final beforeTime = DateTime.now().add(const Duration(seconds: 1));
    final originalTime = DateTime.now().add(const Duration(seconds: 3));
    final relative = RelativeTimeControl(const Duration(seconds: 3));
    relative.constrain(const Duration(seconds: 2));
    expect(relative.isExceededFor(beforeTime), isFalse);
    expect(relative.isExceededFor(originalTime), isTrue);
    expect(
        relative.isExceededFor(
            originalTime.subtract(const Duration(milliseconds: 500))),
        isTrue);
  });

  test('relative time control cant be extended', () {
    final beforeTime = DateTime.now().add(const Duration(seconds: 1));
    final originalTime = DateTime.now().add(const Duration(seconds: 3));
    final relative = RelativeTimeControl(const Duration(seconds: 3));
    relative.constrain(const Duration(seconds: 4));
    expect(relative.isExceededFor(beforeTime), isFalse);
    expect(relative.isExceededFor(originalTime), isFalse);
    expect(
        relative
            .isExceededFor(originalTime.add(const Duration(milliseconds: 100))),
        isTrue);
  });

  test('relative time control to param', () {
    final relative = RelativeTimeControl(const Duration(milliseconds: 123));
    expect(relative.toQueryParameters(), {'reltime': '123'});
  });

  test('relative time control to param after constrain null throws', () {
    final relative = RelativeTimeControl(const Duration(milliseconds: 123));
    relative.constrain(null);
    expect(relative.toQueryParameters, throwsA(anything));
  });

  test('relative time control to param after constrained throws', () {
    final relative = RelativeTimeControl(const Duration(milliseconds: 123));
    relative.constrain(const Duration(milliseconds: 25));
    expect(relative.toQueryParameters, throwsA(anything));
  });

  test('relative time control to param after constrained larger', () {
    final relative = RelativeTimeControl(const Duration(milliseconds: 123));
    relative.constrain(const Duration(milliseconds: 2500));
    expect(relative.toQueryParameters, throwsA(anything));
  });
}
