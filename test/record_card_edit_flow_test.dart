import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:runiverse/app/router/app_router.dart';
import 'package:runiverse/app/router/app_routes.dart';
import 'package:runiverse/core/strings/app_strings.dart';
import 'package:runiverse/core/theme/app_theme.dart';
import 'package:runiverse/features/notification/data/fake_app_stream.dart';
import 'package:runiverse/features/notification/data/fake_notification_repository.dart';
import 'package:runiverse/features/notification/presentation/notification_provider.dart';
import 'package:runiverse/features/profile/domain/image_cropper.dart';
import 'package:runiverse/features/profile/domain/picked_image.dart';
import 'package:runiverse/features/profile/presentation/background_image_provider.dart';
import 'package:runiverse/features/record/data/fake_run_record_repository.dart';
import 'package:runiverse/features/record/presentation/record_provider.dart';
import 'package:runiverse/features/record_card/data/fake_record_card_repository.dart';
import 'package:runiverse/features/record_card/domain/edit_record_card.dart';
import 'package:runiverse/features/record_card/domain/new_record_card.dart';
import 'package:runiverse/features/record_card/domain/music_generation.dart';
import 'package:runiverse/features/record_card/domain/record_card.dart';
import 'package:runiverse/features/record_card/domain/record_card_repository.dart';
import 'package:runiverse/features/record_card/presentation/card_compose_page.dart';
import 'package:runiverse/features/record_card/presentation/card_detail_page.dart';
import 'package:runiverse/features/record_card/presentation/card_draft_provider.dart';
import 'package:runiverse/features/record_card/presentation/card_music_provider.dart';
import 'package:runiverse/features/record_card/presentation/card_photo_page.dart';
import 'package:runiverse/features/record_card/presentation/card_publish_page.dart';
import 'package:runiverse/features/record_card/presentation/record_card_page.dart';
import 'package:runiverse/features/record_card/presentation/record_card_provider.dart';
import 'package:runiverse/features/record_card/presentation/record_card_state.dart';

