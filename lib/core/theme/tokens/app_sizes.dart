/// 크기 토큰 — 디자인 시스템 v1.1 §3-2, §3-3.
///
/// 설계 기준 캔버스는 412×892(Android)다.
///
/// ## 터치 타깃을 만드는 법
///
/// v1 구현에서 가장 반복된 결함이 44px 미달이었고, 원인은 전부 같았다:
/// **수직 패딩만 주고 최소 높이를 두지 않아** 박스가 글자 높이로 접히는 것.
///
/// ```dart
/// // ✅ 최소 높이를 보장한다
/// ConstrainedBox(
///   constraints: const BoxConstraints(minHeight: AppSizes.touchDefault),
///   child: ...,
/// )
///
/// // ❌ 13px 캡션에 수직 패딩 5px → 박스가 23px가 된다
/// Padding(padding: EdgeInsets.symmetric(vertical: 5), child: Text(...))
/// ```
///
/// 아이콘 버튼은 44×44 히트 박스를 유지하고 글리프만 17~24px로 줄인다.
/// 히트 박스를 줄여서 밀도를 확보하지 않는다 — 밀도는 바깥 `gap`과 `padding`에서 회수한다.
/// "보조 액션이라 작게"는 예외 사유가 아니다.
abstract final class AppSizes {
  /// 44 — 일반 화면의 최소 터치 타깃.
  static const touchDefault = 44.0;

  /// 56 — 러닝 중 화면(S11~S13)의 최소 터치 타깃.
  /// 달리면서 조작하므로 조준 정확도가 떨어진다.
  static const touchRunning = 56.0;
}
