import 'package:flutter_test/flutter_test.dart';
import 'package:runiverse/features/session/domain/auto_pause.dart';
import 'package:runiverse/features/session/domain/geo_point.dart';

/// 버튼 없이 멈춘 구간을 가려낸다 — 1.1.0 가이드 2.3.
///
/// ## ⚠️ 이 판정이 틀리면 기록이 통째로 어긋난다
///
/// 서버는 1.1.0부터 정지 구간을 빼고 확정한다. 앱이 같은 기준으로 빼지
/// 않으면 **달리는 내내 보던 숫자와 끝나고 받는 기록이 다르다** — 36분을
/// 서 있던 3km가 화면에서는 76분이었다.
void main() {
  /// 북쪽으로 [meters], 출발로부터 [seconds]초 뒤의 좌표.
  GeoPoint at(double meters, int seconds, {double accuracy = 5}) => GeoPoint(
    latitude: 37.4979 + meters / 111320,
    longitude: 127.0276,
    recordedAt: DateTime(2026, 10, 14, 7).add(Duration(seconds: seconds)),
    accuracy: accuracy,
  );

  group('반경 안에 머무르면 멈춘 것으로 본다', () {
    test('⚠️ 10초를 채우기 전에는 세어 둔다', () {
      // ⚠️ **아직 모른다.** 짧은 머무름은 신호 대기인지 그냥 느린 구간인지
      // 가를 수 없다. 여기서 미리 빼면 **느리게 뛴 사람의 거리가 사라진다.**
      final auto = AutoPause();
      auto.add(at(0, 0));

      final step = auto.add(at(2, 8));

      expect(step.counts, isTrue);
      expect(step.stopped, isFalse);
      expect(auto.stopped, isFalse);
    });

    test('10초를 채우면 멈춘 것으로 본다', () {
      final auto = AutoPause();
      auto.add(at(0, 0));

      final step = auto.add(at(2, 10));

      expect(step.stopped, isTrue);
      expect(step.counts, isFalse, reason: '멈춘 뒤로는 세지 않는다');
      expect(auto.stopped, isTrue);
    });

    test('⚠️ 세어 둔 것을 통째로 되돌린다', () {
      // 가이드 — "기준점부터 inside까지 이미 누적한 시간·거리도 제외".
      // 되돌리지 않으면 **흔들린 만큼이 달린 거리로 남는다.**
      final auto = AutoPause();
      auto.add(at(0, 0));
      auto.add(at(3, 4)); // 세어 둔다
      auto.add(at(1, 8)); // 세어 둔다

      final step = auto.add(at(3, 12));

      expect(step.stopped, isTrue);
      // 0→3m(3m) + 3→1m(2m) = 5m 가 세어져 있다. 확정시키는 좌표
      // (1→3m)는 세기 전에 확정되므로 들어가지 않는다.
      expect(step.rollbackMeters, closeTo(5, 0.2));
      expect(step.rollbackElapsed, const Duration(seconds: 12));
    });

    test('⚠️ 멈춘 뒤에는 더 되돌리지 않는다', () {
      // 두 번 빼면 **멀쩡히 달린 구간까지 사라진다.**
      final auto = AutoPause();
      auto.add(at(0, 0));
      auto.add(at(2, 12)); // 여기서 확정

      final step = auto.add(at(1, 20));

      expect(step.stopped, isTrue);
      expect(step.rollbackMeters, 0);
      expect(step.rollbackElapsed, Duration.zero);
    });
  });

  group('반경을 벗어나면 다시 간다', () {
    test('⚠️ 빠져나가는 이동은 센다', () {
      // 가이드 — "inside → 반경 밖 좌표의 이동은 정상 이동으로 포함".
      // 빼면 **멈췄다 출발할 때마다 몇 미터씩 사라진다.**
      final auto = AutoPause();
      auto.add(at(0, 0));
      auto.add(at(2, 12));
      expect(auto.stopped, isTrue);

      final step = auto.add(at(40, 20));

      expect(step.counts, isTrue);
      expect(step.stopped, isFalse);
      expect(auto.stopped, isFalse);
    });

    test('⚠️ 벗어난 좌표가 새 기준점이 된다', () {
      // 옛 기준점을 들고 있으면 **출발하자마자 다시 "반경 밖"이라** 정지를
      // 영영 못 잡는다.
      final auto = AutoPause();
      auto.add(at(0, 0));
      auto.add(at(2, 12));
      auto.add(at(40, 20)); // 새 기준점

      // 새 기준점 둘레에서 10초를 머무른다.
      final step = auto.add(at(42, 32));

      expect(step.stopped, isTrue);
    });
  });

  group('⚠️ 반경은 좌표마다 다시 잰다', () {
    test('신호가 나빠도 5~8m 위로는 안 벌어진다', () {
      // ⚠️ `accuracy`를 그대로 믿으면 **100m짜리 좌표 하나로 달리는 사람이
      // 멈춘 것이 된다.** 위를 자른다.
      final auto = AutoPause();
      auto.add(at(0, 0, accuracy: 100));

      final step = auto.add(at(30, 12, accuracy: 100));

      expect(step.stopped, isFalse, reason: '30m는 8m 밖이다');
    });

    test('⚠️ 신호가 좋아도 5m 아래로는 안 좁아진다', () {
      // 고정 반경을 좁게 두면 **가만히 서 있어도 좌표가 튀어** 정지를 못
      // 잡는다. 아래도 자른다.
      final auto = AutoPause();
      auto.add(at(0, 0, accuracy: 1));

      final step = auto.add(at(4, 12, accuracy: 1));

      expect(step.stopped, isTrue, reason: '4m는 5m 안이다');
    });
  });

  test('첫 좌표는 그냥 기준점이 된다', () {
    final auto = AutoPause();

    final step = auto.add(at(0, 0));

    expect(step.counts, isTrue);
    expect(step.stopped, isFalse);
  });

  test('⚠️ `reset`이 기준점을 버린다', () {
    // 버튼으로 멈췄다 다시 갈 때 부른다. 안 버리면 **그 사이 걸어간 자리를
    // 옛 기준점에서 재어** 엉뚱하게 "반경 밖"이 된다.
    final auto = AutoPause();
    auto.add(at(0, 0));
    auto.add(at(2, 12));
    expect(auto.stopped, isTrue);

    auto.reset();

    expect(auto.stopped, isFalse);
    expect(auto.add(at(500, 20)).counts, isTrue);
  });
}
