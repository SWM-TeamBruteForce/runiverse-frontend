import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:runiverse/app/router/app_routes.dart';
import 'package:runiverse/core/storage/match_room_store.dart';
import 'package:runiverse/core/strings/app_strings.dart';
import 'package:runiverse/core/theme/app_theme.dart';
import 'package:runiverse/core/widgets/v2/app_button.dart';
import 'package:runiverse/features/matching/data/fake_match_repository.dart';
import 'package:runiverse/features/matching/domain/invite_limits.dart';
import 'package:runiverse/features/matching/presentation/invite_register_page.dart';
import 'package:runiverse/features/matching/data/fake_match_stream.dart';
import 'package:runiverse/features/matching/presentation/match_room_provider.dart';
import 'package:runiverse/features/matching/presentation/invite_register_provider.dart';
import 'package:runiverse/features/matching/presentation/match_register_provider.dart';
import 'package:runiverse/features/session/data/fake_user_status_repository.dart';
import 'package:runiverse/features/session/presentation/user_status_provider.dart';

/// 초대 등록 화면.
///
/// ## ⚠️ 바로가기가 `5km · 하프 · 풀`이다
///
/// 매칭의 3/5/10은 서버가 같은 조건끼리 묶는 **버킷** 때문에 있는 값이고 초대
/// 방에는 버킷이 없다. 타자로 치기 고약하고 이름이 있는 거리만 남긴다.
void main() {
  Future<FakeMatchRepository> pump(WidgetTester tester, {DateTime? now}) async {
    final matches = FakeMatchRepository();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          matchRepositoryProvider.overrideWithValue(matches),
          matchRoomStoreProvider.overrideWithValue(InMemoryMatchRoomStore()),
        ],
        child: MaterialApp(
          theme: AppTheme.dark(),
          home: InviteRegisterPage(now: now),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return matches;
  }

  AppButtonV2 submitButton(WidgetTester tester) => tester.widget<AppButtonV2>(
    find.widgetWithText(AppButtonV2, AppStrings.inviteRegisterSubmit),
  );

  group('바로가기', () {
    testWidgets('⚠️ 5km · 하프 · 풀 셋이다', (tester) async {
      await pump(tester);

      expect(find.text(AppStrings.inviteRegisterShortcut5), findsOneWidget);
      expect(find.text(AppStrings.inviteRegisterShortcutHalf), findsOneWidget);
      expect(find.text(AppStrings.inviteRegisterShortcutFull), findsOneWidget);
    });

    testWidgets('⚠️ 매칭의 3km·10km가 없다', (tester) async {
      // 버킷 때문에 있던 값이다. 초대에는 그 이유가 없다.
      await pump(tester);

      expect(find.text('3km'), findsNothing);
      expect(find.text('10km'), findsNothing);
    });

    testWidgets('⚠️ 세 칸이 균등하게 깔린다', (tester) async {
      // 왼쪽으로 쏠리면 오른쪽 빈자리가 "칩이 더 있는데 잘렸나"로 읽힌다.
      await pump(tester);

      final widths = [
        for (final label in [
          AppStrings.inviteRegisterShortcut5,
          AppStrings.inviteRegisterShortcutHalf,
          AppStrings.inviteRegisterShortcutFull,
        ])
          tester
              .getSize(
                find
                    .ancestor(
                      of: find.text(label),
                      matching: find.byType(Expanded),
                    )
                    .first,
              )
              .width,
      ];

      expect(widths[1], moreOrLessEquals(widths[0], epsilon: 0.5));
      expect(widths[2], moreOrLessEquals(widths[0], epsilon: 0.5));
    });

    testWidgets('누르면 입력란이 그 값으로 채워진다', (tester) async {
      await pump(tester);

      await tester.tap(find.text(AppStrings.inviteRegisterShortcutHalf));
      await tester.pumpAndSettle();

      // 21,098m → 21.098km.
      expect(find.text('21.098'), findsOneWidget);
    });

    testWidgets('풀을 누르면 상한이 들어간다', (tester) async {
      await pump(tester);

      await tester.tap(find.text(AppStrings.inviteRegisterShortcutFull));
      await tester.pumpAndSettle();

      expect(find.text('42.195'), findsOneWidget);
      expect(InviteLimits.fullMeters, InviteLimits.maxMeters);
    });
  });

  group('보내기 버튼', () {
    testWidgets('시각을 안 고르면 잠겨 있다', (tester) async {
      await pump(tester);

      await tester.tap(find.text(AppStrings.inviteRegisterShortcut5));
      await tester.pumpAndSettle();

      expect(submitButton(tester).onPressed, isNull);
    });

    testWidgets('거리를 안 고르면 잠겨 있다', (tester) async {
      await pump(tester);

      expect(submitButton(tester).onPressed, isNull);
    });
  });

  group('고를 수 있는 범위를 적는다', () {
    testWidgets('⚠️ 하드코딩한 운영값이라 화면에 밝힌다', (tester) async {
      await pump(tester);

      expect(find.text(AppStrings.inviteRegisterDistanceRange), findsOneWidget);
      // 시각 범위도 적는다 — 서버가 거절하기 전에 알려야 한다.
      expect(find.textContaining('사이로 정할 수 있어요'), findsOneWidget);
    });
  });

  group('⚠️ 오늘이 끝났을 때', () {
    /// KST 23:50에 해당하는 순간. `wallOf`가 +9시간을 하므로 UTC 14:50이다.
    final closed = DateTime.utc(2026, 10, 29, 14, 50);

    testWidgets('피커 대신 오늘은 못 만든다고 말한다', (tester) async {
      // 바닥(지금 +11분)이 천장(오늘 23:59)을 넘었다. 빈 피커만 두면 고장으로
      // 읽힌다.
      await pump(tester, now: closed);

      expect(find.text(AppStrings.inviteRegisterClosedToday), findsOneWidget);
      expect(find.text(AppStrings.inviteRegisterWhen), findsNothing);
      expect(find.text(AppStrings.inviteRegisterShortcut5), findsNothing);
    });

    testWidgets('자정이 지나면 다시 열린다고 알린다', (tester) async {
      await pump(tester, now: closed);

      expect(
        find.text(AppStrings.inviteRegisterClosedTodayWhy),
        findsOneWidget,
      );
    });

    testWidgets('23:48에는 아직 피커가 있다', (tester) async {
      await pump(tester, now: DateTime.utc(2026, 10, 29, 14, 48));

      expect(find.text(AppStrings.inviteRegisterShortcut5), findsOneWidget);
      expect(find.text(AppStrings.inviteRegisterClosedToday), findsNothing);
    });
  });

  group('⚠️ 입력란을 비우면 거리가 없어진다', () {
    testWidgets('하프를 눌렀다 지우면 버튼이 잠긴다', (tester) async {
      // 안 그러면 입력란은 비었는데 21km 방이 만들어진다. 초대 취소가 없어서
      // 나가는 것 말고 되돌릴 길이 없다.
      await pump(tester);

      await tester.tap(find.text(AppStrings.inviteRegisterShortcutHalf));
      await tester.pumpAndSettle();
      expect(find.text('21.098'), findsOneWidget);

      await tester.enterText(find.byType(TextField), '');
      await tester.pumpAndSettle();

      expect(submitButton(tester).onPressed, isNull);
    });

    testWidgets('읽을 수 없는 값도 비운 것으로 본다', (tester) async {
      await pump(tester);

      await tester.tap(find.text(AppStrings.inviteRegisterShortcut5));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '1.2.3');
      await tester.pumpAndSettle();

      expect(submitButton(tester).onPressed, isNull);
    });
  });

  group('⚠️ 방을 만든 뒤', () {
    testWidgets('스트림에 붙고 상태를 다시 읽는다', (tester) async {
      // 안 붙으면 방 화면이 **첫 스냅샷을 영영 기다린다** — 사용자에게는
      // 로딩만 도는 화면이다. 방은 서버에 멀쩡히 만들어져 있다.
      final matches = FakeMatchRepository();
      final stream = FakeMatchStream();
      final statuses = FakeUserStatusRepository();
      final container = ProviderContainer(
        overrides: [
          matchRepositoryProvider.overrideWithValue(matches),
          matchRoomStoreProvider.overrideWithValue(InMemoryMatchRoomStore()),
          matchStreamProvider.overrideWithValue(stream),
          userStatusRepositoryProvider.overrideWithValue(statuses),
        ],
      );
      addTearDown(container.dispose);

      // ⚠️ **홈에서 밀려 들어온 상태를 재현한다.** 방에서 나갈 때 돌아갈 곳이
      // 있어야 하고, 그것이 이 테스트의 요점이다.
      final router = GoRouter(
        initialLocation: AppRoutes.home,
        routes: [
          GoRoute(
            path: AppRoutes.home,
            builder: (_, _) => const Scaffold(body: Text('홈')),
          ),
          GoRoute(
            path: AppRoutes.inviteRegister,
            builder: (_, _) =>
                InviteRegisterPage(now: DateTime.utc(2026, 10, 29, 10)),
          ),
          GoRoute(
            path: AppRoutes.matchRoom,
            builder: (_, _) => const Scaffold(body: Text('방')),
          ),
        ],
      );
      addTearDown(router.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp.router(
            theme: AppTheme.dark(),
            routerConfig: router,
          ),
        ),
      );
      await tester.pumpAndSettle();

      router.push(AppRoutes.inviteRegister);
      await tester.pumpAndSettle();

      // 시각과 거리를 고른다. 피커를 거치지 않고 provider로 직접 세운다 —
      // 여기서 보려는 것은 보낸 **뒤**의 일이다.
      container.read(inviteRegisterProvider.notifier)
        ..pickTime(DateTime(2026, 10, 29, 19, 30))
        ..setMeters(5000);
      await tester.pumpAndSettle();

      await tester.tap(find.text(AppStrings.inviteRegisterSubmit));
      await tester.pumpAndSettle();

      expect(matches.createdMeters, 5000);
      // 붙어야 방 화면이 스냅샷을 받는다.
      expect(stream.connects, 1);
      // 상태도 새로 읽어야 홈과 복구가 방을 안다.
      expect(statuses.calls, greaterThan(0));
      expect(find.text('방'), findsOneWidget);
      // 등록 화면은 치운다 — 뒤로 가서 또 방을 만들 자리가 아니다.
      expect(find.text(AppStrings.inviteRegisterSubmit), findsNothing);

      // ⚠️ **홈이 아래에 남아야 한다.** `go`로 들어가면 스택이 날아가고, 방에서
      // 나갈 때 `pop()`이 아무 일도 안 해 **빈 방 화면에 갇힌다.**
      expect(router.canPop(), isTrue);
      router.pop();
      await tester.pumpAndSettle();
      expect(find.text('홈'), findsOneWidget);
    });
  });
}
