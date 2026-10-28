import 'package:flutter_test/flutter_test.dart';
import 'package:runiverse/features/session/domain/combo_milestone.dart';

/// 콤보가 어디서 한 번 울리는가 — 1 · 3 · 5 · 10 · 이후 10마다.
///
/// ## ⚠️ 눈금이 아니라 **직전 눈금**을 돌려준다
///
/// "지금 눈금인가"를 묻는 함수였다면 통지를 한 번 놓치는 순간 그 눈금은
/// 영영 안 울린다. 콤보는 10초마다 1씩 오르지만 재연결하면 7에서 시작하기도
/// 한다. **직전에 지난 눈금**을 비교하면 건너뛴 눈금도 한 번은 울린다.
void main() {
  group('직전에 지난 눈금', () {
    test('콤보가 없으면 0이다', () {
      expect(comboMilestoneOf(0), 0);
    });

    test('1·3·5는 그 자리에서 눈금이다', () {
      expect(comboMilestoneOf(1), 1);
      expect(comboMilestoneOf(3), 3);
      expect(comboMilestoneOf(5), 5);
    });

    test('눈금 사이는 직전 눈금에 머문다', () {
      // ⚠️ 2와 4에서 다시 울리면 10초마다 울리는 것과 같아진다.
      expect(comboMilestoneOf(2), 1);
      expect(comboMilestoneOf(4), 3);
    });

    test('10부터는 10마다다', () {
      expect(comboMilestoneOf(9), 5);
      expect(comboMilestoneOf(10), 10);
      expect(comboMilestoneOf(14), 10);
      // ⚠️ 15는 눈금이 아니다. 눈금 사이에도 틱이 울리므로 공백이 생기지
      // 않는다 — 눈금은 성겨야 한 번의 무게가 산다.
      expect(comboMilestoneOf(15), 10);
      expect(comboMilestoneOf(37), 30);
      // 실주행에서 24까지 나왔다. 그보다 길게 이어져도 규칙은 같다.
      expect(comboMilestoneOf(100), 100);
    });
  });

  group('⚠️ 눈금이 올랐는가', () {
    test('한 칸 오르면 울린다', () {
      expect(comboMilestonePassed(before: 0, after: 1), isTrue);
      expect(comboMilestonePassed(before: 2, after: 3), isTrue);
    });

    test('눈금 사이를 오르면 울리지 않는다', () {
      expect(comboMilestonePassed(before: 1, after: 2), isFalse);
      expect(comboMilestonePassed(before: 5, after: 9), isFalse);
      expect(comboMilestonePassed(before: 10, after: 14), isFalse);
    });

    test('⚠️ 건너뛰어도 한 번만 울린다', () {
      // 재연결하면 0에서 7로 뛴다. 1·3·5를 몰아서 울리면 세 번 떨린다.
      expect(comboMilestonePassed(before: 0, after: 7), isTrue);
    });

    test('⚠️ 끊겼다 다시 이어지면 1부터 다시 울린다', () {
      // 최고 기록을 넘을 때만 울리면, 30m 경계에서 오래 버틴 사람이
      // 아무 말도 못 듣는다. 이어진 것 자체가 알릴 일이다.
      expect(comboMilestonePassed(before: 24, after: 0), isFalse);
      expect(comboMilestonePassed(before: 0, after: 1), isTrue);
    });

    test('줄어들 때는 울리지 않는다', () {
      expect(comboMilestonePassed(before: 10, after: 3), isFalse);
    });
  });
}
