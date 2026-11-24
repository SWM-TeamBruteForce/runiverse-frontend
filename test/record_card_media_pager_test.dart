import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runiverse/core/theme/app_theme.dart';
import 'package:runiverse/features/record_card/domain/record_card.dart';
import 'package:runiverse/features/record_card/domain/record_card_activity.dart';
import 'package:runiverse/features/record_card/domain/record_card_visibility.dart';
import 'package:runiverse/features/record_card/domain/route_art.dart';
import 'package:runiverse/features/record_card/presentation/card_media_pager.dart';

/// 포토북 페이저 — 경로 한 장 다음에 사진들 (설계 6-5).
void main() {
  /// 사진 [photos]장짜리 카드.
  RecordCard card({required int photos}) => RecordCard(
    id: 'card-1',
    runningRecordId: 123,
    startedAt: DateTime(2026, 11, 24, 4, 28),
    activity: RecordCardActivity.daily,
    visibility: RecordCardVisibility.friends,
    reviewText: '좋았다',
    route: RouteArt.empty,
    distanceMeters: 5000,
    duration: const Duration(minutes: 30),
    averagePace: const Duration(minutes: 6),
    runners: const [],
    isMine: true,
    photos: [
      for (var i = 0; i < photos; i++)
        RecordCardPhoto(
          id: 'image-$i',
          url: 'https://example.invalid/$i.jpg',
          caption: '사진 $i',
        ),
    ],
  );

  Future<void> pump(WidgetTester tester, RecordCard value) => tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(
        theme: AppTheme.dark(),
        home: Scaffold(
          body: CardMediaPager(
            card: value,
            playing: false,
            onPlayingChanged: (_) {},
            onPageChanged: (_) {},
          ),
        ),
      ),
    ),
  );

  testWidgets('⚠️ 보던 장의 사진이 수정으로 사라져도 터지지 않는다', (tester) async {
    // 수정에서 사진을 지우면 상세가 다시 읽혀 장 수가 줄어든다. 보고 있던
    // 자리가 범위를 벗어나면 상세가 통째로 빨간 화면이 된다 — 2026-11-24
    // 에뮬레이터에서 실제로 그렇게 터졌다(RangeError).
    await pump(tester, card(photos: 2));
    // 마지막 사진 장으로 간다.
    await tester.drag(find.byType(PageView), const Offset(-600, 0));
    await tester.pumpAndSettle();
    await tester.drag(find.byType(PageView), const Offset(-600, 0));
    await tester.pumpAndSettle();

    await pump(tester, card(photos: 1));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });

  testWidgets('⚠️ 사진을 전부 지우면 경로 장만 남는다', (tester) async {
    await pump(tester, card(photos: 1));
    await tester.drag(find.byType(PageView), const Offset(-600, 0));
    await tester.pumpAndSettle();

    await pump(tester, card(photos: 0));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    // 장이 하나뿐이면 점을 두지 않는다 — 알려 주는 것이 없다.
    expect(find.byType(CardPageDots), findsNothing);
  });
}
