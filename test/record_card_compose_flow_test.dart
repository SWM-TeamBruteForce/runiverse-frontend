import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runiverse/app/router/app_router.dart';
import 'package:runiverse/app/router/app_routes.dart';
import 'package:runiverse/core/strings/app_strings.dart';
import 'package:runiverse/core/theme/app_theme.dart';
import 'package:runiverse/features/profile/domain/image_cropper.dart';
import 'package:runiverse/features/profile/domain/picked_image.dart';
import 'package:runiverse/features/profile/presentation/background_image_provider.dart';
import 'package:runiverse/features/notification/data/fake_app_stream.dart';
import 'package:runiverse/features/notification/data/fake_notification_repository.dart';
import 'package:runiverse/features/notification/presentation/notification_provider.dart';
import 'package:runiverse/features/record/data/fake_run_record_repository.dart';
import 'package:runiverse/features/record/presentation/record_provider.dart';
import 'package:runiverse/features/record_card/data/fake_record_card_repository.dart';
import 'package:runiverse/features/record_card/domain/record_card_activity.dart';
import 'package:runiverse/features/record_card/presentation/card_compose_page.dart';
import 'package:runiverse/features/record_card/presentation/card_detail_page.dart';
import 'package:runiverse/features/record_card/presentation/card_draft_provider.dart';
import 'package:runiverse/features/record_card/presentation/card_music_provider.dart';
import 'package:runiverse/features/record_card/presentation/card_photo_slide.dart';
import 'package:runiverse/features/record_card/presentation/card_publish_page.dart';
import 'package:runiverse/features/record_card/presentation/record_card_page.dart';
import 'package:runiverse/features/record_card/presentation/record_card_provider.dart';
import 'package:runiverse/features/record_card/presentation/record_card_state.dart';

