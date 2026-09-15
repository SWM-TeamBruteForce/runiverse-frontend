import 'package:flutter_test/flutter_test.dart';
import 'package:runiverse/features/session/domain/run_progress.dart';

/// 파티원의 진행과 콤보를 **어떻게 읽는가.**
///
/// 둘 다 고빈도 메시지라 이름도 사진도 오지 않는다. 읽기에 실패해도 러닝을
/// 끊을 수 없어, 무엇을 버리고 무엇을 살리는지가 전부다.
void main() {
  group('진행', () {
    test('값을 그대로 옮긴다', () {
      final progress = RunProgress.of({
        'userId': 'u-1',
        'distanceMeters': 1520,
        'targetDistanceMeters': 5000,
        'currentPaceSecondsPerKm': 345,
        'paused': false,
      })!;

      expect(progress.userId, 'u-1');
      expect(progress.distanceMeters, 1520);
      expect(progress.currentPaceSecondsPerKm, 345);
      expect(progress.paused, isFalse);
    });

    test('페이스를 못 잰 경우가 있다', () {
      // 단말이 못 재면 null로 온다. 0으로 읽으면 "0초/km"가 화면에 뜬다.
      final progress = RunProgress.of({
        'userId': 'u-1',
        'distanceMeters': 100,
        'currentPaceSecondsPerKm': null,
      })!;

      expect(progress.currentPaceSecondsPerKm, isNull);
    });

    test('⚠️ 멈춘 것과 느려진 것을 가른다', () {
      // paused가 없으면 화면에서 갑자기 뒤처진 것처럼 보인다.
      final paused = RunProgress.of({
        'userId': 'u-1',
        'distanceMeters': 100,
        'paused': true,
      })!;

      expect(paused.paused, isTrue);
    });

    test('필수 값이 빠지면 읽지 않는다', () {
      expect(RunProgress.of({'userId': 'u-1'}), isNull);
      expect(RunProgress.of({'distanceMeters': 10}), isNull);
    });

    group('진행률', () {
      test('목표 대비로 낸다', () {
        final progress = RunProgress.of({
          'userId': 'u-1',
          'distanceMeters': 2500,
          'targetDistanceMeters': 5000,
        })!;

        expect(progress.ratio, 0.5);
      });

      test('⚠️ 목표를 넘겨도 1을 넘지 않는다', () {
        // 막대가 칸 밖으로 나간다.
        final progress = RunProgress.of({
          'userId': 'u-1',
          'distanceMeters': 6000,
          'targetDistanceMeters': 5000,
        })!;

        expect(progress.ratio, 1);
      });

      test('⚠️ 목표를 모르면 그리지 않는다', () {
        // 임의의 값으로 막대를 그리면 거짓말이 된다.
        final progress = RunProgress.of({
          'userId': 'u-1',
          'distanceMeters': 2500,
        })!;

        expect(progress.ratio, isNull);
      });
    });
  });

  group('콤보', () {
    test('관계마다 하나씩 읽는다', () {
      final combo = RunCombo.of({
        'peers': [
          {
            'userId': 'u-1',
            'gapMeters': -18,
            'comboCount': 12,
            'maxComboCount': 30,
          },
          {
            'userId': 'u-2',
            'gapMeters': 42,
            'comboCount': 3,
            'maxComboCount': 3,
          },
        ],
      })!;

      expect(combo.peers, hasLength(2));
      // 음수면 상대가 뒤에 있다.
      expect(combo.peers.first.gapMeters, -18);
      expect(combo.peers.first.maxComboCount, 30);
    });

    test('⚠️ 빈 목록은 "아무와도 안 겹친다"는 사실이다', () {
      final combo = RunCombo.of({'peers': <Object>[]})!;

      expect(combo.peers, isEmpty);
    });

    test('⚠️ 못 읽은 것은 빈 목록과 다르다', () {
      // 빈 목록으로 읽으면 멀쩡한 콤보가 화면에서 사라진다.
      expect(RunCombo.of({}), isNull);
      expect(RunCombo.of({'peers': null}), isNull);
    });

    test('읽을 수 없는 상대만 건너뛴다', () {
      final combo = RunCombo.of({
        'peers': [
          {'gapMeters': 10},
          {'userId': 'u-2'},
        ],
      })!;

      expect(combo.peers, hasLength(1));
      expect(combo.peers.single.userId, 'u-2');
      // 값이 빠지면 0으로 읽는다 — 겹쳐 있다는 사실 자체는 서버가 보낸 것이다.
      expect(combo.peers.single.comboCount, 0);
    });
  });
}
