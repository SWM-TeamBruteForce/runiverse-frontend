import 'package:flutter/painting.dart';

/// 타입 스케일 — 디자인 시스템 v1.1 §2.
///
/// **색을 넣지 않는다.** 색은 `context.appColors`가 담당한다.
/// 여기는 크기·웨이트·행간·숫자 표현만 정한다.
///
/// ## 행간 표기
///
/// 문서는 `64 / 68`(크기/행간)로 적혀 있는데 Flutter의 `height`는 배수다.
/// 그래서 `68 / 64`처럼 나눗셈을 그대로 남겨 문서와 대조할 수 있게 했다.
///
/// ## 러닝 수치의 tabular
///
/// `metric` 3종에는 `FontFeature.tabularFigures()`가 들어 있다.
/// 이게 없으면 페이스·시간이 갱신될 때마다 숫자 폭이 달라져 자릿수가 흔들리고,
/// 달리면서는 읽을 수 없다.
///
/// ⚠️ 폰트가 `tnum`을 지원하지 않으면 Flutter는 **에러도 경고도 없이 무시한다.**
/// Pretendard는 2026-07-31에 OTF 바이너리에서 태그 존재를 확인했다.
abstract final class AppTypography {
  static const fontFamily = 'Pretendard';

  /// 러닝 수치 전용. 숫자 폭을 고정한다.
  static const _tabular = <FontFeature>[FontFeature.tabularFigures()];

  // ── 러닝 수치 ────────────────────────────────────────────────
  //
  // 글랜서블 규칙(C3): 러닝 중 화면(S11~S13)의 핵심 수치는 hero/lg만 쓴다.
  // 보조 지표는 md 이상, 라벨은 bodyLg 이상.

  /// 64/68 · 800 — 러닝 중 페이스 1강(S13), 로비 카운트다운(S10)
  static const metricHero = TextStyle(
    fontFamily: fontFamily,
    fontSize: 64,
    height: 68 / 64,
    fontWeight: FontWeight.w800,
    fontFeatures: _tabular,
  );

  /// 44/48 · 800 — 홈 확정 카운트다운(S05), 종료 요약
  static const metricLg = TextStyle(
    fontFamily: fontFamily,
    fontSize: 44,
    height: 48 / 44,
    fontWeight: FontWeight.w800,
    fontFeatures: _tabular,
  );

  /// 28/32 · 700 — 대시보드 수치, 4약 지표
  static const metricMd = TextStyle(
    fontFamily: fontFamily,
    fontSize: 28,
    height: 32 / 28,
    fontWeight: FontWeight.w700,
    fontFeatures: _tabular,
  );

  // ── 제목 ─────────────────────────────────────────────────────

  /// 32/40 · 700 — 화면 대형 타이틀
  static const display = TextStyle(
    fontFamily: fontFamily,
    fontSize: 32,
    height: 40 / 32,
    fontWeight: FontWeight.w700,
  );

  /// 26/34 · 700 — 섹션 헤드
  static const h1 = TextStyle(
    fontFamily: fontFamily,
    fontSize: 26,
    height: 34 / 26,
    fontWeight: FontWeight.w700,
  );

  /// 22/30 · 600 — 카드 타이틀, 프로필 대시보드 수치
  static const h2 = TextStyle(
    fontFamily: fontFamily,
    fontSize: 22,
    height: 30 / 22,
    fontWeight: FontWeight.w600,
  );

  /// 18/26 · 600 — 서브 헤드, 화면 헤더
  static const h3 = TextStyle(
    fontFamily: fontFamily,
    fontSize: 18,
    height: 26 / 18,
    fontWeight: FontWeight.w600,
  );

  // ── 본문 ─────────────────────────────────────────────────────

  /// 17/26 · 400 — 주 본문. 러닝 화면 라벨의 크기 하한이다.
  /// 강조가 필요하면 `.copyWith(fontWeight: FontWeight.w500)`.
  static const bodyLg = TextStyle(
    fontFamily: fontFamily,
    fontSize: 17,
    height: 26 / 17,
    fontWeight: FontWeight.w400,
  );

  /// 15/22 · 400 — 기본 본문
  static const body = TextStyle(
    fontFamily: fontFamily,
    fontSize: 15,
    height: 22 / 15,
    fontWeight: FontWeight.w400,
  );

  /// 13/18 · 400 — 캡션·메타·배지.
  /// 강조가 필요하면 `.copyWith(fontWeight: FontWeight.w500)`.
  static const caption = TextStyle(
    fontFamily: fontFamily,
    fontSize: 13,
    height: 18 / 13,
    fontWeight: FontWeight.w400,
  );

  /// 11/14 · 500 — 인디케이터·오버라인·셰이드 번호
  static const micro = TextStyle(
    fontFamily: fontFamily,
    fontSize: 11,
    height: 14 / 11,
    fontWeight: FontWeight.w500,
  );
}