/// 작성 1 → 2 → 3 → 상세로 가는 길 (설계 6-2 · 6-3 · 6-4 · 7절).
///
/// ## ⚠️ 실제 `createAppRouter`를 태운다
///
/// 라우트 선언 순서, `?date=` 파싱, `extra` 없는 상세의 리다이렉트는 **라우터
/// 안에서만** 틀린다. 작성 1에서 미뤄 둔 Minor 8번("실제 라우터를 타는 테스트가
/// 없다")이 여기서 함께 덮인다.
void main() {
  group('화면을 잇는다', () {
    testWidgets('⚠️ 작성의 다음이 바로 저장하기로 간다', (tester) async {
      // 사진은 같은 화면의 장이다(사용자 결정 2026-11-24) — 사이에 화면이
      // 하나 더 서면 밀어서 넣은 사람이 같은 걸음을 두 번 걷는다.
      await _pump(tester, at: AppRoutes.recordCardNew, filled: true);
      await _keepDraft(tester);
      expect(find.byType(CardComposePage), findsOne);

      await tester.tap(find.text(AppStrings.recordCardComposeNext));
      await tester.pumpAndSettle();

      expect(find.byType(CardPublishPage), findsOne);
    });

    testWidgets('사진은 작성 화면을 옆으로 밀어 넣는다', (tester) async {
      await _pump(tester, at: AppRoutes.recordCardNew, filled: true);
      await _keepDraft(tester);

      await tester.drag(find.byType(PageView), const Offset(-600, 0));
      await tester.pumpAndSettle();

      expect(find.byType(CardAddPhotoSlide), findsOne);
    });

    testWidgets('⚠️ 날짜 쿼리가 작성 1까지 간다', (tester) async {
      await _pump(tester, at: AppRoutes.recordCardNewOn(DateTime(2026, 11, 3)));

      expect(
        find.text(AppStrings.recordCardComposeDateLabel(DateTime(2026, 11, 3))),
        findsOne,
      );
    });

    testWidgets('⚠️ 날짜 쿼리가 망가져 있으면 오늘로 떨어진다', (tester) async {
      // 404를 내지 않는다 — 탭 머리의 쓰기 버튼은 날짜를 싣지 않고 들어온다.
      await _pump(tester, at: '${AppRoutes.recordCardNew}?date=어제');

      expect(find.byType(CardComposePage), findsOne);
      expect(tester.takeException(), isNull);
    });
  });

  group('⚠️ 초안 없이 중간에 떨어지면 탭으로 돌려보낸다', () {
    // 딥링크나 프로세스 복원으로 들어오는 길이다. 작성 1을 거치지 않았으면
    // 고를 기록도, 쓴 회고도 없어 보여 줄 것이 없다.
    for (final route in [AppRoutes.recordCardNewPublish]) {
      testWidgets(route, (tester) async {
        await _pump(tester, at: route);

        expect(find.byType(RecordCardPage), findsOne, reason: route);
        expect(find.byType(CardPublishPage), findsNothing);
      });
    }
  });

  testWidgets('⚠️ 저장하면 상세로 가고 작성 화면들이 걷힌다', (tester) async {
    // 설계 6-4: "카드가 만들어지고 상세로 간다(작성 화면들은 스택에서 걷힌다)."
    //
    // ⚠️ **탭에서 걸어 들어간다.** `initialLocation`으로 작성 3에 바로 떨어지면
    // 그 아래에 스택이 없어, 걷어 낼 것도 돌아갈 데도 없다 — 실제 사용자는
    // 탭을 밑에 두고 올라온다.
    _musicNow = DateTime(2026, 11, 18, 10);
    final container = await _walkToPublish(tester);

    await tester.tap(find.text(AppStrings.recordCardPublishSave));
    await tester.pumpAndSettle();

    expect(find.byType(CardDetailPage), findsOne);
    expect(find.byType(CardPublishPage), findsNothing);
    expect(find.byType(CardComposePage), findsNothing);
    // 저장이 끝났으면 초안은 비어 있다 — 다음 작성이 남의 글로 시작하면 안 된다.
    expect(container.read(cardDraftProvider(null)).record, isNull);

    // 뒤로 가면 캘린더다 — 방금 걷은 작성 3이 아니다.
    // `pageBack`은 Material·Cupertino 기본 뒤로만 찾는다. 상세의 뒤로는
    // 이 저장소의 `AppIcon`을 쓴 `IconButton`이다.
    await tester.tap(find.byTooltip(AppStrings.authBack));
    await tester.pumpAndSettle();

    expect(find.byType(RecordCardPage), findsOne);
    expect(find.byType(CardPublishPage), findsNothing);
  });

  testWidgets('⚠️ 저장한 카드가 달력에 바로 보인다', (tester) async {
    // 저장은 됐는데 달력이 다시 받지 않으면, 그날은 **운동화 그대로**다 —
    // "카드를 썼는데 달력은 안 썼다고 한다"로 보인다. 2026-11-18 에뮬레이터에서
    // 실제로 그렇게 보였다.
    final container = await _walkToPublish(tester);

    await tester.tap(find.text(AppStrings.recordCardPublishSave));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip(AppStrings.authBack));
    await tester.pumpAndSettle();

    expect(_cards.creates, 1, reason: '카드는 만들어졌다');

    final after = container.read(recordCardControllerProvider);
    expect(after, isA<RecordCardData>());
    expect(
      (after as RecordCardData).visible
          .expand((m) => m.byDay.values)
          .expand((cards) => cards)
          .map((c) => c.id),
      contains(startsWith('new-')),
      reason: '방금 만든 카드(`new-`)가 달력에 들어와야 한다',
    );
  });

  testWidgets('⚠️ 저장이 도는 중에는 시스템 뒤로로 빠져나가지 못한다', (tester) async {
    // AppBar 뒤로만 닫아 두면 안드로이드 하드웨어·제스처 뒤로가 그대로 나가고,
    // 저장이 끝난 뒤 **걷힌 화면의 context**로 라우터를 불러 "deactivated
    // widget"으로 죽는다. 만들어진 카드를 아무도 받지 못한 채 초안만 비워진다.
    // ⚠️ 저장을 **전환 애니메이션보다 길게** 잡는다. 짧으면 pop이 끝나기 전에
    // 저장이 먼저 끝나, "못 나간다"와 "아직 나가는 중이다"가 구별되지 않는다.
    await _walkToPublish(tester, delay: const Duration(milliseconds: 800));

    await tester.tap(find.text(AppStrings.recordCardPublishSave));
    await tester.pump(const Duration(milliseconds: 50));

    // ⚠️ **`maybePop` 경로로 들어가야 한다.** 안드로이드 하드웨어·제스처
    // 뒤로가 이 길이고, `PopScope`는 이것만 본다. `GoRouter.pop()`은 네비게이터를
    // 직접 걷어 `PopScope`를 건너뛰므로 이 약속을 검사하지 못한다.
    await tester.binding.handlePopRoute();
    // 전환이 끝날 만큼 — 저장(3초)은 아직 돌고 있다.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));

    expect(find.byType(CardPublishPage), findsOne, reason: '도는 동안에는 나가지 못한다');

    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    // 저장은 끝까지 가고 상세로 간다 — 나가지 못했으니 받을 사람이 있다.
    expect(find.byType(CardDetailPage), findsOne);

    await _finishMusic(tester);

    // 저장이 끝나면 달력이 다시 받는다. 이 테스트의 느린 저장소가 거기도
    // 걸려, 안 기다리면 타이머가 남은 채로 끝난다.
    await tester.pumpAndSettle(const Duration(seconds: 2));
  });
}

