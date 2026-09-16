import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runiverse/app/app.dart';
import 'package:runiverse/app/router/app_routes.dart';
import 'package:runiverse/core/storage/match_room_store.dart';
import 'package:runiverse/core/strings/app_strings.dart';
import 'package:runiverse/core/widgets/app_button.dart';
import 'package:runiverse/features/home/presentation/home_page.dart';
import 'package:runiverse/features/matching/data/fake_match_repository.dart';
import 'package:runiverse/features/matching/data/fake_match_stream.dart';
import 'package:runiverse/features/matching/domain/match_failure.dart';
import 'package:runiverse/features/matching/domain/target_distance.dart';
import 'package:runiverse/features/matching/presentation/match_register_page.dart';
import 'package:runiverse/features/matching/presentation/match_register_provider.dart';
import 'package:runiverse/features/matching/presentation/match_room_provider.dart';
import 'package:runiverse/features/session/data/fake_user_status_repository.dart';
import 'package:runiverse/features/session/presentation/user_status_provider.dart';

/// 매칭 등록 (S08) — **무엇을 골라야 열리고, 무엇이 서버로 나가는가.**
///
/// 시각을 앱이 조립하면 엉뚱한 날짜로 신청되고 사용자는 알아챌 방법이 없다.
/// 그래서 "서버가 준 문자열이 그대로 나가는가"가 여기서 가장 중요한 확인이다.
void main() {
  /// 시각을 고정한다. 목록을 앱이 벽시계로 만들기 때문에, 고정하지 않으면
  /// 밤 10시 이후에 돌릴 때 고를 수 있는 슬롯이 없어 테스트가 시각에 따라
  /// 달라진다.
  const nineteen = '2026-09-15T19:00:00';

  /// 18:30 — 18:00은 이미 지났고 19:00부터는 고를 수 있다.
  DateTime clockAt1830() => DateTime(2026, 9, 15, 18, 30);

  Future<FakeMatchRepository> pumpRegister(
    WidgetTester tester, {
    FakeMatchRepository? repository,
    DateTime Function()? clock,
  }) async {
    final matches = repository ?? FakeMatchRepository();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          matchRepositoryProvider.overrideWithValue(matches),
          matchClockProvider.overrideWithValue(clock ?? clockAt1830),
          // 신청이 방 번호를 남긴다. 진짜는 플랫폼 채널을 탄다.
          matchRoomStoreProvider.overrideWithValue(InMemoryMatchRoomStore()),
          // 신청에 성공하면 곧바로 스트림에 붙는다. 진짜를 두면 dio가
          // 서버 주소를 찾다 죽는다.
          matchStreamProvider.overrideWithValue(FakeMatchStream()),
          // 신청에 성공하면 홈 배너가 볼 상태를 다시 읽는다.
          userStatusRepositoryProvider.overrideWithValue(
            FakeUserStatusRepository(),
          ),
        ],
        child: const RuniverseApp(initialLocation: AppRoutes.home),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(AppButton, AppStrings.homeMatchCta));
    await tester.pumpAndSettle();
    return matches;
  }

  /// 시간 시트를 열어 [time]을 고른다.
  Future<void> pickSlot(WidgetTester tester, String time) async {
    await tester.tap(find.text(AppStrings.matchTimePlaceholder));
    await tester.pumpAndSettle();
    await tester.tap(find.text(time));
    await tester.pumpAndSettle();
  }

  Future<void> pickDistance(WidgetTester tester, TargetDistance km) async {
    await tester.tap(find.text(AppStrings.matchDistanceText(km.km)));
    await tester.pumpAndSettle();
  }

  /// 등록을 누르고 화면이 자리를 잡을 때까지 돌린다.
  ///
  /// ⚠️ `pumpAndSettle`을 쓰지 못한다. 신청에 성공하면 대기방으로 가는데,
  /// 그 화면이 카운트다운 때문에 1초 타이머를 계속 돌려 영영 잠잠해지지 않는다.
  Future<void> tapCta(WidgetTester tester) async {
    await tester.tap(
      find.widgetWithText(AppButton, AppStrings.matchRegisterCta),
    );
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  /// CTA를 찾는다. `onPressed`가 `null`이면 잠긴 것이다.
  AppButton cta(WidgetTester tester) => tester.widget<AppButton>(
    find.widgetWithText(AppButton, AppStrings.matchRegisterCta),
  );

  group('고르기', () {
    testWidgets('들어오면 시간대를 갖춘다', (tester) async {
      await pumpRegister(tester);

      expect(find.byType(MatchRegisterPage), findsOneWidget);
      expect(find.text(AppStrings.matchTimePlaceholder), findsOneWidget);
    });

    testWidgets('⚠️ 둘 다 골라야 CTA가 열린다', (tester) async {
      // 하나만으로 열면 서버가 400으로 거절하고, 사용자는 왜인지 모른다.
      await pumpRegister(tester);
      expect(cta(tester).onPressed, isNull);

      await pickSlot(tester, '19:00');
      expect(cta(tester).onPressed, isNull);

      await pickDistance(tester, TargetDistance.km5);
      expect(cta(tester).onPressed, isNotNull);
    });

    testWidgets('고른 시간이 보인다', (tester) async {
      await pumpRegister(tester);

      await pickSlot(tester, '19:00');

      expect(find.text('19:00'), findsOneWidget);
    });

    testWidgets('⚠️ 마감된 시간대는 목록에 남되 눌리지 않는다', (tester) async {
      // 빼면 "18:00이 왜 없지"가 되고, 목록이 줄어드는 것도 이상하게 읽힌다.
      await pumpRegister(tester);

      await tester.tap(find.text(AppStrings.matchTimePlaceholder));
      await tester.pumpAndSettle();

      expect(find.text('18:00'), findsOneWidget);
      // 18:30 기준이라 18:00·18:30 둘 다 지났다.
      expect(find.text(AppStrings.matchSlotClosed), findsNWidgets(2));

      await tester.tap(find.text('18:00'));
      await tester.pumpAndSettle();

      // 시트가 그대로다 — 눌려서 닫혔다면 마감된 슬롯이 골라진 것이다.
      expect(find.text(AppStrings.matchSlotSheetTitle), findsOneWidget);
    });

    testWidgets('⚠️ 모르는 대기 인원은 적지 않는다', (tester) async {
      // 조회 API가 없어 목록은 앱이 만들고, 대기 인원은 전부 `null`이다.
      // 0명으로 그리면 아무도 없다고 잘못 알린다.
      await pumpRegister(tester);

      await tester.tap(find.text(AppStrings.matchTimePlaceholder));
      await tester.pumpAndSettle();

      expect(find.text(AppStrings.matchWaitingCount(0)), findsNothing);
    });

    testWidgets('앱이 만든 목록은 18:00부터 22:00까지다', (tester) async {
      await pumpRegister(tester);

      await tester.tap(find.text(AppStrings.matchTimePlaceholder));
      await tester.pumpAndSettle();

      expect(find.text('18:00'), findsOneWidget);

      // 시트가 화면 절반이라 마지막 칸은 굴려야 나온다. 화면에 목록이 둘
      // (등록 화면·시트)이라 시트 쪽을 짚어 굴린다.
      final sheetList = find.ancestor(
        of: find.text('18:00'),
        matching: find.byType(ListView),
      );
      await tester.drag(sheetList, const Offset(0, -400));
      await tester.pumpAndSettle();
      expect(find.text('22:00'), findsOneWidget);
    });
  });

  group('신청', () {
    testWidgets('⚠️ 서버가 준 문자열을 그대로 보낸다', (tester) async {
      // 앱이 "오늘 + 19:00"을 조립하면 자정 근처에서 엉뚱한 날짜가 나간다.
      final matches = await pumpRegister(tester);

      await pickSlot(tester, '19:00');
      await pickDistance(tester, TargetDistance.km5);
      await tapCta(tester);

      expect(matches.appliedSlotRaw, nineteen);
      expect(matches.appliedDistance, TargetDistance.km5);
    });

    testWidgets('신청이 되면 홈으로 돌아간다', (tester) async {
      // 모집 중에는 갈 화면이 따로 없다. 홈 히어로가 그 상태를 보여준다.
      await pumpRegister(tester);

      await pickSlot(tester, '19:00');
      await pickDistance(tester, TargetDistance.km5);
      await tapCta(tester);

      expect(find.byType(HomePage), findsOneWidget);
      // ⚠️ 등록 화면은 닫는다. 뒤로 가서 또 신청하면 서버가 409로 막는다.
      expect(find.byType(MatchRegisterPage), findsNothing);
    });

    testWidgets('이미 진행 중이면 화면에 남아 이유를 말한다', (tester) async {
      final matches = FakeMatchRepository(
        applyFailure: MatchFailure.alreadyInProgress,
      );
      await pumpRegister(tester, repository: matches);

      await pickSlot(tester, '19:00');
      await pickDistance(tester, TargetDistance.km5);
      await tester.tap(
        find.widgetWithText(AppButton, AppStrings.matchRegisterCta),
      );
      await tester.pumpAndSettle();

      expect(find.text(AppStrings.matchFailedAlready), findsOneWidget);
      expect(find.byType(MatchRegisterPage), findsOneWidget);
    });

    testWidgets('⚠️ 쿨다운은 언제까지인지 말한다', (tester) async {
      // "잠시 제한됩니다"만으로는 언제 다시 눌러야 할지 알 수 없다.
      final until = DateTime(2026, 9, 15, 19, 30);
      final matches = FakeMatchRepository(
        applyFailure: MatchFailure.cooldown,
        cooldownUntil: until,
      );
      await pumpRegister(tester, repository: matches);

      await pickSlot(tester, '19:00');
      await pickDistance(tester, TargetDistance.km5);
      await tester.tap(
        find.widgetWithText(AppButton, AppStrings.matchRegisterCta),
      );
      await tester.pumpAndSettle();

      expect(find.text(AppStrings.matchFailedCooldown(until)), findsOneWidget);
    });

    testWidgets('⚠️ 마감 경합이면 고른 시간대를 놓는다', (tester) async {
      // 그대로 두면 마감된 슬롯으로 등록을 눌러 같은 409를 다시 맞는다.
      final matches = FakeMatchRepository(
        applyFailure: MatchFailure.slotClosed,
      );
      await pumpRegister(tester, repository: matches);

      await pickSlot(tester, '19:00');
      await pickDistance(tester, TargetDistance.km5);

      // 이 사이에 마감됐다 — 서버가 409로 알려주고, 화면이 그 슬롯만 잠근다.
      await tester.tap(
        find.widgetWithText(AppButton, AppStrings.matchRegisterCta),
      );
      await tester.pumpAndSettle();

      expect(find.text(AppStrings.matchFailedSlotClosed), findsOneWidget);
      expect(find.text(AppStrings.matchTimePlaceholder), findsOneWidget);
      expect(cta(tester).onPressed, isNull);
    });

    testWidgets('⚠️ 네트워크 실패에 재시도를 권하지 않는다', (tester) async {
      // 신청됐는지 알 수 없어, 다시 보내면 중복 신청이 된다.
      final matches = FakeMatchRepository(
        applyFailure: MatchFailure.network,
      );
      await pumpRegister(tester, repository: matches);

      await pickSlot(tester, '19:00');
      await pickDistance(tester, TargetDistance.km5);
      await tester.tap(
        find.widgetWithText(AppButton, AppStrings.matchRegisterCta),
      );
      await tester.pumpAndSettle();

      expect(find.text(AppStrings.matchFailedNetwork), findsOneWidget);
    });
  });
}
