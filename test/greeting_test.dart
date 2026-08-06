import 'package:flutter_test/flutter_test.dart';
import 'package:runiverse/features/home/domain/greeting.dart';

/// 경계값만 본다. 구간 한가운데는 경계가 맞으면 자동으로 맞다.
void main() {
  Greeting at(int hour, [int minute = 0]) =>
      GreetingRule.of(DateTime(2026, 8, 5, hour, minute));

  group('구간의 첫 시각', () {
    test('05시부터 아침이다', () {
      expect(at(5), Greeting.morning);
    });

    test('12시부터 오후다', () {
      expect(at(12), Greeting.afternoon);
    });

    test('18시부터 저녁이다', () {
      expect(at(18), Greeting.evening);
    });

    test('23시부터 밤이다', () {
      expect(at(23), Greeting.night);
    });
  });

  group('구간의 마지막 시각', () {
    test('11시 59분까지 아침이다', () {
      expect(at(11, 59), Greeting.morning);
    });

    test('17시 59분까지 오후다', () {
      expect(at(17, 59), Greeting.afternoon);
    });

    test('22시 59분까지 저녁이다', () {
      expect(at(22, 59), Greeting.evening);
    });
  });

  group('밤은 자정을 넘어 이어진다', () {
    test('자정도 밤이다', () {
      expect(at(0), Greeting.night);
    });

    test('04시 59분까지 밤이다', () {
      expect(at(4, 59), Greeting.night);
    });
  });

  test('분은 구간을 바꾸지 않는다', () {
    for (var minute = 0; minute < 60; minute += 7) {
      expect(at(14, minute), Greeting.afternoon, reason: '14:$minute');
    }
  });
}