/// 탭 → 작성 1 → 2 → 3까지 **실제로 눌러서** 올라간다.
Future<ProviderContainer> _walkToPublish(
  WidgetTester tester, {
  Duration delay = Duration.zero,
}) async {
  final container = await _pump(
    tester,
    at: AppRoutes.recordCard,
    filled: true,
    delay: delay,
  );

  // 탭 머리의 연필.
  await tester.tap(find.byTooltip(AppStrings.recordCardEmptyAction).first);
  await tester.pumpAndSettle();
  await _keepDraft(tester);

  await tester.tap(find.text(AppStrings.recordCardComposeNext));
  await tester.pumpAndSettle();
  expect(find.byType(CardPublishPage), findsOne);

  return container;
}

/// 작성 1이 들어올 때 띄우는 **이어 쓰기 시트**를 받는다.
///
/// ⚠️ 초안이 차 있으면(`isDirty`) 설계 7절에 따라 반드시 한 번 묻는다. 안
/// 치우면 시트가 `다음` 버튼을 덮어 탭이 먹히지 않는다.
Future<void> _keepDraft(WidgetTester tester) async {
  expect(find.text(AppStrings.recordCardComposeResumeTitle), findsOne);
  await tester.tap(find.text(AppStrings.recordCardComposeResume));
  await tester.pumpAndSettle();
}

// ── 도움 ──────────────────────────────────────────────────────

final _today = DateTime(2026, 11, 18);

/// 가짜가 보는 "지금". **음악 상태가 이 값으로 계산된다**(요청 시각과의 차).
var _musicNow = DateTime(2026, 11, 18, 10);

/// ⚠️ **저장하면 상세가 음악을 묻기 시작한다** — 음악을 켜고 저장했으면
/// 만드는 중이고, 끝날 때까지 상세를 다시 읽는다. 폴링 타이머를 남기고
/// 테스트를 끝내면 `!timersPending`으로 떨어지므로, 시계를 밀어 끝 상태로
/// 세운다.
Future<void> _finishMusic(WidgetTester tester) async {
  _musicNow = _musicNow.add(const Duration(seconds: 14));
  await tester.pump(CardMusicController.firstInterval);
  await tester.pumpAndSettle();
}

/// 방금 세운 카드 저장소. 만든 횟수를 본다.
late FakeRecordCardRepository _cards;

/// 실제 라우터를 태운 앱. [filled]면 초안이 작성 1을 통과한 상태다.
Future<ProviderContainer> _pump(
  WidgetTester tester, {
  required String at,
  bool filled = false,
  Duration delay = Duration.zero,
}) async {
  final container = ProviderContainer(
    overrides: [
      recordCardRepositoryProvider.overrideWithValue(
        _cards = FakeRecordCardRepository(
          today: _today,
          delay: delay,
          clock: () => _musicNow,
        ),
      ),
      runRecordRepositoryProvider.overrideWithValue(
        FakeRunRecordRepository(today: _today),
      ),
      recordCardClockProvider.overrideWithValue(() => _today),
      // 진짜는 `dart:ui`와 플랫폼 플러그인을 써서 테스트 환경에 없다.
      imageCropperProvider.overrideWithValue(_Cropper()),
      // ⚠️ **셸을 세우려면 이 둘이 필요하다.** 작성 2·3에서 초안 없이
      // 떨어지면 `/record-card`(셸 안)로 돌려보내는데, 진짜 `AppShell`은
      // `dioProvider`를 거쳐 `API_BASE_URL`을 찾다 죽는다 — 테스트는
      // `--dart-define`을 받지 않는다. `widget_test.dart`에 같은 전례가 있다.
      appStreamProvider.overrideWithValue(FakeAppStream()),
      notificationRepositoryProvider.overrideWithValue(
        FakeNotificationRepository(),
      ),
    ],
  );
  addTearDown(container.dispose);

  if (filled) {
    final draft = container.read(cardDraftProvider(null).notifier);
    final records = await container
        .read(runRecordRepositoryProvider)
        .byDateRange(
          from: _today.subtract(const Duration(days: 16)),
          to: _today,
        );
    draft.pickRecord(records.first);
    draft.setActivity(RecordCardActivity.daily);
    draft.setReview('좋았다');
  }

  final router = createAppRouter(initialLocation: at);
  addTearDown(router.dispose);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(theme: AppTheme.dark(), routerConfig: router),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

/// 자르지 않고 받은 것을 그대로 돌려준다.
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
