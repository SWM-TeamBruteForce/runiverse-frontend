import 'package:flutter/animation.dart';
import 'package:flutter/physics.dart';

/// 모션 토큰 — 디자인 시스템 v1.1 §4-3.
///
/// `Duration(milliseconds: 200)`이나 `Curves.easeOut` 대신 여기 있는 값을 쓴다.
/// 화면마다 다른 속도를 쓰면 앱이 들쭉날쭉해 보인다.
///
/// ## CSS 이징을 Flutter로 옮기는 법
///
/// 문서는 `cubic-bezier(x1,y1,x2,y2)`로 적혀 있고 Flutter는 [Cubic]이 같은 순서를 받는다.
/// 그대로 옮겨 적으면 된다 — `cubic-bezier(.2,0,0,1)` → `Cubic(0.2, 0, 0, 1)`.
///
/// ## 햅틱은 모션과 함께 간다
///
/// 카운트다운 3-2-1(숫자가 바뀔 때마다) · 색 리빌 피크 · 매칭 확정 토스트.
/// **음소거 상태에서도 햅틱은 유지한다.** 끄는 것은 음성뿐이다.
abstract final class AppMotion {
  // ── 이징 ─────────────────────────────────────────────────────

  /// 표준 이징. 빠르게 출발해 부드럽게 멈춘다.
  static const easeStandard = Cubic(0.2, 0, 0, 1);

  /// 느린 전환용. 끝을 조금 더 길게 끈다.
  static const easeSlow = Cubic(0.2, 0, 0.2, 1);

  /// 빛이 번지는 느낌. 초반에 확 퍼지고 길게 잦아든다.
  /// 색 리빌과 토스트 드롭이 이 곡선을 공유한다.
  static const easeBloom = Cubic(0.16, 1, 0.3, 1);

  // ── 지속 시간 ────────────────────────────────────────────────

  /// 120ms — 탭 피드백·토글·칩 선택. 즉각 반응해야 하는 것들.
  static const fast = Duration(milliseconds: 120);

  /// 200ms — 화면 전환·시트 등장.
  static const base = Duration(milliseconds: 200);

  /// 320ms — 매칭 러너 입장(페이드+스케일업), 진행률 순위 스위칭, 페이지 슬라이드.
  static const slow = Duration(milliseconds: 320);

  /// 320ms — 인앱 토스트 상단 슬라이드다운. [slow]와 길이는 같지만
  /// [easeBloom]과 짝지어 쓰는 것이 달라 별도 토큰으로 둔다.
  static const drop = Duration(milliseconds: 320);

  /// 1000ms — 색 리빌 번짐. 문서가 정한 범위는 800~1200ms다.
  /// 연출 비중이 큰 곳(S04.5 시그니처 리빌, S14 컬러 리빌)은 [revealLong]을 쓴다.
  static const reveal = Duration(milliseconds: 1000);

  /// 1200ms — 리빌 범위의 상한.
  static const revealLong = Duration(milliseconds: 1200);

  // ── 스프링 ───────────────────────────────────────────────────

  /// spring(220, 24) — 카운트다운 숫자 스케일, 슬롯머신 전환.
  ///
  /// [Duration]이 아니라 물리 시뮬레이션이라 `AnimationController.animateWith`에
  /// [SpringSimulation]으로 넘긴다. `duration`에 넣을 수 없다.
  static const spring = SpringDescription(mass: 1, stiffness: 220, damping: 24);
}
