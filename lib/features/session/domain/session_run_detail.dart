import 'package:runiverse/features/record/domain/run_detail.dart';
import 'package:runiverse/features/session/domain/calorie_calculator.dart';
import 'package:runiverse/features/session/domain/geo_point.dart';
import 'package:runiverse/features/session/domain/run_metrics.dart';
import 'package:runiverse/features/session/domain/split_calculator.dart';

/// 방금 끝낸 러닝을 [RunDetail]로 옮긴다.
///
/// ## 왜 여기서 만드나
///
/// S16 화면은 [RunDetail] 하나만 받는다 — 세션을 모른다. 그래야 기록 탭이
/// 같은 화면을 열 수 있고, `record`가 `session/presentation`에 기대지 않는다.
/// **세션을 아는 쪽이 옮긴다**는 규칙이라 이 파일이 `session/domain`에 있다.
///
/// ## ⚠️ 이 값은 서버가 확정한 기록이 아니다
///
/// 앱이 러닝 중 계산한 값이다. 서버는 목표 거리를 넘긴 구간을 잘라내는 등
/// 앱이 모르는 규칙으로 기록을 만든다. 종료 직후에는 서버 확정을 기다리지
/// 않고 이 값을 보여주고, 기록 탭에서 다시 열면 그때는 서버 값이 온다.
abstract final class SessionRunDetail {
  const SessionRunDetail._();

  static RunDetail from({
    required RunMetrics metrics,
    required List<List<GeoPoint>> track,
    required int? weightKg,
  }) {
    final splits = SplitCalculator.from(track);
    final cadence = _sampleCadence(splits.length);

    return RunDetail(
      // 아직 서버 기록이 없다. 기록 탭에서 열 때만 번호가 붙는다.
      distanceKm: metrics.distanceKm,
      duration: metrics.elapsed,
      averagePace: metrics.averagePace ?? Duration.zero,
      cadenceSpm: metrics.cadenceSpm,
      track: track,
      // ⚠️ 구간 케이던스가 지어낸 값이라는 것을 모델이 들고 간다.
      cadenceIsSample: true,
      splits: [
        for (var i = 0; i < splits.length; i++)
          RunSplitDetail(
            split: splits[i],
            cadenceSpm: cadence[i],
            caloriesKcal: CalorieCalculator.burned(
              meters: splits[i].distanceMeters,
              elapsed: splits[i].duration,
              weightKg: weightKg,
            ),
          ),
      ],
    );
  }

  /// ⚠️ **진짜 케이던스가 아니다.** 구간별 실측값이 남지 않아 만들어 낸 값이다.
  ///
  /// `TrackPoint`에만 실리는데 그건 서버 ack 뒤 지워지고, 화면에 남는
  /// `GeoPoint`에는 그 값이 없다. 컨트롤러의 걸음 표본도 최근 창만 남기고
  /// 계속 버린다. 실측을 남기려면 러닝 중 1km마다 스냅샷을 들어야 하고,
  /// 그건 실기기 검증과 함께 갈 별도 작업이다.
  ///
  /// 달리기 케이던스가 보통 170~180spm이라 그 언저리에서 흔들리게 두었다.
  static List<int> _sampleCadence(int count) {
    const pattern = [172, 176, 169, 178, 174, 171, 177];
    return [for (var i = 0; i < count; i++) pattern[i % pattern.length]];
  }
}
