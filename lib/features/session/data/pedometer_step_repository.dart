import 'package:pedometer/pedometer.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:runiverse/features/session/domain/step_repository.dart';

/// 실제 걸음 센서를 읽는 구현.
///
/// **이 파일이 `pedometer`를 아는 유일한 곳이다.** 패키지 타입(`StepCount`)이
/// 밖으로 새지 않게 여기서 도메인 타입으로 옮긴다 —
/// `GeolocatorLocationRepository`와 같은 규칙이다.
class PedometerStepRepository implements StepRepository {
  const PedometerStepRepository();

  @override
  Future<bool> ensureAccess() async {
    // ⚠️ **`pedometer` 패키지는 권한을 요청하지 않는다.** 매니페스트가 비어
    // 있고 요청 코드도 없다. 여기서 하지 않으면 센서가 조용히 아무것도 주지
    // 않는다 — 에러도 나지 않아 "왜 케이던스가 안 뜨지"를 한참 쫓게 된다.
    final status = await Permission.activityRecognition.request();
    return status.isGranted;
  }

  @override
  Stream<StepSample> watchSteps() => Pedometer.stepCountStream.map(
    (count) => StepSample(
      steps: count.steps,
      // ⚠️ 패키지가 주는 시각을 쓴다. `DateTime.now()`로 대신하면 안드로이드가
      // 이벤트를 묶어 보낼 때 **여러 표본이 같은 시각을 갖게 되어** 케이던스가
      // 무한대로 튄다.
      at: count.timeStamp,
    ),
  );
}
