import 'package:flutter_test/flutter_test.dart';
import 'package:runiverse/features/session/domain/run_numbers.dart';

/// 러닝의 번호 두 개 — **올리는 규칙이 전부다.**
///
/// ## ⚠️ 여기가 1.1.1의 심장이다
///
/// 서버는 **번호가 다른 연속 좌표 사이**를 멈춘 구간으로 보고 거리·시간·고도
/// 에서 뺀다. 번호를 한 번 더 올리면 멈추지 않은 구간이 빠지고, 안 올리면
/// 멈춘 구간이 거리에 들어간다 — 고치려던 바로 그 버그다.
///
/// 순수 Dart다. 값을 손으로 먹여 본다.
void main() {
  group('새 러닝', () {
    test('순번은 1, 구간 번호는 0이다', () {
      expect(RunNumbers.start.nextSequence, 1);
      expect(RunNumbers.start.pauseSegment, 0);
    });
  });

  group('일시정지', () {
    test('⚠️ 구간 번호만 올라간다 — 순번은 그대로다', () {
      // `sequence`는 일시정지와 무관하게 이어 증가한다. 여기서 같이 밀면
      // 쓰지 않은 번호가 비고, 서버가 경로를 이을 때 빈 자리를 만난다.
      final paused = RunNumbers.start.afterPause();

      expect(paused.pauseSegment, 1);
      expect(paused.nextSequence, 1);
    });

    test('멈춘 횟수만큼 올라간다', () {
      final twice = RunNumbers.start.afterPause().afterPause();

      expect(twice.pauseSegment, 2);
    });

    test('⚠️ 상한에서 멈춘다', () {
      // 10만을 넘기면 `INVALID_REQUEST`로 **배치 전체가 거부된다.** 사람이
      // 10만 번 멈출 일은 없으니 여기 닿는 것은 버그인데, 그때 러닝을 통째로
      // 잃는 것보다 멈춤 몇 번이 한 구간으로 뭉개지는 편이 낫다.
      const atLimit = RunNumbers(
        nextSequence: 1,
        pauseSegment: RunNumbers.maxPauseSegment,
      );

      expect(atLimit.afterPause().pauseSegment, RunNumbers.maxPauseSegment);
    });
  });

  group('좌표 하나', () {
    test('⚠️ 순번만 올라간다 — 구간 번호는 그대로다', () {
      // 좌표가 쌓이는 동안 구간 번호가 움직이면, 멈추지도 않았는데 서버가
      // 경계를 본다.
      final after = const RunNumbers(
        nextSequence: 7,
        pauseSegment: 2,
      ).afterPoint();

      expect(after.nextSequence, 8);
      expect(after.pauseSegment, 2);
    });
  });

  group('⚠️ 큰 쪽으로 맞추기', () {
    test('저장된 값이 앞서 있으면 그쪽을 따른다', () {
      // 앱을 재설치하면 로컬 번호가 0으로 태어난다. 그 번호로 보내면 이미 쓴
      // 순번은 중복으로 무시되고, 구간 번호는 줄어들어 거부된다.
      final merged = RunNumbers.start.mergedWith(
        const RunNumbers(nextSequence: 120, pauseSegment: 2),
      );

      expect(merged.nextSequence, 120);
      expect(merged.pauseSegment, 2);
    });

    test('들고 있던 값이 앞서 있으면 그대로 둔다', () {
      // 로컬이 서버·저장소보다 앞서는 것은 정상이다 — 아직 안 보낸 좌표가
      // 있다는 뜻이다. 뒤로 물리면 그 좌표를 덮어쓴다.
      const local = RunNumbers(nextSequence: 300, pauseSegment: 5);

      final merged = local.mergedWith(
        const RunNumbers(nextSequence: 120, pauseSegment: 2),
      );

      expect(merged.nextSequence, 300);
      expect(merged.pauseSegment, 5);
    });

    test('⚠️ 둘을 따로 고른다', () {
      // 한쪽이 앞서고 다른 쪽이 뒤처지는 조합이 실제로 생긴다 — 재설치 뒤
      // 서버에서 받은 순번은 크지만, 멈춘 뒤 올린 구간 번호는 로컬이 크다.
      // 통째로 한쪽을 고르면 나머지가 뒤로 물린다.
      final merged = const RunNumbers(
        nextSequence: 10,
        pauseSegment: 5,
      ).mergedWith(const RunNumbers(nextSequence: 120, pauseSegment: 2));

      expect(merged.nextSequence, 120);
      expect(merged.pauseSegment, 5);
    });
  });

  group('값으로 비교한다', () {
    test('같은 번호면 같다', () {
      expect(
        const RunNumbers(nextSequence: 3, pauseSegment: 1),
        const RunNumbers(nextSequence: 3, pauseSegment: 1),
      );
    });

    test('한 쪽만 달라도 다르다', () {
      expect(
        const RunNumbers(nextSequence: 3, pauseSegment: 1),
        isNot(const RunNumbers(nextSequence: 3, pauseSegment: 2)),
      );
    });
  });
}