/// 상세에서 고치고 지우는 길 (설계 6-6).
///
/// ## ⚠️ 실제 `createAppRouter`를 태운다
///
/// 수정 라우트 셋과 `:id` 파싱, `extra` 없는 진입, 저장 뒤 스택 걷기는
/// **라우터 안에서만** 틀린다.
void main() {
  group('⋮', () {
    testWidgets('수정과 삭제가 있다', (tester) async {
      await _pumpDetail(tester);

      await tester.tap(find.byTooltip(AppStrings.recordCardMore));
      await tester.pumpAndSettle();

      expect(find.text(AppStrings.recordCardEditTitle), findsOne);
      expect(find.text(AppStrings.recordCardDelete), findsOne);
    });

    testWidgets('수정을 누르면 그 카드의 작성 1로 간다', (tester) async {
      await _pumpDetail(tester);

      await _openMenu(tester, AppStrings.recordCardEditTitle);

      expect(find.byType(CardComposePage), findsOne);
      // 카드 값이 들어와 있다.
      expect(find.text(AppStrings.recordCardEditRecordLocked), findsOne);
    });
  });

  group('수정 저장', () {
    testWidgets('⚠️ 세 화면을 거쳐 저장하면 고친 값이 상세에 보인다', (tester) async {
      await _pumpDetail(tester);
      await _openMenu(tester, AppStrings.recordCardEditTitle);

      await _reachReview(tester);
      await tester.enterText(find.byType(TextField), '고친 글');
      await tester.pump();
      await tester.tap(find.text(AppStrings.recordCardComposeNext));
      await tester.pumpAndSettle();
      expect(find.byType(CardPhotoPage), findsOne);

      await tester.tap(find.text(AppStrings.recordCardComposeNext));
      await tester.pumpAndSettle();
      expect(find.byType(CardPublishPage), findsOne);

      await tester.tap(find.text(AppStrings.recordCardPublishSave));
      await tester.pumpAndSettle();

      expect(find.byType(CardDetailPage), findsOne);
      expect(find.text('고친 글'), findsOne);

      // ⚠️ 고친 값이 AI 입력이라 저장이 음악을 다시 걸었다 — 폴링을 끝낸다.
      await _finishMusic(tester);
    });

    testWidgets('⚠️ 저장하면 상세의 음악 줄이 되돌아간다 — 전곡을 다시 만든다', (tester) async {
      // 작성 3이 "처음부터 다시 만듭니다"라고 알렸으면, 돌아온 상세가 그 말과
      // 같은 것을 보여야 한다. 다 된 음악 줄(`멈춤`)이 그대로 서 있으면
      // **방금 읽은 경고가 거짓**이 된다.
      // 사진이 없는 카드라 넘어갈 장이 없다 — 줄은 `음악이 준비됐어요`다.
      await _pumpDetail(tester);
      expect(find.text(AppStrings.recordCardMusicReady), findsOne);

      await _openMenu(tester, AppStrings.recordCardEditTitle);
      await _reachReview(tester);
      await tester.enterText(find.byType(TextField), '고친 글');
      await tester.pump();
      await _nextTwice(tester);

      await tester.tap(find.text(AppStrings.recordCardPublishSave));
      await tester.pumpAndSettle();

      expect(find.text(AppStrings.recordCardMusicQueued), findsOne);
      expect(find.text(AppStrings.recordCardMusicReady), findsNothing);

      await _finishMusic(tester);
    });

    testWidgets('⚠️ 저장하면 작성 셋도 옛 상세도 걷힌다', (tester) async {
      // 새 상세를 그냥 밀면 상세가 둘 쌓여 **뒤로가 두 번**이 되고, 밑에
      // 깔린 것은 **고치기 전 값**을 들고 있다.
      await _pumpDetail(tester);
      await _openMenu(tester, AppStrings.recordCardEditTitle);
      await _nextTwice(tester);

      await tester.tap(find.text(AppStrings.recordCardPublishSave));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip(AppStrings.authBack));
      await tester.pumpAndSettle();

      expect(find.byType(RecordCardPage), findsOne);
      expect(find.byType(CardDetailPage), findsNothing);
    });

    testWidgets('저장하면 초안을 비운다', (tester) async {
      // 안 비우면 다음에 그 카드를 열었을 때 고치다 만 것이 되살아난다.
      final container = await _pumpDetail(tester);
      await _openMenu(tester, AppStrings.recordCardEditTitle);
      await _nextTwice(tester);

      await tester.tap(find.text(AppStrings.recordCardPublishSave));
      await tester.pumpAndSettle();

      expect(container.read(cardDraftProvider(_card.id)).editing, isNull);
    });
  });

  group('삭제', () {
    testWidgets('⚠️ 되돌릴 수 없다고 말하고 받는다', (tester) async {
      // 서버에 논리 삭제 컬럼이 없다(설계 3절).
      await _pumpDetail(tester);

      await tester.tap(find.byTooltip(AppStrings.recordCardMore));
      await tester.pumpAndSettle();
      await tester.tap(find.text(AppStrings.recordCardDelete));
      await tester.pumpAndSettle();

      expect(find.text(AppStrings.recordCardDeleteTitle), findsOne);
      expect(find.text(AppStrings.recordCardDeleteBody), findsOne);
    });

    // ── 음악 알림 (설계 6-6) ──────────────────────────────────

    testWidgets('⚠️ 만드는 중이면 함께 사라진다고 알린다', (tester) async {
      // ⚠️ 목 번호 **1001**은 사진이 없고 음악이 실패해 있다
      // (`FakeRecordCardRepository._seeded`). `다시 만들기`를 눌러 **만드는
      // 중**으로 세운 뒤 지우려 한다 — 사용자가 실제로 지나는 길이다.
      await _pumpDetail(tester, cardId: 1001);
      await tester.tap(find.text(AppStrings.recordCardMusicRetry));
      await tester.pump();
      expect(find.text(AppStrings.recordCardMusicQueued), findsOne);

      await _openMenu(tester, AppStrings.recordCardDelete);

      expect(find.text(AppStrings.recordCardMusicWorkingDelete), findsOne);

      await tester.tap(find.text(AppStrings.recordCardDeleteCancel));
      await tester.pumpAndSettle();
      await _finishMusic(tester);
    });

    testWidgets('⚠️ 알리기만 하고 막지 않는다', (tester) async {
      await _pumpDetail(tester, cardId: 1001);
      await tester.tap(find.text(AppStrings.recordCardMusicRetry));
      await tester.pump();

      await _openMenu(tester, AppStrings.recordCardDelete);
      await tester.tap(find.text(AppStrings.recordCardDeleteConfirm));
      await tester.pumpAndSettle();

      expect(_cards.deletes, 1);
      expect(find.byType(CardDetailPage), findsNothing);
    });

    testWidgets('만드는 중이 아니면 삭제 시트가 음악을 말하지 않는다', (tester) async {
      await _pumpDetail(tester);

      await _openMenu(tester, AppStrings.recordCardDelete);

      expect(find.text(AppStrings.recordCardMusicWorkingDelete), findsNothing);
    });

    testWidgets('그대로 두기를 고르면 아무 일도 없다', (tester) async {
      final container = await _pumpDetail(tester);

      await _openMenu(tester, AppStrings.recordCardDelete);
      await tester.tap(find.text(AppStrings.recordCardDeleteCancel));
      await tester.pumpAndSettle();

      expect(find.byType(CardDetailPage), findsOne);
      expect(_cards.deletes, 0);
      expect(container, isNotNull);
    });

    // ⚠️ Review Focus 4
    testWidgets('⚠️ 지우면 상세에 머물지 않는다', (tester) async {
      // 없는 카드를 보고 있으면 거기서 수정을 눌러 404를 받는다.
      await _pumpDetail(tester);

      await _openMenu(tester, AppStrings.recordCardDelete);
      await tester.tap(find.text(AppStrings.recordCardDeleteConfirm));
      await tester.pumpAndSettle();

      expect(find.byType(CardDetailPage), findsNothing);
      expect(find.byType(RecordCardPage), findsOne);
      expect(_cards.deletes, 1);
    });

    testWidgets('⚠️ 도는 동안 진행 표시가 뜨고 다시 눌리지 않는다', (tester) async {
      // 아무 표시가 없으면 느린 망에서 "안 눌렸다"로 읽혀 또 누른다.
      await _pumpDetail(tester, delay: const Duration(milliseconds: 300));

      await _openMenu(tester, AppStrings.recordCardDelete);
      await tester.tap(find.text(AppStrings.recordCardDeleteConfirm));
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(
        tester
            .widget<IconButton>(
              find.ancestor(
                of: find.byTooltip(AppStrings.recordCardMore),
                matching: find.byType(IconButton),
              ),
            )
            .onPressed,
        isNull,
        reason: '도는 동안 ⋮가 다시 열리면 안 된다',
      );

      // ⚠️ **`pumpAndSettle`을 쓰지 않는다.** 진행 표시가 영원히 도는
      // 애니메이션이라 영영 "settle"하지 않는다.
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byType(RecordCardPage), findsOne);
    });

    testWidgets('⚠️ 두 번 눌러도 실패했다고 하지 않는다', (tester) async {
      // 재진입 가드가 `false`를 주고 화면이 그것을 실패로 읽으면, 지워졌는데
      // "지우지 못했어요"를 본 직후 화면이 걷힌다.
      await _pumpDetail(tester, delay: const Duration(milliseconds: 300));

      await _openMenu(tester, AppStrings.recordCardDelete);
      await tester.tap(find.text(AppStrings.recordCardDeleteConfirm));
      await tester.pump();
      // 시트는 닫혔고 상세가 도는 중이다. 한 번 더 같은 길을 탄다.
      await tester.tap(find.byTooltip(AppStrings.recordCardMore));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.text(AppStrings.recordCardDeleteFailed), findsNothing);
      expect(_cards.deletes, 1);
    });

    testWidgets('⚠️ 지운 카드가 달력에서 빠진다', (tester) async {
      // 안 무효화하면 지운 카드가 달력에 남는다.
      final container = await _pumpDetail(tester);

      await _openMenu(tester, AppStrings.recordCardDelete);
      await tester.tap(find.text(AppStrings.recordCardDeleteConfirm));
      await tester.pumpAndSettle();

      final state = container.read(recordCardControllerProvider);
      final ids = state is RecordCardData
          ? state.visible.expand((m) => m.cards).map((c) => c.id)
          : const <int>[];
      expect(ids, isNot(contains(_card.id)));
    });
  });

  group('⚠️ 카드 없이 수정 라우트에 떨어지면 탭으로 돌려보낸다', () {
    // 딥링크나 프로세스 복원이다. 카드 단건 조회 API가 없어 보여 줄 것이 없다.
    for (final route in [
      AppRoutes.recordCardEditOf(1000),
      AppRoutes.recordCardEditPhotosOf(1000),
      AppRoutes.recordCardEditPublishOf(1000),
    ]) {
      testWidgets(route, (tester) async {
        await _pumpAt(tester, route);

        expect(find.byType(RecordCardPage), findsOne, reason: route);
        expect(find.byType(CardComposePage), findsNothing);
      });
    }
  });
}

