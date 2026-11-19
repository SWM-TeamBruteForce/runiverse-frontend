import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runiverse/core/strings/app_strings.dart';
import 'package:runiverse/core/theme/app_theme.dart';
import 'package:runiverse/features/record_card/domain/edit_record_card.dart';
import 'package:runiverse/features/record_card/domain/music_generation.dart';
import 'package:runiverse/features/record_card/domain/new_record_card.dart';
import 'package:runiverse/features/record_card/domain/record_card.dart';
import 'package:runiverse/features/record_card/domain/record_card_activity.dart';
import 'package:runiverse/features/record_card/domain/record_card_visibility.dart';
import 'package:runiverse/features/record_card/domain/route_art.dart';
import 'package:runiverse/features/record_card/domain/record_card_repository.dart';
import 'package:runiverse/features/record_card/presentation/card_media_pager.dart';
import 'package:runiverse/features/record_card/presentation/music_strip.dart';
import 'package:runiverse/features/record_card/presentation/record_card_provider.dart';
import 'package:runiverse/features/record_card/presentation/card_detail_page.dart';
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
      latitude: 37.52,
      longitude: 127.03,
      recordedAt: DateTime(2026, 9, 2),
    ),
  ],
]);

RecordCard _card({int photos = 0}) => RecordCard(
  id: 7,
  runningRecordId: 107,
  startedAt: DateTime(2026, 9, 2, 18, 54),
  activity: RecordCardActivity.daily,
  visibility: RecordCardVisibility.friends,
  reviewText: '오늘은 퇴근 후 성수동에서 달렸다.',
  photos: [
    for (var i = 0; i < photos; i++)
      RecordCardPhoto(
        id: i,
        url: 'assets/images/sign_in_hero.png',
        caption: '사진 $i의 한마디',
      ),
  ],
  route: _route,
  distanceMeters: 5400,
  duration: const Duration(minutes: 28, seconds: 10),
  averagePace: const Duration(minutes: 5, seconds: 38),
  runners: const [
    CardRunner(userId: 'u-1', nickname: '동완러너'),
    CardRunner(userId: 'u-2', nickname: '바람'),
  ],
);

/// 지금 몇 번째 장인가.
int pageOf(WidgetTester tester) {
  final view = tester.widget<PageView>(find.byType(PageView));
  return (view.controller!.page ?? 0).round();
}

/// 음악만 답하는 저장소. **번호를 안 본다** — 상세가 어떤 카드를 들고 와도
/// 같은 상태를 준다.
class _MusicRepository implements RecordCardRepository {
  _MusicRepository(this.status);

  final MusicStatus status;

  var requests = 0;

  @override
  Future<MusicGeneration> musicOf(int cardId) async => status == MusicStatus.none
      ? MusicGeneration.none(cardId)
      : MusicGeneration(cardId: cardId, status: status, trackCount: 1);

  @override
  Future<MusicGeneration> requestMusic(int cardId) async {
    requests++;
    return MusicGeneration(
      cardId: cardId,
      status: MusicStatus.queued,
      trackCount: 1,
    );
  }

  /// 이 테스트는 **음악만** 본다. 불리면 테스트가 잘못 세워진 것이다.
  @override
  Future<List<RecordCard>> byDateRange({
    required DateTime from,
    required DateTime to,
  }) => throw UnsupportedError('이 테스트는 목록을 받지 않는다');

  @override
  Future<RecordCard> create(NewRecordCard card) =>
      throw UnsupportedError('이 테스트는 카드를 만들지 않는다');

  @override
  Future<RecordCard> update(EditRecordCard card) =>
      throw UnsupportedError('이 테스트는 카드를 고치지 않는다');

  @override
  Future<void> delete(int cardId) =>
      throw UnsupportedError('이 테스트는 카드를 지우지 않는다');
}

