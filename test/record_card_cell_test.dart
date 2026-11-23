import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runiverse/core/strings/app_strings.dart';
import 'package:runiverse/core/theme/app_theme.dart';
import 'package:runiverse/core/widgets/profile_photo_image.dart';
import 'package:runiverse/features/record_card/domain/record_card.dart';
import 'package:runiverse/features/record_card/domain/record_card_activity.dart';
import 'package:runiverse/features/record_card/domain/record_card_visibility.dart';
import 'package:runiverse/features/record_card/domain/route_art.dart';
import 'package:runiverse/core/widgets/card_face.dart';
import 'package:runiverse/core/widgets/route_art_view.dart';
import 'package:runiverse/features/record_card/presentation/record_card_cell.dart';
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

RecordCard _card({
  required int id,
  List<RecordCardPhoto> photos = const [],
  RouteArt? route,
}) => RecordCard(
  id: 'card-$id',
  runningRecordId: id + 100,
  startedAt: DateTime(2026, 9, 2, 18, 54),
  activity: RecordCardActivity.daily,
  visibility: RecordCardVisibility.friends,
  reviewText: '회고',
  photos: photos,
  route: route ?? _route,
  distanceMeters: 5000,
  duration: const Duration(minutes: 30),
  averagePace: const Duration(minutes: 6),
  runners: const [],
);

Future<void> _pump(
  WidgetTester tester, {
  required List<RecordCard> cards,
  bool showDayNumber = true,
  bool hasUnwrittenRun = false,
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
            hasUnwrittenRun: hasUnwrittenRun,
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
            RecordCardPhoto(id: 'img-1', url: 'assets/images/onboarding_record.jpg'),
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

  testWidgets('⚠️ 경로도 사진도 없는 카드가 빈 날과 같아 보이면 안 된다', (tester) async {
    // 트레드밀이나 GPS를 못 받은 러닝은 경로가 비어 있다. 사진까지 없으면
    // 칸이 안 뛴 날과 픽셀 단위로 같아져, 쓴 카드를 달력에서 못 찾는다.
    await _pump(tester, cards: [_card(id: 1, route: RouteArt.empty)]);

    expect(find.byType(CardMarkDot), findsOneWidget);
  });

  testWidgets('⚠️ 뛰었는데 카드가 없는 칸에는 운동화가 선다', (tester) async {
    // 안 뛴 날과 눈으로 갈라져야 한다 — 날짜 숫자만 있는 칸이 둘을 함께
    // 뜻하면 카드를 쓸 수 있는 날을 사용자가 찾을 수 없다.
    await _pump(tester, cards: const [], hasUnwrittenRun: true);

    expect(find.byType(RunShoeMark), findsOneWidget);
    expect(find.text('2'), findsOneWidget);
  });

  testWidgets('⚠️ 카드가 있으면 운동화를 두지 않는다', (tester) async {
    // 카드를 쓴 날에 운동화가 겹치면 "아직 안 썼다"로 읽힌다.
    await _pump(tester, cards: [_card(id: 1)], hasUnwrittenRun: true);

    expect(find.byType(RunShoeMark), findsNothing);
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
        AppStrings.recordCardCellSemantics(day: DateTime(2026, 9, 2), count: 2),
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
        AppStrings.recordCardCellSemantics(day: DateTime(2026, 9, 2), count: 0),
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

  group('cardThumbnail', () {
    testWidgets('⚠️ 주소의 꼴마다 읽는 데가 다르다', (tester) async {
      // 올릴 엔드포인트가 없어 방금 만든 카드의 사진은 기기 안 임시 파일이다.
      // 이 분기가 없으면 `ProfilePhotoImage`가 파일 경로를 URL로 치고 받으려
      // 한다.
      late BuildContext captured;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(),
          home: Builder(
            builder: (context) {
              captured = context;
              return const SizedBox();
            },
          ),
        ),
      );

      expect(
        cardThumbnail(captured, 'assets/images/a.jpg'),
        isA<AssetImage>(),
        reason: 'Fake 목 데이터는 번들 에셋이다',
      );
      expect(
        cardThumbnail(captured, 'https://x.example/a.jpg?sig=1'),
        isA<ProfilePhotoImage>(),
        reason: '서명이 달라져도 경로가 같으면 다시 받지 않는다',
      );
      expect(
        cardThumbnail(captured, '/data/user/0/cache/cropped.jpg'),
        isA<FileImage>(),
        reason: '방금 잘라 둔, 아직 올리지 않은 사진이다',
      );
    });
  });
}
