import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:runiverse/core/strings/app_strings.dart';
import 'package:runiverse/core/theme/app_theme.dart';
import 'package:runiverse/features/record_card/domain/edit_record_card.dart';
import 'package:runiverse/features/record_card/domain/card_music.dart';
import 'package:runiverse/features/record_card/domain/new_record_card.dart';
import 'package:runiverse/features/record_card/domain/composable_record.dart';
import 'package:runiverse/features/record_card/domain/record_card.dart';
import 'package:runiverse/features/record_card/domain/record_card_list_item.dart';
import 'package:runiverse/features/record_card/domain/record_card_activity.dart';
import 'package:runiverse/features/record_card/domain/record_card_visibility.dart';
import 'package:runiverse/features/record_card/domain/route_art.dart';
import 'package:runiverse/features/record_card/domain/record_card_repository.dart';
import 'package:runiverse/features/record_card/presentation/card_media_pager.dart';
import 'package:runiverse/features/record_card/presentation/music_strip.dart';
import 'package:runiverse/features/record_card/presentation/record_card_provider.dart';
import 'package:runiverse/features/record_card/presentation/card_detail_page.dart';
import 'package:runiverse/core/widgets/route_art_view.dart';
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

RecordCard _card({int photos = 0, bool mine = true}) => RecordCard(
  id: 'card-7',
  runningRecordId: 107,
  startedAt: DateTime(2026, 9, 2, 18, 54),
  activity: RecordCardActivity.daily,
  visibility: RecordCardVisibility.friends,
  reviewText: '오늘은 퇴근 후 성수동에서 달렸다.',
  photos: [
    for (var i = 0; i < photos; i++)
      RecordCardPhoto(
        id: 'img-$i',
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
  // ⚠️ **서버가 답하는 값이다**(8-1의 `isMine`). 묶음 6까지는 라우트 쿼리로
  // 들려 보냈다.
  isMine: mine,
);

/// 지금 몇 번째 장인가.
int pageOf(WidgetTester tester) {
  final view = tester.widget<PageView>(find.byType(PageView));
  return (view.controller!.page ?? 0).round();
}

/// 음악만 답하는 저장소. **번호를 안 본다** — 상세가 어떤 카드를 들고 와도
/// 같은 상태를 준다.
class _MusicRepository implements RecordCardRepository {
  /// 이 테스트는 프로필 그리드를 그리지 않는다. 불리면 테스트가 잘못 세워진
  /// 것이다.
  @override
  Future<RecordCardListPage> cardsOf({
    required String userId,
    int? limit,
    String? cursor,
  }) => throw UnsupportedError('이 테스트는 사람별 카드를 묻지 않는다');

  _MusicRepository(this.status, {this.card});

  /// 모든 곡에 심을 상태. `null`이면 **서버가 아직 곡을 안 준 것**이다.
  final MusicStatus? status;

  /// 상세가 번호로 물으면 돌려줄 카드. `null`이면 `404`를 흉내낸다.
  final RecordCard? card;

  /// 몇 번 다시 만들어 달라고 했나.
  var requests = 0;

  @override
  Future<void> retryMusic(String cardId) async {
    requests++;
  }

  /// 이 테스트는 **음악만** 본다. 불리면 테스트가 잘못 세워진 것이다.
  @override
  Future<List<ComposableRecord>> runsInRange({
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
  Future<void> delete(String cardId) =>
      throw UnsupportedError('이 테스트는 카드를 지우지 않는다');

  /// ⚠️ **번호를 안 본다.** 어떤 번호로 물어도 세워 둔 카드를 준다 — 이
  /// 테스트가 보는 것은 음악과 소유자 표시다.
  @override
  Future<RecordCard> detailOf(String cardId) async {
    final found = card;
    if (found == null) {
      throw const RecordCardException(RecordCardFailure.notFound);
    }
    return found;
  }

  /// 곡을 심은 카드. 상태를 안 주면 곡이 아예 없는 카드다.
  static RecordCard withMusic(RecordCard card, MusicStatus? status) {
    final music = status == null
        ? null
        : CardMusic(
            status: status,
            url: status == MusicStatus.completed ? 'https://x/m.m4a' : null,
          );
    return RecordCard(
      id: card.id,
      runningRecordId: card.runningRecordId,
      startedAt: card.startedAt,
      activity: card.activity,
      visibility: card.visibility,
      reviewText: card.reviewText,
      photos: [
        for (final photo in card.photos)
          RecordCardPhoto(
            id: photo.id,
            url: photo.url,
            caption: photo.caption,
            music: music,
          ),
      ],
      route: card.route,
      distanceMeters: card.distanceMeters,
      duration: card.duration,
      averagePace: card.averagePace,
      runners: card.runners,
      isMine: card.isMine,
      baseMusic: music,
    );
  }
}

Future<void> _pump(
  WidgetTester tester, {
  int photos = 0,
  bool light = false,
  MusicStatus? music = MusicStatus.completed,
  _MusicRepository? repository,
  bool mine = true,
}) async {
  final card = _MusicRepository.withMusic(
    _card(photos: photos, mine: mine),
    music,
  );
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
          repository ?? _MusicRepository(music, card: card),
        ),
      ],
      child: MaterialApp(
        theme: light ? AppTheme.light() : AppTheme.dark(),
        home: const CardDetailPage(cardId: 'card-7'),
      ),
    ),
  );
  // ⚠️ **두 번 민다.** 첫 프레임은 카드를 받아 오는 중이고, 음악 상태는 그
  // 다음에 선다.
  await tester.pump();
  await tester.pump();
}