Future<void> _pump(
  WidgetTester tester, {
  int photos = 0,
  bool light = false,
  MusicStatus music = MusicStatus.succeeded,
  _MusicRepository? repository,
}) async {
  // ⚠️ 기본 테스트 화면(800×600)은 가로로 넓어 9:16 페이저가 화면보다 길어진다.
  // 아래 내용이 전부 밀려나 "안 보인다"로 떨어진다. 손전화 크기로 맞춘다.
  tester.view.physicalSize = const Size(412, 915);
  tester.view.devicePixelRatio = 1;
  // ⚠️ **시스템 여백도 넣는다.** 기본 테스트 화면에는 상태바도 제스처 바도
  // 없어서, "다 들어온다"가 기기에서만 거짓이 된다 — 실제로 그랬다.
  tester.view.padding = const FakeViewPadding(top: 38, bottom: 38);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPadding);

  // ⚠️ **`ProviderScope`가 필요하다.** 상세가 삭제 상태와 음악 상태를 본다.
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        recordCardRepositoryProvider.overrideWithValue(
          repository ?? _MusicRepository(music),
        ),
      ],
      child: MaterialApp(
        theme: light ? AppTheme.light() : AppTheme.dark(),
        home: CardDetailPage(card: _card(photos: photos)),
      ),
    ),
  );
  // 음악 상태가 한 프레임 뒤에 선다.
  await tester.pump();
}

