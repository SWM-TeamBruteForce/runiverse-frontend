import 'package:flutter_test/flutter_test.dart';
import 'package:runiverse/features/session/domain/runner_status.dart';

/// 참가자 상태를 전선에서 읽는다.
///
/// ## ⚠️ 1.1.0 에서 `paused`(bool) 가 `status`(문자열) 로 바뀌었다
///
/// `bool` 로는 **멈춘 것·끊긴 것·끝난 것**이 전부 같아 보였다.
void main() {
  test('네 상태를 읽는다', () {
    expect(RunnerStatus.of('RUNNING'), RunnerStatus.running);
    expect(RunnerStatus.of('PAUSED'), RunnerStatus.paused);
    expect(RunnerStatus.of('DISCONNECTED'), RunnerStatus.disconnected);
    expect(RunnerStatus.of('FINISHED'), RunnerStatus.finished);
  });

  group('⚠️ 모르는 값은 뛰는 중으로 본다', () {
    // 반대로 `disconnected` 로 떨어뜨리면 **멀쩡히 뛰는 사람이 끊긴 것처럼**
    // 보인다. 통지가 끊긴 것은 화면이 `stale` 로 따로 보조한다.
    test('없으면', () => expect(RunnerStatus.of(null), RunnerStatus.running));
    test('빈 문자열이면', () {
      expect(RunnerStatus.of(''), RunnerStatus.running);
    });
    test('처음 보는 값이면', () {
      expect(RunnerStatus.of('WARMING_UP'), RunnerStatus.running);
    });
    test('문자열이 아니면', () {
      expect(RunnerStatus.of(true), RunnerStatus.running);
      expect(RunnerStatus.of(3), RunnerStatus.running);
    });
  });

  test('⚠️ 소문자는 읽지 않는다', () {
    // 서버는 대문자로만 준다. 소문자를 받아 주면 **어느 쪽이 맞는지 모르는
    // 채로** 둘 다 도는 코드가 된다.
    expect(RunnerStatus.of('paused'), RunnerStatus.running);
  });

  test('뛰고 있지 않은 셋을 가린다', () {
    expect(RunnerStatus.running.isHalted, isFalse);
    expect(RunnerStatus.paused.isHalted, isTrue);
    expect(RunnerStatus.disconnected.isHalted, isTrue);
    expect(RunnerStatus.finished.isHalted, isTrue);
  });
}