// ── 도움 ──────────────────────────────────────────────────────

final _today = DateTime(2026, 11, 18);

/// 가짜가 보는 "지금". **음악 상태가 이 값으로 계산된다**(요청 시각과의 차).
/// 테스트가 밀어서 생성을 끝낸다.
var _musicNow = DateTime(2026, 11, 18, 10);

/// ⚠️ **만드는 중인 음악에는 끝이 없다** — 폴링 타이머를 남기고 테스트를
/// 끝내면 `!timersPending`으로 떨어진다. 시계를 밀어 끝 상태로 세운다.
Future<void> _finishMusic(WidgetTester tester) async {
  _musicNow = _musicNow.add(const Duration(seconds: 14));
  await tester.pump(CardMusicController.pollInterval);
  await tester.pump();
}

late FakeRecordCardRepository _cards;
late GoRouter _router;

/// 상세에 띄운 카드. ⚠️ **가짜 저장소에 실제로 있는 것**이어야 한다 — 지어낸
/// 번호를 쓰면 고치기·지우기가 `notFound`로 떨어진다.
late RecordCard _card;

/// `⋮`를 열고 한 줄을 누른다.
Future<void> _openMenu(WidgetTester tester, String item) async {
  await tester.tap(find.byTooltip(AppStrings.recordCardMore));
  await tester.pumpAndSettle();
  await tester.tap(find.text(item));
  await tester.pumpAndSettle();
}