void main() {
  testWidgets('첫 장은 경로 선 아트다', (tester) async {
    await _pump(tester, photos: 2);

    expect(find.byType(RouteArtView), findsOneWidget);
    expect(pageOf(tester), 0);
  });

  testWidgets('지표 셋과 회고가 보인다', (tester) async {
    await _pump(tester);

    // ⚠️ 단위까지 함께 본다. 숫자만 두면 `5.40`이 무엇인지 알 수 없다.
    expect(
      find.text('${AppStrings.kmFloor(5400)} ${AppStrings.runPartyUnitKm}'),
      findsOneWidget,
    );
    expect(
      find.text(
        '${AppStrings.recordRunDuration(const Duration(minutes: 5, seconds: 38))}'
        '${AppStrings.runPartyUnitPerKm}',
      ),
      findsOneWidget,
    );
    expect(find.text('오늘은 퇴근 후 성수동에서 달렸다.'), findsOneWidget);
  });

  testWidgets('⚠️ 한 화면에 기록·사진·메모가 다 들어온다', (tester) async {
    // 스크롤하지 않고도 회고까지 보여야 한다. 사진이 커서 아래가 밀려나기
    // 쉬운 자리라, 화면 높이로 못 박는다.
    await _pump(tester, photos: 2);

    final memo = find.text('오늘은 퇴근 후 성수동에서 달렸다.');
    expect(memo, findsOneWidget);
    expect(tester.getRect(memo).bottom, lessThanOrEqualTo(915));
  });

  testWidgets('날짜가 머리에 선다', (tester) async {
    await _pump(tester);

    expect(
      find.text(AppStrings.recordCardDateTitle(DateTime(2026, 9, 2))),
      findsOneWidget,
    );
  });

  testWidgets('⚠️ 유형은 두지 않는다 — 달력의 필터가 이미 말했다', (tester) async {
    await _pump(tester);

    expect(find.text(AppStrings.recordCardActivityDaily), findsNothing);
  });

  testWidgets('⚠️ 머리에는 기록만 둔다 — 러너 줄도 메모 라벨도 없다', (tester) async {
    await _pump(tester);

    expect(find.textContaining('함께 뛴 러너'), findsNothing);
    expect(find.text('러닝 메모'), findsNothing);
  });

  testWidgets('⚠️ 글자 자리는 하나다 — 경로 장은 회고, 사진 장은 그 사진의 캡션', (tester) async {
    await _pump(tester, photos: 2);

    expect(find.text('오늘은 퇴근 후 성수동에서 달렸다.'), findsOneWidget);
    expect(find.text('사진 0의 한마디'), findsNothing);

    await tester.drag(find.byType(PageView), const Offset(-400, 0));
    await tester.pumpAndSettle();

    // 사진에는 회고가 없다. 그 자리에 캡션이 대신 든다.
    expect(find.text('오늘은 퇴근 후 성수동에서 달렸다.'), findsNothing);
    expect(find.text('사진 0의 한마디'), findsOneWidget);
  });

  testWidgets('⚠️ 사진이 화면의 절반 남짓을 넘지 않는다 — 글이 밀려난다', (tester) async {
    await _pump(tester, photos: 2);

    expect(
      tester.getSize(find.byType(PageView)).height,
      lessThanOrEqualTo(915 * 0.55),
    );
  });

  testWidgets('⚠️ 점은 사진과 글 사이에 선다', (tester) async {
    await _pump(tester, photos: 2);

    final dots = tester.getRect(find.byType(CardPageDots));
    final pager = tester.getRect(find.byType(PageView));
    final text = tester.getRect(find.text('오늘은 퇴근 후 성수동에서 달렸다.'));

    expect(dots.top, greaterThanOrEqualTo(pager.bottom));
    expect(dots.bottom, lessThanOrEqualTo(text.top));
  });

  testWidgets('⚠️ 사진이 없으면 한 장뿐이고 진행 막대도 안 뜬다', (tester) async {
    await _pump(tester);

    expect(find.byType(CardPageDots), findsNothing);
  });

  testWidgets('사진이 5장이면 막대가 6개다', (tester) async {
    await _pump(tester, photos: 5);

    final bars = tester.widget<CardPageDots>(find.byType(CardPageDots));
    expect(bars.count, 6);
  });

  testWidgets('사진 장에서는 캡션이 보인다', (tester) async {
    await _pump(tester, photos: 2);

    await tester.drag(find.byType(PageView), const Offset(-400, 0));
    await tester.pumpAndSettle();

    expect(find.text('사진 0의 한마디'), findsOneWidget);
  });

  testWidgets('⚠️ 그 장의 길이가 지나면 다음 장으로 넘어간다', (tester) async {
    await _pump(tester, photos: 2);

    // 첫 장(경로)은 기본 음악 길이만큼 선다.
    await tester.pump(MusicGeneration.baseDuration);
    await tester.pumpAndSettle();
    expect(pageOf(tester), 1);

    // 사진 장은 사진 음악 길이만큼.
    await tester.pump(MusicGeneration.photoDuration);
    await tester.pumpAndSettle();
    expect(pageOf(tester), 2);
  });

  testWidgets('⚠️ 마지막 장에서는 멈춘다 — 처음으로 되돌아가지 않는다', (tester) async {
    await _pump(tester, photos: 1);

    await tester.pump(MusicGeneration.baseDuration);
    await tester.pumpAndSettle();
    expect(pageOf(tester), 1);

    await tester.pump(MusicGeneration.photoDuration * 3);
    await tester.pumpAndSettle();
    expect(pageOf(tester), 1);
  });

  testWidgets('⚠️ 사진이 없으면 아예 넘어가지 않는다', (tester) async {
    await _pump(tester);

    await tester.pump(MusicGeneration.baseDuration * 2);
    await tester.pumpAndSettle();
    expect(pageOf(tester), 0);
  });

  testWidgets('탭하면 멈추고 다시 탭하면 이어간다', (tester) async {
    await _pump(tester, photos: 2);

    await tester.tap(find.byType(PageView));
    await tester.pump();
    await tester.pump(MusicGeneration.baseDuration * 2);
    await tester.pumpAndSettle();
    expect(pageOf(tester), 0, reason: '멈췄는데 넘어갔다');

    await tester.tap(find.byType(PageView));
    await tester.pump();
    await tester.pump(MusicGeneration.baseDuration);
    await tester.pumpAndSettle();
    expect(pageOf(tester), 1);
  });

  testWidgets('⚠️ 손으로 밀면 그 장부터 다시 센다', (tester) async {
    await _pump(tester, photos: 2);

    // 첫 장에서 한참 기다리다가 손으로 넘긴다.
    await tester.pump(MusicGeneration.baseDuration - const Duration(seconds: 2));
    await tester.drag(find.byType(PageView), const Offset(-400, 0));
    await tester.pumpAndSettle();
    expect(pageOf(tester), 1);

    // 남은 2초로 넘어가면 안 된다. 사진 장의 길이를 새로 센다.
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
    expect(pageOf(tester), 1);

    await tester.pump(MusicGeneration.photoDuration);
    await tester.pumpAndSettle();
    expect(pageOf(tester), 2);
  });

  testWidgets('⚠️ 스크린리더가 몇 번째 장인지 읽는다', (tester) async {
    final handle = tester.ensureSemantics();
    await _pump(tester, photos: 2);

    expect(
      find.bySemanticsLabel(
        AppStrings.recordCardPageSemantics(index: 1, count: 3),
      ),
      findsOne,
    );

    handle.dispose();
  });

  testWidgets('라이트 테마에서도 그려진다', (tester) async {
    await _pump(tester, photos: 2, light: true);

    expect(tester.takeException(), isNull);
  });

  // ── 음악 줄 (묶음 5) ──────────────────────────────────────────

  testWidgets('상세에 음악 줄이 선다', (tester) async {
    await _pump(tester, photos: 2);

    expect(find.byType(MusicStrip), findsOneWidget);
  });

  testWidgets('⚠️ 음악 줄은 글 아래에 선다 — 사진을 밀어내지 않는다', (tester) async {
    await _pump(tester, photos: 2);

    final memo = tester.getRect(find.text('오늘은 퇴근 후 성수동에서 달렸다.'));
    final strip = tester.getRect(find.byType(MusicStrip));

    expect(strip.top, greaterThanOrEqualTo(memo.bottom));
  });

  testWidgets('⚠️ 줄의 멈춤을 누르면 책이 안 넘어간다', (tester) async {
    await _pump(tester, photos: 2);

    await tester.tap(find.text(AppStrings.recordCardMusicPause));
    await tester.pump();

    await tester.pump(MusicGeneration.baseDuration * 2);
    await tester.pumpAndSettle();

    expect(pageOf(tester), 0, reason: '멈췄는데 넘어갔다');
  });

  testWidgets('⚠️ 다시 누르면 이어간다', (tester) async {
    await _pump(tester, photos: 2);

    await tester.tap(find.text(AppStrings.recordCardMusicPause));
    await tester.pump();
    await tester.tap(find.text(AppStrings.recordCardMusicPlay));
    await tester.pump();

    await tester.pump(MusicGeneration.baseDuration);
    await tester.pumpAndSettle();

    expect(pageOf(tester), 1);
  });

  testWidgets('⚠️ 사진을 탭해 멈추면 줄도 재생으로 바뀐다 — 둘이 한 상태다', (tester) async {
    await _pump(tester, photos: 2);
    expect(find.text(AppStrings.recordCardMusicPause), findsOneWidget);

    await tester.tap(find.byType(PageView));
    await tester.pump();

    expect(find.text(AppStrings.recordCardMusicPlay), findsOneWidget);
  });

  testWidgets('⚠️ 음악이 없는 카드도 책은 넘어간다 — 음악은 길이의 출처일 뿐이다', (
    tester,
  ) async {
    await _pump(tester, photos: 2, music: MusicStatus.none);
    expect(find.text(AppStrings.recordCardMusicCreate), findsOneWidget);

    await tester.pump(MusicGeneration.baseDuration);
    await tester.pumpAndSettle();

    expect(pageOf(tester), 1);
  });

  testWidgets('⚠️ 만드는 중인 카드도 책은 넘어간다', (tester) async {
    await _pump(tester, photos: 2, music: MusicStatus.processing);

    await tester.pump(MusicGeneration.baseDuration);
    await tester.pumpAndSettle();

    expect(pageOf(tester), 1);
  });
}
