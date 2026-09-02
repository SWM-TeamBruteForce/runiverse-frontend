import 'package:runiverse/features/session/domain/geo_point.dart';
import 'package:runiverse/features/session/domain/run_split.dart';

/// 러닝 하나의 상세. **S16 화면이 그리는 것 전부**다.
///
/// ## 화면 하나가 두 곳에서 열린다
///
/// 러닝을 막 끝냈을 때(S15 → S16)와 기록 탭에서 지난 기록을 눌렀을 때다.
/// 앞은 앱이 방금 계산한 값으로, 뒤는 서버가 확정한 값(20번)으로 채운다.
/// **화면은 어느 쪽인지 모른다** — 그래서 이 모델이 둘 사이에 있다.
///
/// ## 구간을 여기서 이미 나눠 둔다
///
/// 화면이 `SplitCalculator`를 부르지 않는다. 서버에서 온 기록은 서버가
/// 나눈 구간을 그대로 써야 하는데, 화면이 다시 계산하면 두 숫자가 갈린다.
class RunDetail {
  const RunDetail({
    required this.distanceKm,
    required this.duration,
    required this.averagePace,
    required this.track,
    required this.splits,
    this.recordId,
    this.cadenceSpm,
    this.cadenceIsSample = false,
  });

  /// 서버 기록의 번호. **막 끝낸 러닝이면 `null`이다** — 아직 기록이 없다.
  final int? recordId;

  final double distanceKm;

  /// 총 러닝 시간. 일시정지는 빠져 있다.
  final Duration duration;

  final Duration averagePace;

  /// 전체 평균 케이던스. 못 구하면 `null`이라 화면이 `--`를 쓴다.
  final int? cadenceSpm;

  /// 지도에 그릴 경로. 세그먼트마다 선이 끊긴다(일시정지 구간).
  ///
  /// 서버 기록은 좌표가 한 줄로 오므로 세그먼트가 하나다.
  final List<List<GeoPoint>> track;

  final List<RunSplitDetail> splits;

  /// ⚠️ 구간 케이던스가 **지어낸 값인가.**
  ///
  /// `true`면 차트에 `예시` 꼬리표가 붙는다. 가짜 값을 진짜처럼 두지 않으려고
  /// 모델이 들고 다닌다 — 화면이 출처를 짐작하지 않게 한다.
  final bool cadenceIsSample;

  bool get hasSplits => splits.isNotEmpty;
}

/// 구간 하나 + 그 구간의 파생 지표.
///
/// [RunSplit]을 감싸는 이유는 **거리·시간은 계산으로 나오지만 케이던스·칼로리는
/// 출처가 다르기** 때문이다. 앱이 낼 때도 있고 서버가 줄 때도 있다.
class RunSplitDetail {
  const RunSplitDetail({
    required this.split,
    this.cadenceSpm,
    this.caloriesKcal,
  });

  final RunSplit split;

  /// 구간 평균 케이던스. 표본이 부족하면 `null`이다.
  final int? cadenceSpm;

  /// 구간 소모 칼로리. 몸무게를 모르면 `null`이다.
  final int? caloriesKcal;

  int get index => split.index;
  double get distanceMeters => split.distanceMeters;
  Duration get pace => split.pace;
  bool get isPartial => split.isPartial;
}