void main() {
  /// 번호로 받아 오는 세 갈래 (묶음 7 작업 4).
  group('받아 오기', () {
    testWidgets('⚠️ 받아 오는 중에는 ⋮를 그리지 않는다', (tester) async {
      // 내 카드인지 **서버가 답한다.** 받기 전에 그리면 남의 카드에도 수정
      // 버튼이 한 프레임 섰다 사라진다.
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            recordCardRepositoryProvider.overrideWithValue(
              _MusicRepository(
                MusicStatus.completed,
                card: _MusicRepository.withMusic(
                  _card(),
                  MusicStatus.completed,
                ),
              ),
            ),
          ],
          child: MaterialApp(
            theme: AppTheme.dark(),
            home: const CardDetailPage(cardId: 'card-7'),
          ),
        ),
      );
      // 첫 프레임이다 — 아직 답이 오지 않았다.
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.byIcon(LucideIcons.ellipsisVertical), findsNothing);

      await tester.pumpAndSettle();
      expect(find.byIcon(LucideIcons.ellipsisVertical), findsOneWidget);
    });

    testWidgets('⚠️ 404면 찾을 수 없다고 하고 다시 시도를 두지 않는다', (tester) async {
      // 삭제·권한 없음·작성자 탈퇴를 서버가 한 응답으로 묶었다(가이드 2절).
      // 열 번 더 물어도 같은 답이라 `다시 시도`는 거짓 희망이다.
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            recordCardRepositoryProvider.overrideWithValue(
              _MusicRepository(MusicStatus.completed),
            ),
          ],
          child: MaterialApp(
            theme: AppTheme.dark(),
            home: const CardDetailPage(cardId: 'card-없음'),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text(AppStrings.recordCardGone), findsOneWidget);
      expect(find.text(AppStrings.recordRetry), findsNothing);
      expect(find.byIcon(LucideIcons.ellipsisVertical), findsNothing);
    });
  });

  /// 남의 카드 — 프로필 그리드로 들어오는 길이 묶음 6에서 열렸다.
  group('남의 카드', () {
    testWidgets('⚠️ 남의 카드에는 ⋮가 없다', (tester) async {
      // 설계 6-5. 수정·삭제가 뜨면 눌러서 403을 받는다.
      await _pump(tester, mine: false);

      expect(find.byIcon(LucideIcons.ellipsisVertical), findsNothing);
    });

    testWidgets('내 카드에는 ⋮가 있다', (tester) async {
      await _pump(tester);

      expect(find.byIcon(LucideIcons.ellipsisVertical), findsOneWidget);
    });

    testWidgets('⚠️ 남의 카드에서는 음악을 만들라고 하지 않는다', (tester) async {
      // 남의 카드에 생성을 요청하는 것은 **쓰기**다.
      await _pump(tester, mine: false, music: null);

      expect(find.text(AppStrings.recordCardMusicProcessing), findsNothing);
    });

    testWidgets('⚠️ 남의 카드의 실패한 음악에 다시 만들기를 세우지 않는다', (tester) async {
      await _pump(tester, mine: false, music: MusicStatus.failed);

      expect(find.text(AppStrings.recordCardMusicRetry), findsNothing);
      expect(find.text(AppStrings.recordCardMusicFailed), findsNothing);
    });

    testWidgets('⚠️ 남의 카드에서도 다 된 음악은 재생을 쥔다', (tester) async {
      // 듣는 것은 읽기다.
      await _pump(tester, mine: false, photos: 2);

      expect(find.text(AppStrings.recordCardMusicPause), findsOneWidget);
    });
  });

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

  testWidgets('⚠️ 사진을 탭해 멈추면 줄도 재생으로 바뀐다 — 둘이 한 상태다', (tester) async {
    await _pump(tester, photos: 2);
    expect(find.text(AppStrings.recordCardMusicPause), findsOneWidget);

    await tester.tap(find.byType(PageView));
    await tester.pump();

    expect(find.text(AppStrings.recordCardMusicPlay), findsOneWidget);
  });

  testWidgets('⚠️ 사진이 없어도 버튼은 선다 — 틀 것이 있다', (tester) async {
    // 한 장뿐인 책이라 넘어갈 데는 없지만 곡은 있다. 버튼이 쥐는 것이
    // 장 넘김에서 소리로 바뀌었다(설계 2절).
    await _pump(tester);

    expect(find.text(AppStrings.recordCardMusicPause), findsOneWidget);
  });

  testWidgets('⚠️ 마지막 장에서도 버튼이 남는다', (tester) async {
    await _pump(tester, photos: 1);
    expect(find.text(AppStrings.recordCardMusicPause), findsOneWidget);

    await tester.drag(find.byType(PageView), const Offset(-400, 0));
    await tester.pumpAndSettle();

    expect(pageOf(tester), 1);
    expect(find.text(AppStrings.recordCardMusicPause), findsOneWidget);
  });
}
