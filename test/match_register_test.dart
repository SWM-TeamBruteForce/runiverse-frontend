import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runiverse/app/app.dart';
import 'package:runiverse/app/router/app_routes.dart';
import 'package:runiverse/core/storage/match_room_store.dart';
import 'package:runiverse/core/strings/app_strings.dart';
import 'package:runiverse/features/app_update/data/fake_app_version_repository.dart';
import 'package:runiverse/features/app_update/presentation/app_version_provider.dart';
import 'package:runiverse/features/home/presentation/home_page.dart';
import 'package:runiverse/features/matching/data/fake_match_repository.dart';
import 'package:runiverse/features/matching/data/fake_match_stream.dart';
import 'package:runiverse/features/matching/domain/match_failure.dart';
import 'package:runiverse/features/matching/domain/slot_board.dart';
import 'package:runiverse/features/matching/domain/slot_load_failure.dart';
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
  Future<FakeMatchRepository> pumpApp(
    WidgetTester tester, {
    FakeMatchRepository? repository,
  }) async {
    final matches = repository ?? FakeMatchRepository();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          // 스플래시가 **토큰 복원보다 먼저** 앱 버전을 확인한다. 진짜를 두면
          // dio가 서버 주소를 찾다 죽고, 판정을 못 받은 화면은 넘어가지 않는다.
          appVersionRepositoryProvider.overrideWithValue(
            FakeAppVersionRepository(),
          ),
          matchRepositoryProvider.overrideWithValue(matches),
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

    return matches;
  }

  /// 홈에서 매칭 등록으로 간다.
  ///
  /// 홈 CTA 는 `AppButtonV2` 로 옮겼다. 여기서 보는 건 등록 화면이지 홈의
  /// 버튼 종류가 아니라, 글자로만 찾는다.
  Future<void> openRegister(WidgetTester tester) async {
    await tester.tap(find.text(AppStrings.homeMatchCta));
    await tester.pumpAndSettle();
  }

  Future<FakeMatchRepository> pumpRegister(
    WidgetTester tester, {
    FakeMatchRepository? repository,
  }) async {
    final matches = await pumpApp(tester, repository: repository);
    await openRegister(tester);
    return matches;
  }

  /// 시간 시트를 열어 [time]을 고른다.
  Future<void> pickSlot(WidgetTester tester, String time) async {
    await tester.tap(find.text(AppStrings.matchTimePlaceholder));
    await tester.pumpAndSettle();
    await tester.tap(find.text(time));
    await tester.pumpAndSettle();
  }

  /// 거리 칩을 누른다. **킬로미터로 받는다** — 칩은 응답이 만든다.
  Future<void> pickDistance(WidgetTester tester, int km) async {
    await tester.tap(find.text(AppStrings.matchDistanceText(km)));
    await tester.pumpAndSettle();
  }

  /// 등록 버튼. **글자가 숫자를 달고 바뀐다**(`매칭 등록하기 · 3명 대기`)
  /// — 앞부분으로 찾는다.
  final cta = find.textContaining(AppStrings.matchRegisterCta);

  /// 등록을 누르고 화면이 자리를 잡을 때까지 돌린다.
  ///
  /// ⚠️ `pumpAndSettle`을 쓰지 못한다. 신청에 성공하면 대기방으로 가는데,
  /// 그 화면이 카운트다운 때문에 1초 타이머를 계속 돌려 영영 잠잠해지지 않는다.
  Future<void> tapCta(WidgetTester tester) async {
    await tester.tap(cta);
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  /// CTA가 열려 있는가. **부품의 `onPressed`를 보지 않는다.**
  ///
  /// 눌러 보고 **서버로 나갔는지**로 판단한다. 잠김은 부품의 속성이 아니라
  /// 화면의 약속이고, 디자인이 바뀌어도 그 약속은 그대로다.
  ///
  /// ⚠️ 먼저 기록을 비운다. 앞서 실패한 신청도 `appliedSlotRaw`를 남겨서,
  /// 비우지 않으면 잠긴 버튼을 열렸다고 읽는다.
  Future<bool> ctaOpens(
    WidgetTester tester,
    FakeMatchRepository matches,
  ) async {
    matches.appliedSlotRaw = null;
    await tapCta(tester);
    return matches.appliedSlotRaw != null;
  }

  group('고르기', () {
    testWidgets('들어오면 시간대를 갖춘다', (tester) async {
      await pumpRegister(tester);

      expect(find.byType(MatchRegisterPage), findsOneWidget);
      expect(find.text(AppStrings.matchTimePlaceholder), findsOneWidget);
    });

    testWidgets('⚠️ 시간이 거리보다 위에 있다', (tester) async {
      // 2026-10-22에 거리를 위로 올린 이유는 **조회가 거리를 필수로 받았기
      // 때문**이다. 그 제약이 사라졌으므로 시안의 순서로 돌아간다.
      await pumpRegister(tester);

      expect(
        tester.getTopLeft(find.text(AppStrings.matchTimeLabel)).dy,
        lessThan(
          tester.getTopLeft(find.text(AppStrings.matchDistanceLabel)).dy,
        ),
      );
    });

    testWidgets('⚠️ 거리를 안 골라도 시간을 고를 수 있다', (tester) async {
      // 한 번에 다 받으므로 잠글 이유가 없다. 시트의 숫자는 거리와 무관한
      // 합계다(설계 5-3).
      await pumpRegister(tester);

      await tester.tap(find.text(AppStrings.matchTimePlaceholder));
      await tester.pumpAndSettle();

      // 시트 위젯은 비공개다. **제목으로** 찾는다.
      expect(find.text(AppStrings.matchSlotSheetTitle), findsOneWidget);
    });

    testWidgets('⚠️ 거리 칩이 응답에서 선다', (tester) async {
      // 앱이 목록을 갖지 않는다 — 서버가 7km를 추가하면 그대로 나타나야 한다.
      final matches = FakeMatchRepository(
        board: SlotBoard([
          DistanceSlots(
            meters: 7000,
            slots: [FakeMatchRepository.slotAt('10:00')],
          ),
        ]),
      );
      await pumpRegister(tester, repository: matches);

      expect(find.text(AppStrings.matchDistanceText(7)), findsOneWidget);
      expect(find.text(AppStrings.matchDistanceText(5)), findsNothing);
    });

    testWidgets('⚠️ 둘 다 골라야 CTA가 열린다', (tester) async {
      // 하나만으로 열면 서버가 400으로 거절하고, 사용자는 왜인지 모른다.
      final matches = await pumpRegister(tester);
      expect(await ctaOpens(tester, matches), isFalse);

      await pickDistance(tester, 5);
      expect(await ctaOpens(tester, matches), isFalse);

      await pickSlot(tester, '10:00');
      expect(await ctaOpens(tester, matches), isTrue);
    });

    testWidgets('고른 시간이 보인다', (tester) async {
      await pumpRegister(tester);

      await pickSlot(tester, '10:00');

      expect(find.text('10:00'), findsOneWidget);
    });

    testWidgets('⚠️ 마감된 시간대는 목록에 남되 눌리지 않는다', (tester) async {
      // 빼면 "10:00이 왜 없지"가 되고, 목록이 줄어드는 것도 이상하게 읽힌다.
      final matches = FakeMatchRepository(
        board: SlotBoard([
          DistanceSlots(
            meters: 3000,
            slots: [
              FakeMatchRepository.slotAt('10:00', selectable: false),
              FakeMatchRepository.slotAt('10:30', waiting: 2),
            ],
          ),
        ]),
      );
      await pumpRegister(tester, repository: matches);

      await tester.tap(find.text(AppStrings.matchTimePlaceholder));
      await tester.pumpAndSettle();

      expect(find.text('10:00'), findsOneWidget);
      expect(find.text(AppStrings.matchSlotClosed), findsOneWidget);

      await tester.tap(find.text('10:00'));
      await tester.pumpAndSettle();

      // 시트가 그대로다 — 눌려서 닫혔다면 마감된 시각이 골라진 것이다.
      expect(find.text(AppStrings.matchSlotSheetTitle), findsOneWidget);
    });

    testWidgets('⚠️ 전부 마감이면 진입에서 바로 알린다', (tester) async {
      // 판은 차 있는데 고를 것이 없다. 거리를 눌러 봐야 알게 두면, 잠긴
      // 선택기 앞에서 왜 아무것도 못 고르는지 모른 채 서 있게 된다.
      final matches = FakeMatchRepository(
        board: SlotBoard([
          DistanceSlots(
            meters: 3000,
            slots: [FakeMatchRepository.slotAt('10:00', selectable: false)],
          ),
        ]),
      );
      await pumpRegister(tester, repository: matches);

      expect(find.text(AppStrings.matchClosedTitle), findsOneWidget);
    });

    testWidgets('⚠️ 0명인 시각에는 숫자를 적지 않는다', (tester) async {
      // `0명 대기`는 비어 있다고 알리는 꼴이라 오히려 사람을 민다.
      await pumpRegister(tester);

      await tester.tap(find.text(AppStrings.matchTimePlaceholder));
      await tester.pumpAndSettle();

      // 가짜 기본 판의 시각 합계는 5 · 0 · 6이다.
      expect(find.text(AppStrings.matchWaitingCount(5)), findsOneWidget);
      expect(find.text(AppStrings.matchWaitingCount(0)), findsNothing);
    });

    testWidgets('⚠️ 시트는 모든 거리를 더한 수를 그린다', (tester) async {
      // 거리를 고르기 전에 열 수 있으므로, 시트의 숫자는 거리와 무관한
      // 합계여야 한다. 3km 하나의 수를 그리면 다른 거리를 고를 사람에게
      // 거짓이 된다.
      await pumpRegister(tester);

      await tester.tap(find.text(AppStrings.matchTimePlaceholder));
      await tester.pumpAndSettle();

      expect(
        find.text(AppStrings.matchWaitingCount(5)),
        findsOneWidget,
        reason: '10:00 = 3 + 2 + 0',
      );
      expect(
        find.text(AppStrings.matchWaitingCount(6)),
        findsOneWidget,
        reason: '11:00 = 4 + 1 + 1',
      );
    });
  });

  group('등록 버튼의 숫자', () {
    testWidgets('⚠️ 둘 다 고르면 그 조건의 수가 버튼에 붙는다', (tester) async {
      // 10:00 × 3km는 3명이다. 시트에 선 합계 5명과 다른 숫자라는 것이 요점
      // 이다 — 거리를 고르면 숫자가 **진짜 그 조건의 수**로 좁혀진다.
      await pumpRegister(tester);
      await pickSlot(tester, '10:00');
      await pickDistance(tester, 3);

      expect(find.text(AppStrings.matchRegisterCtaWaiting(3)), findsOneWidget);
    });

    testWidgets('거리를 바꾸면 숫자도 바뀐다', (tester) async {
      await pumpRegister(tester);
      await pickSlot(tester, '10:00');

      await pickDistance(tester, 3);
      expect(find.text(AppStrings.matchRegisterCtaWaiting(3)), findsOneWidget);

      await pickDistance(tester, 5);
      expect(find.text(AppStrings.matchRegisterCtaWaiting(2)), findsOneWidget);
    });

    testWidgets('⚠️ 하나만 골랐으면 숫자가 없다', (tester) async {
      await pumpRegister(tester);
      await pickSlot(tester, '10:00');

      expect(find.text(AppStrings.matchRegisterCta), findsOneWidget);
    });

    testWidgets('⚠️ 0명이면 숫자를 붙이지 않는다', (tester) async {
      // 10:00 × 10km는 0명이다. `0명 대기`는 비어 있다고 알리는 꼴이라
      // 오히려 사람을 민다 — 버튼은 `매칭 등록하기`로 남는다.
      await pumpRegister(tester);
      await pickSlot(tester, '10:00');
      await pickDistance(tester, 10);

      expect(find.text(AppStrings.matchRegisterCta), findsOneWidget);
    });
  });

  group('팝업으로 알리는 두 가지', () {
    testWidgets('⚠️ 마감 경합이면 시간 규칙을 팝업으로 알린다', (tester) async {
      // "방금 그 시간대는 마감됐어요" 한 줄로는 **언제까지 누르면 되는지**
      // 알 수 없다. 운영 규칙이라 한 줄로는 전해지지 않는다.
      final matches = FakeMatchRepository(
        applyFailure: MatchFailure.slotClosed,
      );
      await pumpRegister(tester, repository: matches);

      await pickDistance(tester, 5);
      await pickSlot(tester, '10:00');
      await tester.tap(cta);
      await tester.pumpAndSettle();

      expect(find.text(AppStrings.matchSlotClosedTitle), findsOneWidget);
      expect(find.textContaining('18:00'), findsOneWidget);
      expect(find.textContaining('18:50'), findsOneWidget);
    });

    testWidgets('⚠️ 마감 경합 팝업은 화면에 남는다', (tester) async {
      // 다른 시각이 아직 열려 있다. 홈으로 내보내면 다시 신청할 길까지 끊는다.
      final matches = FakeMatchRepository(
        applyFailure: MatchFailure.slotClosed,
      );
      await pumpRegister(tester, repository: matches);

      await pickDistance(tester, 5);
      await pickSlot(tester, '10:00');
      await tester.tap(cta);
      await tester.pumpAndSettle();
      await tester.tap(find.text(AppStrings.matchPolicyClose));
      await tester.pumpAndSettle();

      expect(find.text(AppStrings.matchRegisterTitle), findsOneWidget);
    });

    testWidgets('⚠️ 이탈 제재는 규칙과 해제 시각을 함께 말한다', (tester) async {
      final until = DateTime(2026, 7, 26, 7, 30);
      final matches = FakeMatchRepository(
        applyFailure: MatchFailure.cooldown,
        cooldownUntil: until,
      );
      await pumpRegister(tester, repository: matches);

      await pickDistance(tester, 5);
      await pickSlot(tester, '10:00');
      await tester.tap(cta);
      await tester.pumpAndSettle();

      expect(find.text(AppStrings.matchCooldownTitle), findsOneWidget);
      // ⚠️ 같은 문구가 화면 아래 안내에도 있다. **팝업 안에서** 찾는다.
      expect(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.text(AppStrings.matchCooldownRule),
        ),
        findsOneWidget,
      );
      expect(find.text(AppStrings.matchCooldownUntil(until)), findsOneWidget);
    });

    testWidgets('⚠️ 해제 시각을 모르면 그 줄을 만들지 않는다', (tester) async {
      // 없는 시각을 지어내면 그때까지 기다린 사람이 또 막힌다.
      final matches = FakeMatchRepository(applyFailure: MatchFailure.cooldown);
      await pumpRegister(tester, repository: matches);

      await pickDistance(tester, 5);
      await pickSlot(tester, '10:00');
      await tester.tap(cta);
      await tester.pumpAndSettle();

      expect(find.text(AppStrings.matchCooldownTitle), findsOneWidget);
      expect(find.textContaining('다시 신청할 수 있어요'), findsNothing);
    });

    testWidgets('⚠️ 나머지 실패는 스낵바 그대로다', (tester) async {
      // "다시 해보세요" 한 마디면 끝이라 팝업으로 막을 이유가 없다.
      final matches = FakeMatchRepository(applyFailure: MatchFailure.network);
      await pumpRegister(tester, repository: matches);

      await pickDistance(tester, 5);
      await pickSlot(tester, '10:00');
      await tester.tap(cta);
      await tester.pumpAndSettle();

      expect(find.byType(AlertDialog), findsNothing);
      expect(find.text(AppStrings.matchFailedNetwork), findsOneWidget);
    });
  });

  group('마감 안내', () {
    testWidgets('⚠️ 등록을 눌렀는데 오늘이 끝났으면 팝업으로 알리고 홈으로 보낸다', (tester) async {
      // 마감 경합(409)을 받아 목록을 다시 받아 보니 **남은 자리가 없다.**
      // 그 슬롯만 잠그고 스낵바를 띄우면, 다시 고를 것이 없는 화면에 사람을
      // 세워 둔 채 "마감됐어요"만 말하는 셈이다.
      final matches = FakeMatchRepository(
        applyFailure: MatchFailure.slotClosed,
        board: SlotBoard([
          DistanceSlots(
            meters: 5000,
            slots: [FakeMatchRepository.slotAt('10:00')],
          ),
        ]),
      );
      await pumpRegister(tester, repository: matches);

      await pickDistance(tester, 5);
      await pickSlot(tester, '10:00');

      // 누르는 사이에 마감됐다 — 다시 받으면 그 하나도 닫혀 있다.
      matches.board = SlotBoard([
        DistanceSlots(
          meters: 5000,
          slots: [FakeMatchRepository.slotAt('10:00', selectable: false)],
        ),
      ]);
      await tester.tap(cta);
      await tester.pumpAndSettle();

      expect(find.text(AppStrings.matchClosedTitle), findsOneWidget);
      // ⚠️ **빈손으로 돌려보내지 않는다.** 혼자 뛰기는 마감과 무관하다.
      expect(find.textContaining(AppStrings.homeSoloCta), findsOneWidget);

      await tester.tap(find.text(AppStrings.matchClosedGoHome));
      await tester.pumpAndSettle();

      expect(find.text(AppStrings.matchRegisterTitle), findsNothing);
    });

    testWidgets('⚠️ 아직 고를 자리가 남았으면 팝업이 아니라 스낵바다', (tester) async {
      // 그 시각만 놓친 것이다. 홈으로 쫓아내면 다른 시각으로 다시 신청할
      // 길까지 끊는다.
      final matches = FakeMatchRepository(
        applyFailure: MatchFailure.slotClosed,
      );
      await pumpRegister(tester, repository: matches);

      await pickDistance(tester, 5);
      await pickSlot(tester, '10:00');
      await tester.tap(cta);
      await tester.pumpAndSettle();

      expect(find.text(AppStrings.matchClosedTitle), findsNothing);
      expect(find.text(AppStrings.matchSlotClosedTitle), findsOneWidget);
    });

    testWidgets('⚠️ 고를 자리가 남았으면 들어와도 팝업이 없다', (tester) async {
      await pumpRegister(tester);

      expect(find.text(AppStrings.matchClosedTitle), findsNothing);
      expect(find.text(AppStrings.matchTimePlaceholder), findsOneWidget);
    });

    testWidgets('⚠️ 다시 들어오면 지난번에 고른 것이 남지 않는다', (tester) async {
      // 남으면 **기본값처럼** 선택돼 있고, 그 거리의 낡은 숫자까지 그대로 선다.
      final matches = await pumpRegister(tester);
      await pickSlot(tester, '10:00');
      await pickDistance(tester, 10);
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();

      await openRegister(tester);

      expect(find.text(AppStrings.matchTimePlaceholder), findsOneWidget);
      expect(await ctaOpens(tester, matches), isFalse);
    });
  });

  group('목록 조회 실패', () {
    testWidgets('⚠️ 이유가 머문다 — 스낵바로 사라지지 않는다', (tester) async {
      // 신청용 실패와 같은 자리에 담으면 화면이 스낵바를 띄우고 곧바로 지워서,
      // 잠긴 이유가 한 프레임 만에 사라진다.
      final matches = FakeMatchRepository()
        ..slotsFailure = SlotLoadFailure.network;
      await pumpRegister(tester, repository: matches);
      await tester.pump(const Duration(seconds: 5));

      expect(find.text(AppStrings.matchSlotsLoadFailed), findsOneWidget);
      expect(find.text(AppStrings.matchSlotsRetry), findsOneWidget);
    });

    testWidgets('⚠️ 다시 시도가 유일한 길이다', (tester) async {
      // 전에는 거리를 다시 누르는 것이 곧 재조회여서, 이 버튼이 없어도
      // 빠져나올 수 있었다. 이제 부르는 곳은 `load()` 하나다.
      final matches = FakeMatchRepository()
        ..slotsFailure = SlotLoadFailure.network;
      await pumpRegister(tester, repository: matches);

      matches.slotsFailure = null;
      await tester.tap(find.text(AppStrings.matchSlotsRetry));
      await tester.pumpAndSettle();

      // 진입 1 · 다시 시도 2
      expect(matches.slotsCalls, 2);
      expect(find.text(AppStrings.matchSlotsLoadFailed), findsNothing);
      expect(find.text(AppStrings.matchTimePlaceholder), findsOneWidget);
    });

    testWidgets('⚠️ 세션이 만료되면 다시 로그인하라고 말한다', (tester) async {
      // "불러오지 못했어요 + 다시 시도"만 뜨면 눌러도 영원히 같은 화면이다.
      // 빠져나오려면 다시 로그인해야 한다는 걸 알 길이 없다. 신청 경로는 같은
      // 상황에서 이미 그렇게 말한다 — 한 화면 안에서 두 경로가 달라선 안 된다.
      final matches = FakeMatchRepository()
        ..slotsFailure = SlotLoadFailure.sessionExpired;
      await pumpRegister(tester, repository: matches);

      expect(find.text(AppStrings.matchFailedExpired), findsOneWidget);
      expect(find.text(AppStrings.matchSlotsLoadFailed), findsNothing);
      // 다시 시도해 봐야 같은 답이다. 권하지 않는다.
      expect(find.text(AppStrings.matchSlotsRetry), findsNothing);
    });

    testWidgets('⚠️ 실패하면 거리 칩이 아예 서지 않는다', (tester) async {
      // 칩은 응답이 만든다 — 판이 없으면 세울 것이 없다. 빈 자리를 남기면
      // `목표 거리`라는 글자만 떠 있어 무엇이 빠진 것인지 알 수 없다. 까닭은
      // 시간 선택기 아래 줄이 말한다.
      final matches = FakeMatchRepository()
        ..slotsFailure = SlotLoadFailure.network;
      await pumpRegister(tester, repository: matches);

      expect(find.text(AppStrings.matchDistanceText(3)), findsNothing);
      expect(find.text(AppStrings.matchSlotsLoadFailed), findsOneWidget);
    });
  });

  group('신청', () {
    testWidgets('⚠️ 서버가 준 문자열을 그대로 보낸다', (tester) async {
      // 앱이 "오늘 + 10:00"을 조립하면 자정 근처에서 엉뚱한 날짜가 나간다.
      final matches = await pumpRegister(tester);
      final expected = matches.board.distances.first.slots.first.raw;

      await pickDistance(tester, 5);
      await pickSlot(tester, '10:00');
      await tapCta(tester);

      expect(matches.appliedSlotRaw, expected);
      expect(matches.appliedMeters, 5000);
    });

    testWidgets('신청이 되면 홈으로 돌아간다', (tester) async {
      // 모집 중에는 갈 화면이 따로 없다. 홈 히어로가 그 상태를 보여준다.
      await pumpRegister(tester);

      await pickDistance(tester, 5);
      await pickSlot(tester, '10:00');
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

      await pickDistance(tester, 5);
      await pickSlot(tester, '10:00');
      await tester.tap(cta);
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

      await pickDistance(tester, 5);
      await pickSlot(tester, '10:00');
      await tester.tap(cta);
      await tester.pumpAndSettle();

      expect(find.text(AppStrings.matchCooldownUntil(until)), findsOneWidget);
    });

    testWidgets('⚠️ 마감 경합이면 고른 시간대를 놓는다', (tester) async {
      // 그대로 두면 마감된 슬롯으로 등록을 눌러 같은 409를 다시 맞는다.
      final matches = FakeMatchRepository(
        applyFailure: MatchFailure.slotClosed,
      );
      await pumpRegister(tester, repository: matches);

      await pickDistance(tester, 5);
      await pickSlot(tester, '10:00');

      // 이 사이에 마감됐다 — 서버가 409로 알려주고, 화면이 그 슬롯만 잠근다.
      await tester.tap(cta);
      await tester.pumpAndSettle();

      expect(find.text(AppStrings.matchSlotClosedTitle), findsOneWidget);
      expect(find.text(AppStrings.matchTimePlaceholder), findsOneWidget);
      expect(await ctaOpens(tester, matches), isFalse);
    });

    testWidgets('⚠️ 마감 경합 뒤에는 목록을 다시 받는다', (tester) async {
      // 서버가 준 `selectable`은 받은 시점의 사진이다. 그사이 **다른 시각들도**
      // 마감됐을 수 있는데, 안 받으면 화면이 그것을 모른 채로 남는다.
      final matches = FakeMatchRepository(
        applyFailure: MatchFailure.slotClosed,
      );
      await pumpRegister(tester, repository: matches);

      // ⚠️ **진입 한 번이 전부다.** 고르는 것으로는 더 부르지 않는다.
      await pickSlot(tester, '10:00');
      await pickDistance(tester, 5);
      expect(matches.slotsCalls, 1);

      await tester.tap(cta);
      await tester.pumpAndSettle();

      expect(matches.slotsCalls, 2, reason: '409 뒤에 다시 받는다');
    });

    testWidgets('⚠️ 마감 경합 문구가 두 번 뜨지 않는다', (tester) async {
      // 재조회가 실패 문구를 다시 세우면 **사라졌던 스낵바가 다시 나타나고**
      // 4초 타이머가 처음부터 돈다.
      final matches = FakeMatchRepository(
        applyFailure: MatchFailure.slotClosed,
      );
      await pumpRegister(tester, repository: matches);

      await pickDistance(tester, 5);
      await pickSlot(tester, '10:00');
      await tester.tap(cta);
      await tester.pumpAndSettle();

      // 스낵바가 스스로 사라질 때까지 둔다.
      await tester.pump(const Duration(seconds: 6));
      await tester.pumpAndSettle();

      expect(find.text(AppStrings.matchFailedSlotClosed), findsNothing);
    });

    testWidgets('⚠️ 네트워크 실패에 재시도를 권하지 않는다', (tester) async {
      // 신청됐는지 알 수 없어, 다시 보내면 중복 신청이 된다.
      final matches = FakeMatchRepository(applyFailure: MatchFailure.network);
      await pumpRegister(tester, repository: matches);

      await pickDistance(tester, 5);
      await pickSlot(tester, '10:00');
      await tester.tap(cta);
      await tester.pumpAndSettle();

      expect(find.text(AppStrings.matchFailedNetwork), findsOneWidget);
    });
  });
}
