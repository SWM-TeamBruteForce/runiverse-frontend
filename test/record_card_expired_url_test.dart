import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runiverse/core/theme/app_theme.dart';
import 'package:runiverse/core/widgets/card_face.dart';
import 'package:runiverse/core/widgets/route_art_view.dart';
import 'package:runiverse/features/record_card/domain/route_art.dart';

/// 만료된 조회 URL (연동 가이드 7절).
///
/// 사진·썸네일·프로필 이미지·음악 주소는 **1시간** 뒤 만료된다. `403`이면 그
/// 주소를 준 API를 다시 불러 새 주소를 받는다.
void main() {
  /// 늘 깨지는 그림. 만료된 주소를 흉내낸다.
  ///
  /// `Image`가 못 받으면 `errorBuilder`가 불린다 — 403도 404도 같은 길이다.
  const broken = 'https://example.invalid/gone.jpg';

  const route = RouteArt(
    strokes: [
      [RoutePoint(0, 0), RoutePoint(1, 1)],
    ],
    aspect: 1,
  );

  Future<void> pump(
    WidgetTester tester, {
    required VoidCallback onExpired,
    String? url = broken,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(),
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 60,
              height: 100,
              child: CardFace(
                thumbnailUrl: url,
                route: route,
                onExpired: onExpired,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('⚠️ 못 받으면 한 번만 알린다', (tester) async {
    // 막지 않으면 **다시 받은 주소도 만료됐을 때 끝나지 않는 고리**가 된다 —
    // 새 주소로 또 403, 또 재조회.
    var calls = 0;
    await pump(tester, onExpired: () => calls++);

    // 여러 프레임을 더 그려도 한 번이다.
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }

    expect(calls, 1);
  });

  testWidgets('못 받은 자리는 선으로 떨어진다 — 칸이 비지 않는다', (tester) async {
    await pump(tester, onExpired: () {});

    expect(find.byType(RouteArtView), findsOneWidget);
  });

  testWidgets('⚠️ 주소가 아예 없으면 알리지 않는다 — 만료가 아니다', (tester) async {
    // 사진을 다 지운 카드다. 받을 것이 없으니 다시 받을 일도 없다.
    var calls = 0;
    await pump(tester, onExpired: () => calls++, url: null);

    expect(calls, 0);
    expect(find.byType(RouteArtView), findsOneWidget);
  });

  testWidgets('⚠️ 알리는 쪽을 안 두어도 터지지 않는다', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(),
        home: const Scaffold(
          body: Center(
            child: SizedBox(
              width: 60,
              height: 100,
              child: CardFace(thumbnailUrl: broken, route: route),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });
}
