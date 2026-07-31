import 'package:flutter/painting.dart';

/// 코너 라운드 — 디자인 시스템 v1.1 §4-1.
///
/// `BorderRadius.circular(16)` 대신 `AppRadius.lg`를 쓴다.
abstract final class AppRadius {
  /// 8 — 칩·배지·작은 버튼
  static const sm = BorderRadius.all(Radius.circular(8));

  /// 12 — 입력 필드·보조 카드·스와치
  static const md = BorderRadius.all(Radius.circular(12));

  /// 16 — 기본 카드·시트 상단
  static const lg = BorderRadius.all(Radius.circular(16));

  /// 24 — 히어로 블록·바텀시트
  static const xl = BorderRadius.all(Radius.circular(24));

  /// 999 — 아바타·토글·프리셋 칩(pill).
  /// 실제로는 높이의 절반이면 충분하지만, 높이를 몰라도 되도록 큰 값을 쓴다.
  static const full = BorderRadius.all(Radius.circular(999));
}
