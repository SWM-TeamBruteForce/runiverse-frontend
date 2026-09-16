import 'package:flutter_test/flutter_test.dart';
import 'package:runiverse/features/matching/domain/run_launch.dart';

/// 언제 쏘고, 언제 3-2-1을 보여주는가.
///
/// ⚠️ **발사 시각을 당기면 서버가 거절한다.** `RUNNING_START`가 `start_at`보다
/// 이르면 `INVALID_ROOM_STATE`다. 연출은 줄여도 시각은 그대로여야 한다.
void main() {
  final at = DateTime(2026, 9, 16, 19);
  final launch = RunLaunch(at);

  /// 출발 [ms]밀리초 전.
  DateTime before(int ms) => at.subtract(Duration(milliseconds: ms));

  group('남은 시간', () {
    test('그대로 센다', () {
      expect(launch.remaining(before(8000)), const Duration(seconds: 8));
    });

    test('⚠️ 지나면 0이다', () {
      // 화면이 "-3초"를 그리게 두면 안 된다.
      expect(launch.remaining(at), Duration.zero);
      expect(
        launch.remaining(at.add(const Duration(seconds: 5))),
        Duration.zero,
      );
    });
  });

  group('언제 쏘는가', () {
    test('정각이면 쏜다', () {
      expect(launch.shouldLaunch(at), isTrue);
    });

    test('⚠️ 1밀리초라도 이르면 쏘지 않는다', () {
      // 이르면 서버가 INVALID_ROOM_STATE로 거절한다.
      expect(launch.shouldLaunch(before(1)), isFalse);
    });

    test('지났으면 곧바로 쏜다', () {
      // 앱이 늦게 깼거나 통지를 못 받은 경우다. 그래도 시작한다.
      expect(launch.shouldLaunch(at.add(const Duration(minutes: 2))), isTrue);
    });
  });

  group('언제 대기실로 들어가는가', () {
    test('30초 전부터 들어간다', () {
      // 정각에 붙기 시작하면 첫 메시지가 그만큼 늦는다.
      expect(launch.shouldEnter(before(30000)), isTrue);
      expect(launch.shouldEnter(before(31000)), isFalse);
    });

    test('이미 지났으면 당연히 들어간다', () {
      expect(launch.shouldEnter(at.add(const Duration(minutes: 1))), isTrue);
    });
  });

  group('3-2-1', () {
    test('3초보다 멀면 숫자를 띄우지 않는다', () {
      expect(launch.countdownNumber(before(3001)), isNull);
    });

    test('⚠️ 올림해서 보여준다', () {
      // 2.4초 남았는데 2를 띄우면 마지막 1초가 0으로 보인다.
      expect(launch.countdownNumber(before(3000)), 3);
      expect(launch.countdownNumber(before(2400)), 3);
      expect(launch.countdownNumber(before(2000)), 2);
      expect(launch.countdownNumber(before(1200)), 2);
      expect(launch.countdownNumber(before(1000)), 1);
      expect(launch.countdownNumber(before(300)), 1);
    });

    test('정각에는 숫자가 없다', () {
      // 이 순간은 숫자가 아니라 출발이다.
      expect(launch.countdownNumber(at), isNull);
      expect(
        launch.countdownNumber(at.add(const Duration(seconds: 1))),
        isNull,
      );
    });
  });
}
