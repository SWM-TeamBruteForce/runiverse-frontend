import 'package:runiverse/features/session/domain/geo_point.dart';

/// 버튼 없이 멈춘 구간을 가려낸다 — 1.1.0 가이드 2.3.
///
/// ## ⚠️ 버튼 일시정지와 다른 것이다
///
/// 신호 대기처럼 **버튼을 누르지 않고 멈춘 경우**다. 그때는 `RUNNING_PAUSE`를
/// 보내지 않고 좌표 수집·전송을 **그대로 이어 간다** — 서버가 좌표를 봐야
/// 정지 구간을 판정할 수 있어서다. 상대에게도 `PAUSED`로 가지 않는다.
///
/// 프론트가 할 일은 **화면의 시간·거리 누적을 같은 기준으로 맞추는 것**뿐이다.
/// 안 맞추면 서 있던 시간이 화면에 그대로 쌓여, 끝나고 받은 서버 기록과
/// 어긋난다 — 실제로 36분을 서 있던 러닝이 3km에 76분으로 찍혔다.
///
/// ## 판정
///
/// | 항목 | 기준 |
/// |---|---|
/// | 기준점 | 정지 여부를 재기 시작한 좌표 |
/// | 반경 | 새로 받은 좌표의 `accuracy`를 [minRadiusMeters]~[maxRadiusMeters]로 가둔 값 |
/// | `inside` | 기준점 반경 안에서 **마지막으로** 받은 좌표 |
/// | 멈췄다 | `inside` 시각 − 기준점 시각이 [stillFor] 이상 |
///
/// ⚠️ **반경을 좌표마다 다시 잰다.** 신호가 나쁜 곳에서는 가만히 서 있어도
/// 좌표가 10m씩 튄다. 고정 반경을 쓰면 그 튐이 "움직였다"가 되어 정지를
/// 영영 못 잡는다. 그렇다고 `accuracy`를 그대로 믿으면 100m짜리가 와서
/// 달리는 사람이 멈춘 것이 된다 — 그래서 양쪽을 자른다.
///
/// ## ⚠️ 빠져나가는 이동은 빼지 않는다
///
/// 반경 밖 좌표가 오면 **`inside` → 그 좌표의 이동은 정상 이동으로 센다.**
/// 그것까지 빼면 멈췄다 출발할 때마다 몇 미터씩 사라진다. 그리고 그 좌표가
/// 새 기준점이 된다.
class AutoPause {
  AutoPause({
    this.minRadiusMeters = 5,
    this.maxRadiusMeters = 8,
    this.stillFor = const Duration(seconds: 10),
  });

  /// 반경의 아래위. 가이드가 "`accuracyMeters`를 5~8m 범위로 제한한 값"이라 정했다.
  final double minRadiusMeters;
  final double maxRadiusMeters;

  /// 이만큼 반경 안에 머무르면 멈춘 것으로 본다.
  final Duration stillFor;

  /// 정지를 재기 시작한 좌표.
  GeoPoint? _anchor;

  /// 기준점 반경 안에서 마지막으로 받은 좌표.
  GeoPoint? _inside;

  /// 기준점 이후로 **세어 둔** 거리. 멈춤이 확정되면 이만큼 되돌린다.
  double _metersSinceAnchor = 0;

  var _stopped = false;

  /// 지금 멈춘 것으로 보는가.
  bool get stopped => _stopped;

  /// 좌표 하나를 넣고 **화면이 무엇을 할지** 받는다.
  AutoPauseStep add(GeoPoint point) {
    final anchor = _anchor;
    if (anchor == null) {
      _anchor = point;
      _inside = point;
      _metersSinceAnchor = 0;
      return const AutoPauseStep.counts();
    }

    final radius = point.accuracy.clamp(minRadiusMeters, maxRadiusMeters);
    final movedFromAnchor = anchor.distanceTo(point);

    // ── 반경 밖 ─────────────────────────────────────────────
    if (movedFromAnchor > radius) {
      // ⚠️ **빠져나가는 이동은 센다.** 빼면 멈췄다 출발할 때마다 몇 미터가
      // 사라진다. 그리고 여기가 새 기준점이다.
      _anchor = point;
      _inside = point;
      _metersSinceAnchor = 0;
      _stopped = false;
      return const AutoPauseStep.counts();
    }

    // ── 반경 안 ─────────────────────────────────────────────
    final previous = _inside ?? anchor;
    _inside = point;

    if (_stopped) {
      // 이미 멈춘 것으로 보고 있다. 더 되돌릴 것은 없다 — 세지 않았으니까.
      return const AutoPauseStep.frozen();
    }

    final still = point.recordedAt.difference(anchor.recordedAt);
    if (still < stillFor) {
      // ⚠️ **아직 모른다.** 10초를 못 채운 머무름은 신호 대기인지 그냥 느린
      // 구간인지 가를 수 없다. 일단 세어 두고, 멈춤으로 확정되면 그때
      // 통째로 되돌린다.
      _metersSinceAnchor += previous.distanceTo(point);
      return const AutoPauseStep.counts();
    }

    // ── 여기서 멈춤이 확정된다 ────────────────────────────────
    //
    // 기준점부터 지금까지 세어 둔 것을 되돌린다. 가이드가 "기준점부터
    // inside까지 이미 누적한 시간·거리도 제외"라고 적은 그것이다.
    _stopped = true;
    final rollback = _metersSinceAnchor;
    _metersSinceAnchor = 0;
    return AutoPauseStep._(
      counts: false,
      stopped: true,
      rollbackMeters: rollback,
      rollbackElapsed: still,
    );
  }

  /// 처음으로 되돌린다. 버튼으로 멈췄다 다시 갈 때 부른다 — 그 사이 좌표를
  /// 세션이 통째로 버리므로, 기준점을 들고 있으면 **엉뚱한 곳에서 잰다.**
  void reset() {
    _anchor = null;
    _inside = null;
    _metersSinceAnchor = 0;
    _stopped = false;
  }
}

/// [AutoPause.add]의 답. **화면이 이 좌표로 무엇을 할지**를 담는다.
class AutoPauseStep {
  const AutoPauseStep._({
    required this.counts,
    required this.stopped,
    this.rollbackMeters = 0,
    this.rollbackElapsed = Duration.zero,
  });

  /// 평소. 이 좌표까지의 이동을 센다.
  const AutoPauseStep.counts() : this._(counts: true, stopped: false);

  /// 멈춰 있는 동안. 세지 않고, 되돌릴 것도 없다.
  const AutoPauseStep.frozen() : this._(counts: false, stopped: true);

  /// 이 좌표까지의 이동을 거리·시간에 세는가.
  final bool counts;

  /// 넣고 난 뒤 멈춘 것으로 보는가. 화면의 시계를 세울지 가른다.
  final bool stopped;

  /// 지금 거리에서 빼야 할 미터. **멈춤이 확정되는 순간에만** 0보다 크다.
  final double rollbackMeters;

  /// 지금 시간에서 빼야 할 만큼. 같은 순간에만 0보다 크다.
  final Duration rollbackElapsed;
}
