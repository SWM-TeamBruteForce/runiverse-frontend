/// 파티원 한 명의 진행.
///
/// ## ⚠️ 본인은 오지 않는다
///
/// 서버가 본인에게는 보내지 않는다 — 본인 진행은 앱이 이미 계산해 화면에
/// 띄우고 있다. 그래서 이 값들은 **전부 남의 것**이다.
///
/// ## ⚠️ 이름도 사진도 없다
///
/// `userId`만 온다. 10초마다 인원수만큼 나가는 메시지라 presigned URL이 붙으면
/// payload가 커져서다. 표시 정보는 다른 곳에서 받아 `userId`로 맞춘다.
class RunProgress {
  const RunProgress({
    required this.userId,
    required this.distanceMeters,
    this.targetDistanceMeters,
    this.currentPaceSecondsPerKm,
    this.paused = false,
  });

  final String userId;

  /// **서버가 수신한 좌표로 누적한 값**이다.
  ///
  /// 앱이 화면에 띄우는 본인 거리와 미세하게 다를 수 있지만, 남의 화면에 쓰는
  /// 값이라 서버 기준으로 통일한다.
  final int distanceMeters;

  final int? targetDistanceMeters;

  /// 마지막 좌표의 값. 단말이 못 재면 `null`이다.
  final int? currentPaceSecondsPerKm;

  /// 멈춰 있는가.
  ///
  /// 이 값이 없으면 **멈춘 것과 느려진 것을 구분할 수 없다** — 화면에서 갑자기
  /// 뒤처진 것처럼 보인다.
  ///
  /// ⚠️ 서버가 `RUNNING_PAUSE`를 구현하기 전까지는 항상 `false`로 온다.
  final bool paused;

  /// 목표 대비 얼마나 왔는가. 0~1로 자른다.
  ///
  /// 목표를 모르면 `null`이다 — 임의의 값으로 막대를 그리면 거짓말이 된다.
  double? get ratio {
    final target = targetDistanceMeters;
    if (target == null || target <= 0) return null;
    final value = distanceMeters / target;
    return value > 1 ? 1 : value;
  }

  /// 몸통에서 읽는다. **읽을 수 없으면 `null`이다.**
  ///
  /// ⚠️ 던지지 않는다. 진행 통지 하나가 이상하다고 러닝을 끊을 수는 없다 —
  /// 다음 통지가 같은 사람의 최신값을 다시 실어 온다.
  static RunProgress? of(Map<String, dynamic> data) {
    final userId = data['userId'];
    final distance = data['distanceMeters'];
    if (userId is! String || distance is! int) return null;

    return RunProgress(
      userId: userId,
      distanceMeters: distance,
      targetDistanceMeters: _intOrNull(data['targetDistanceMeters']),
      currentPaceSecondsPerKm: _intOrNull(data['currentPaceSecondsPerKm']),
      paused: data['paused'] == true,
    );
  }

  static int? _intOrNull(Object? value) => value is int ? value : null;
}

/// 나와 어떤 상대 사이의 콤보.
class ComboPeer {
  const ComboPeer({
    required this.userId,
    required this.gapMeters,
    required this.comboCount,
    required this.maxComboCount,
  });

  final String userId;

  /// **누적 주행 거리의 차이**다. 좌표상 거리가 아니다 — 참가자들이 각자 다른
  /// 장소에서 뛴다.
  ///
  /// 양수면 상대가 앞, 음수면 뒤.
  final int gapMeters;

  /// 지금 이어지고 있는 콤보.
  ///
  /// ⚠️ **앱이 세지 않는다.** 서버가 콤보 시작 시각에서 계산한다 — 배치 도착
  /// 수로 세면 인원과 전송 빈도에 따라 값이 달라진다.
  final int comboCount;

  /// 이번 러닝에서 이 상대와 기록한 최고 콤보.
  final int maxComboCount;

  static ComboPeer? of(Object? wire) {
    if (wire is! Map) return null;
    final userId = wire['userId'];
    if (userId is! String) return null;

    return ComboPeer(
      userId: userId,
      gapMeters: wire['gapMeters'] is int ? wire['gapMeters'] as int : 0,
      comboCount: wire['comboCount'] is int ? wire['comboCount'] as int : 0,
      maxComboCount: wire['maxComboCount'] is int
          ? wire['maxComboCount'] as int
          : 0,
    );
  }
}

/// 콤보 통지 한 통.
///
/// ## ⚠️ 항상 전체 상태다
///
/// 콤보가 끊긴 상대는 **목록에서 빠진다.** 끊김을 알리는 별도 이벤트가 없어서,
/// 받으면 화면을 이 목록으로 통째로 갈아끼운다. 한 통을 놓쳐도 다음 통이
/// 현재 상태를 다시 실어 온다.
///
/// 아무와도 겹치지 않으면 [peers]는 빈 목록이다.
class RunCombo {
  const RunCombo(this.peers);

  final List<ComboPeer> peers;

  /// 몸통에서 읽는다. `peers`가 없으면 `null` — 빈 목록과 다르다.
  ///
  /// 빈 목록은 "아무와도 안 겹친다"는 사실이고, `null`은 "못 읽었다"다.
  /// 못 읽은 것을 빈 목록으로 읽으면 멀쩡한 콤보가 화면에서 사라진다.
  static RunCombo? of(Map<String, dynamic> data) {
    final peers = data['peers'];
    if (peers is! List) return null;
    return RunCombo([for (final peer in peers) ?ComboPeer.of(peer)]);
  }
}