/// 작성 1 → 2 → 3.
Future<void> _nextTwice(WidgetTester tester) async {
  for (var i = 0; i < 2; i++) {
    await tester.tap(find.text(AppStrings.recordCardComposeNext));
    await tester.pumpAndSettle();
  }
}

/// 회고 칸을 화면 안으로 끌어 올린다 — 수정 모드는 경로·지표가 들어가 더 길다.
Future<void> _reachReview(WidgetTester tester) async {
  await tester.dragUntilVisible(
    find.byType(TextField),
    find.byType(ListView),
    const Offset(0, -120),
  );
  await tester.pumpAndSettle();
}

/// 카드 상세에 선 상태로 띄운다.
Future<ProviderContainer> _pumpDetail(
  WidgetTester tester, {
  Duration delay = Duration.zero,
  int? cardId,
}) async {
  final container = await _pumpAt(tester, AppRoutes.recordCard, delay: delay);

  // 사진 없는 카드를 고른다 — 사진이 있으면 주소를 받으러 나가 테스트가
  // 네트워크를 탄다.
  // ⚠️ **31일을 넘기지 않는다** — 가짜도 진짜와 같은 규칙으로 거절한다
  // (`RecordCardRepository.maxRangeDays`).
  final all = await _cards.byDateRange(
    from: _today.subtract(const Duration(days: 25)),
    to: _today,
  );
  _card = cardId == null
      ? all.firstWhere((c) => c.photos.isEmpty)
      : all.firstWhere((c) => c.id == cardId);

  _router.push(AppRoutes.recordCardDetailOf(_card.id), extra: _card);
  await tester.pumpAndSettle();
  expect(find.byType(CardDetailPage), findsOne);
  return container;
}

