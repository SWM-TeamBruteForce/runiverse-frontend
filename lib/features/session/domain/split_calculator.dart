import 'package:runiverse/features/session/domain/geo_point.dart';
import 'package:runiverse/features/session/domain/run_split.dart';

/// 달린 경로를 1km 구간으로 끊는다.
///
/// ## 경계는 좌표 사이에 걸린다
///
/// GPS는 1km 지점에 딱 맞춰 좌표를 주지 않는다. 두 좌표 사이 어딘가에서 1km가
/// 넘어가므로, **그 다리를 거리 비율로 잘라 시간도 같은 비율로 나눈다.**
/// 넘어간 좌표에서 끊으면 구간이 1km보다 조금씩 길어지고, 그 오차가 뒤로 갈수록
/// 쌓여 마지막 구간이 엉뚱해진다.
///
/// ## 일시정지는 세지 않는다
///
/// 입력이 **세그먼트 목록**이라는 점이 곧 이 규칙이다. 시간차를 세그먼트 안에서만
/// 재므로 멈춰 있던 사이는 자연히 빠진다. 거리도 마찬가지다 — 멈춘 동안 차로
/// 이동했다면 그 선은 애초에 이어지지 않는다(`RunSessionController.track` 참조).
abstract final class SplitCalculator {
  const SplitCalculator._();

  /// 구간 하나의 길이(미터). 정본 S16.5가 1km 단위로 그린다.
  static const splitMeters = 1000.0;

  /// [segments]를 [splitMeters]씩 끊는다. 좌표가 모자라면 빈 목록이다.
  ///
  /// 마지막에 남은 자투리는 `isPartial`인 구간으로 붙는다. 버리면 화면의 총
  /// 거리와 구간 합계가 어긋난다.
  static List<RunSplit> from(List<List<GeoPoint>> segments) {
    final splits = <RunSplit>[];

    // 아직 1km를 채우지 못하고 넘어온 몫.
    var carriedMeters = 0.0;
    var carriedTime = Duration.zero;

    for (final segment in segments) {
      for (var i = 1; i < segment.length; i++) {
        final from = segment[i - 1];
        final to = segment[i];

        var legMeters = from.distanceTo(to);
        var legTime = to.recordedAt.difference(from.recordedAt);

        // 제자리이거나 시계가 거꾸로 간 다리는 건너뛴다. 비율로 나눌 때
        // 0으로 나누게 되고, 음수 시간은 페이스를 통째로 망친다.
        if (legMeters <= 0 || legTime.isNegative) continue;

        // 한 다리가 두 개 이상의 경계를 넘을 수도 있다 — 신호가 오래 끊겼다가
        // 멀리서 다시 잡히면 그렇다.
        while (carriedMeters + legMeters >= splitMeters) {
          final needed = splitMeters - carriedMeters;
          final share = legTime * (needed / legMeters);

          splits.add(
            RunSplit(
              index: splits.length + 1,
              distanceMeters: splitMeters,
              duration: carriedTime + share,
              isPartial: false,
            ),
          );

          legMeters -= needed;
          legTime -= share;
          carriedMeters = 0;
          carriedTime = Duration.zero;
        }

        carriedMeters += legMeters;
        carriedTime += legTime;
      }
    }

    if (carriedMeters > 0) {
      splits.add(
        RunSplit(
          index: splits.length + 1,
          distanceMeters: carriedMeters,
          duration: carriedTime,
          isPartial: true,
        ),
      );
    }

    return splits;
  }
}
