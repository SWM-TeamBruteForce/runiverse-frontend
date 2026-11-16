import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runiverse/core/strings/app_strings.dart';
import 'package:runiverse/core/theme/app_theme.dart';
import 'package:runiverse/features/record_card/domain/record_card.dart';
import 'package:runiverse/features/record_card/domain/record_card_activity.dart';
import 'package:runiverse/features/record_card/domain/record_card_visibility.dart';
import 'package:runiverse/features/record_card/domain/route_art.dart';
import 'package:runiverse/features/record_card/presentation/record_card_cell.dart';
import 'package:runiverse/features/record_card/presentation/route_art_view.dart';
import 'package:runiverse/features/session/domain/geo_point.dart';

final _route = normalizeRoute([
  [
    GeoPoint(
      latitude: 37.50,
      longitude: 127.00,
      recordedAt: DateTime(2026, 9, 2),
    ),
    GeoPoint(
      latitude: 37.51,
      longitude: 127.01,
      recordedAt: DateTime(2026, 9, 2),
    ),
  ],
]);

RecordCard _card({required int id, List<RecordCardPhoto> photos = const []}) =>
    RecordCard(
      id: id,
      runningRecordId: id + 100,
      startedAt: DateTime(2026, 9, 2, 18, 54),
      activity: RecordCardActivity.daily,
      visibility: RecordCardVisibility.friends,
      reviewText: '회고',
      photos: photos,
      route: _route,
      distanceMeters: 5000,
      duration: const Duration(minutes: 30),
      averagePace: const Duration(minutes: 6),
      runners: const [],
    );

Future<void> _pump(
  WidgetTester tester, {
  required List<RecordCard> cards,
  bool showDayNumber = true,
  bool light = false,
  VoidCallback? onTap,
}) => tester.pumpWidget(
  MaterialApp(
    theme: light ? AppTheme.light() : AppTheme.dark(),
    home: Scaffold(
      body: Center(
        child: SizedBox(
          width: 43,
          height: 62,
          child: RecordCardCell(
            day: DateTime(2026, 9, 2),
            cards: cards,
            showDayNumber: showDayNumber,
            onTap: onTap,
          ),
        ),
      ),
    ),
  ),
);

void main() {
  testWidgets('사진이 있으면 썸네일을 그린다', (tester) async {
    await _pump(
      tester,
      cards: [
        _card(
          id: 1,
          photos: const [
            RecordCardPhoto(id: 1, url: 'assets/images/onboarding_record.jpg'),
          ],
        ),
      ],
    );

    expect(find.byType(Image), findsOneWidget);
    expect(find.byType(RouteArtView), findsNothing);
  });

  testWidgets('⚠️ 사진이 없으면 선 아트를 그린다 — 빈 날처럼 보이면 안 된다', (tester) async {
    await _pump(tester, cards: [_card(id: 1)]);

    expect(find.byType(RouteArtView), findsOneWidget);
  });

  testWidgets('카드가 없는 날은 날짜만 있다', (tester) async {
    await _pump(tester, cards: const []);

    expect(find.byType(RouteArtView), findsNothing);
    expect(find.byType(Image), findsNothing);
    expect(find.text('2'), findsOneWidget);
  });

  testWidgets('⚠️ 하루에 둘이면 개수 배지가 뜬다', (tester) async {
    await _pump(tester, cards: [_card(id: 1), _card(id: 2)]);

    expect(find.text('2'), findsWidgets);
  });

  testWidgets('하나면 배지가 없다', (tester) async {
    await _pump(tester, cards: [_card(id: 1)]);

    // 날짜 숫자 '2' 하나뿐이다. 배지가 뜨면 '1'이 보인다.
    expect(find.text('1'), findsNothing);
  });

  testWidgets('⚠️ showDayNumber가 false면 날짜를 안 그린다 — 분기 보기는 칸이 작다', (
    tester,
  ) async {
    await _pump(tester, cards: [_card(id: 1)], showDayNumber: false);

    expect(find.text('2'), findsNothing);
    expect(find.byType(RouteArtView), findsOneWidget);
  });

  testWidgets('누르면 onTap이 불린다', (tester) async {
    var tapped = 0;
    await _pump(tester, cards: [_card(id: 1)], onTap: () => tapped++);

    await tester.tap(find.byType(RecordCardCell));
    expect(tapped, 1);
  });

  testWidgets('⚠️ 스크린리더가 날짜와 장수를 읽는다', (tester) async {
    final handle = tester.ensureSemantics();
    await _pump(tester, cards: [_card(id: 1), _card(id: 2)]);

    expect(
      find.bySemanticsLabel(
        AppStrings.recordCardCellSemantics(
          day: DateTime(2026, 9, 2),
          count: 2,
        ),
      ),
      findsOne,
    );

    handle.dispose();
  });

  testWidgets('⚠️ 카드 없는 날도 읽을 말이 있다', (tester) async {
    final handle = tester.ensureSemantics();
    await _pump(tester, cards: const []);

    expect(
      find.bySemanticsLabel(
        AppStrings.recordCardCellSemantics(
          day: DateTime(2026, 9, 2),
          count: 0,
        ),
      ),
      findsOne,
    );

    handle.dispose();
  });

  testWidgets('라이트 테마에서도 그려진다', (tester) async {
    await _pump(tester, cards: [_card(id: 1)], light: true);

    expect(tester.takeException(), isNull);
    expect(find.byType(RouteArtView), findsOneWidget);
  });
}