Future<ProviderContainer> _pumpAt(
  WidgetTester tester,
  String at, {
  Duration delay = Duration.zero,
}) async {
  _musicNow = DateTime(2026, 11, 18, 10);
  final container = ProviderContainer(
    overrides: [
      recordCardRepositoryProvider.overrideWithValue(
        // ⚠️ **Fake의 `delay`를 쓰지 않는다.** 그것은 `byDateRange`에도
        // 걸려 달력이 과거를 더 받는 길까지 느려지고, `pumpAndSettle`이
        // 영영 끝나지 않는다. 느리게 할 것은 **삭제뿐**이다.
        _SlowDelete(
          _cards = FakeRecordCardRepository(
            today: _today,
            clock: () => _musicNow,
          ),
          delay,
        ),
      ),
      runRecordRepositoryProvider.overrideWithValue(
        FakeRunRecordRepository(today: _today),
      ),
      recordCardClockProvider.overrideWithValue(() => _today),
      imageCropperProvider.overrideWithValue(_Cropper()),
      // 셸을 세우려면 이 둘이 필요하다 — 진짜는 dio를 거쳐 서버 주소를 찾다
      // 죽는다(`widget_test.dart`에 전례).
      appStreamProvider.overrideWithValue(FakeAppStream()),
      notificationRepositoryProvider.overrideWithValue(
        FakeNotificationRepository(),
      ),
    ],
  );
  addTearDown(container.dispose);

  _router = createAppRouter(initialLocation: at);
  addTearDown(_router.dispose);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(theme: AppTheme.dark(), routerConfig: _router),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

/// 삭제만 느린 저장소. 나머지는 그대로 넘긴다.
class _SlowDelete implements RecordCardRepository {
  @override
  Future<List<RecordCard>> byUser({required String userId, int? limit}) =>
      _inner.byUser(userId: userId, limit: limit);

  _SlowDelete(this._inner, this._delay);

  final FakeRecordCardRepository _inner;
  final Duration _delay;

  @override
  Future<void> delete(int cardId) async {
    if (_delay > Duration.zero) await Future<void>.delayed(_delay);
    return _inner.delete(cardId);
  }

  @override
  Future<List<RecordCard>> byDateRange({
    required DateTime from,
    required DateTime to,
  }) => _inner.byDateRange(from: from, to: to);

  @override
  Future<RecordCard> create(NewRecordCard card) => _inner.create(card);

  @override
  Future<RecordCard> update(EditRecordCard card) => _inner.update(card);

  @override
  Future<MusicGeneration> musicOf(int cardId) => _inner.musicOf(cardId);

  @override
  Future<MusicGeneration> requestMusic(int cardId) =>
      _inner.requestMusic(cardId);
}

class _Cropper implements ImageCropper {
  @override
  Future<PickedImage> crop(
    PickedImage image, {
    required double aspectRatio,
    required double alignY,
    double alignX = 0,
  }) async => image;

  @override
  Future<void> discard(PickedImage cropped) async {}
}
