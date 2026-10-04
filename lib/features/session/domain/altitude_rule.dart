/// 기기가 준 고도를 믿을 수 있는가.
///
/// ## ⚠️ 안드로이드는 못 구하면 `0.0`을 준다
///
/// `geolocator`가 `altitude`를 못 채우면 `0.0`이 들어온다. 그것을 그대로
/// 보내면 **서버가 실제 고도로 보고 누적 상승을 계산한다** — 못 재는 기기는
/// 누적 경사가 0 m 가 되고, 간헐적으로 0이 섞이면 오히려 **부풀려진다.**
///
/// ⚠️ **기록은 저장한 뒤에 고치지 않는다.** 잘못 보낸 값은 그대로 남는다.
/// (📅 기록 탭 연동 가이드 3-2 · 이슈 `[기록 목록] 기간 조회 API 연동`)
///
/// ## ⚠️ `altitude == 0`만 보고 버리면 안 된다
///
/// **해발 0 m 인 곳이 실제로 있다** — 해안 산책로를 달린 기록을 통째로
/// 잃는다. 정확도를 함께 봐야 "못 쟀다"와 "정말 0 m"가 갈린다.
abstract final class AltitudeRule {
  const AltitudeRule._();

  /// 보낼 고도. 믿을 수 없으면 `null`이다.
  ///
  /// 서버는 `null`인 점을 고도 계산에서 뺀다 — 0으로 메우는 것과 다르다.
  static double? trusted({required double altitude, required double accuracy}) {
    // 정확도를 못 구한 것이다. 값이 얼마든 근거가 없다.
    if (accuracy < 0) return null;

    // ⚠️ 둘 다 정확히 0이면 **센서가 안 채운 것**이다. 진짜로 해발 0 m 인
    // 지점이라면 정확도가 0일 수 없다 — GPS 는 오차를 늘 함께 준다.
    if (altitude == 0.0 && accuracy == 0.0) return null;

    return altitude;
  }
}
