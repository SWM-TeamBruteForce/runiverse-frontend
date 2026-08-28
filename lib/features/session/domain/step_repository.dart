/// 기기가 센 걸음 한 번.
///
/// ## ⚠️ 부팅 이후 누적이다
///
/// 안드로이드 `TYPE_STEP_COUNTER`는 **기기를 켠 뒤 총 몇 걸음인지**를 준다.
/// 이번 러닝의 걸음 수가 아니다. 그래서 이 값 자체는 쓸 데가 없고,
/// **두 표본의 차이**로만 의미가 생긴다([CadenceCalculator]).
class StepSample {
  const StepSample({required this.steps, required this.at});

  /// 부팅 이후 누적 걸음 수.
  final int steps;

  /// 기기가 이 값을 만든 시각.
  final DateTime at;
}

/// 걸음 센서를 누가 읽을 것인가.
///
/// 위치와 같은 모양이다 — 패키지 타입이 밖으로 새지 않게 `data`에서 도메인
/// 타입으로 옮기고, 테스트는 가짜를 끼운다.
abstract interface class StepRepository {
  /// 걸음 센서를 쓸 수 있는가. 권한이 없으면 물어본다.
  ///
  /// ⚠️ **`ACTIVITY_RECOGNITION`은 Android 10부터 런타임 권한이다.** 선언만
  /// 해두면 센서가 조용히 아무것도 주지 않는다 — 에러도 나지 않는다.
  Future<bool> ensureAccess();

  /// 걸음이 늘 때마다 알린다.
  ///
  /// ⚠️ **초당 한 번이 아니다.** 안드로이드가 이벤트를 묶어 보내 몇 초씩
  /// 몰려 오기도 한다. 그래서 창으로 평균을 낸다.
  Stream<StepSample> watchSteps();
}
