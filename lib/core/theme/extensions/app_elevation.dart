import 'package:flutter/material.dart';

/// 기반 UI 그림자 — 디자인 시스템 v1.1 §4-2.
///
/// **면의 높이 위계만 표현하는 중립 그림자다.** 러닝 색 글로우(`AppGlow`)와 역할이 다르다.
/// 여기에는 색을 받는 API가 없다. 앱 크롬에 러닝 색이 새지 않게 하려는 의도다.
///
/// ## 다크에서는 그림자를 거의 쓰지 않는다
///
/// 다크 테마는 그림자 대신 **면 밝기 상승**으로 높이를 표현한다
/// (`bgSurface` → `bgElevated`). 그림자는 모달·바텀시트 같은 강한 분리에만 쓴다.
/// 그래서 다크의 [level1]은 빈 리스트다 — 배경색과 테두리로 이미 구분되기 때문이다.
@immutable
class AppElevation extends ThemeExtension<AppElevation> {
  const AppElevation({
    required this.level1,
    required this.level2,
    required this.level3,
  });

  /// 카드처럼 살짝 떠 있는 면. 다크에서는 면색+테두리로 대신하므로 비어 있다.
  final List<BoxShadow> level1;

  /// 팝오버·드롭다운.
  final List<BoxShadow> level2;

  /// 모달·바텀시트.
  final List<BoxShadow> level3;

  /// level0은 그림자가 없다. 면 색만으로 구분한다.
  static const List<BoxShadow> level0 = [];

  static const dark = AppElevation(
    level1: [],
    level2: [
      BoxShadow(color: Color(0x66000000), blurRadius: 16, offset: Offset(0, 4)),
    ],
    level3: [
      BoxShadow(
        color: Color(0x80000000),
        blurRadius: 40,
        offset: Offset(0, 12),
      ),
    ],
  );

  static const light = AppElevation(
    level1: [
      BoxShadow(color: Color(0x0F0F131A), blurRadius: 2, offset: Offset(0, 1)),
    ],
    level2: [
      BoxShadow(color: Color(0x1A0F131A), blurRadius: 12, offset: Offset(0, 4)),
    ],
    level3: [
      BoxShadow(
        color: Color(0x240F131A),
        blurRadius: 32,
        offset: Offset(0, 12),
      ),
    ],
  );

  @override
  AppElevation copyWith({
    List<BoxShadow>? level1,
    List<BoxShadow>? level2,
    List<BoxShadow>? level3,
  }) {
    return AppElevation(
      level1: level1 ?? this.level1,
      level2: level2 ?? this.level2,
      level3: level3 ?? this.level3,
    );
  }

  @override
  AppElevation lerp(covariant AppElevation? other, double t) {
    if (other == null) return this;
    return AppElevation(
      level1: BoxShadow.lerpList(level1, other.level1, t) ?? level1,
      level2: BoxShadow.lerpList(level2, other.level2, t) ?? level2,
      level3: BoxShadow.lerpList(level3, other.level3, t) ?? level3,
    );
  }
}

/// `context.appElevation.level2`로 그림자를 꺼낸다.
extension AppElevationContext on BuildContext {
  AppElevation get appElevation {
    final elevation = Theme.of(this).extension<AppElevation>();
    assert(
      elevation != null,
      'AppElevation이 ThemeData.extensions에 없다. '
      'MaterialApp의 theme/darkTheme으로 AppTheme.light()/dark()를 쓰고 있는지 확인한다.',
    );
    return elevation ?? AppElevation.dark;
  }
}
