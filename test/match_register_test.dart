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
import 'package:runiverse/features/matching/domain/slot_load_failure.dart';
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

  /// 홈까지만 띄운다. 운영 안내 팝업을 보는 테스트가 쓴다.
  Future<FakeMatchRepository> pumpHome(
    WidgetTester tester, {
    FakeMatchRepository? repository,
  }) => pumpApp(tester, repository: repository);

  /// 홈에서 매칭 등록으로 간다. **운영 안내 팝업을 거친다.**
  ///
  /// 홈 CTA 는 `AppButtonV2` 로 옮겼다. 여기서 보는 건 등록 화면이지 홈의
  /// 버튼 종류가 아니라, 글자로만 찾는다.
  Future<void> openRegister(WidgetTester tester) async {
    await tester.tap(find.text(AppStrings.homeMatchCta));
    await tester.pumpAndSettle();
    await tester.tap(find.text(AppStrings.matchPolicyConfirm));
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

  Future<void> pickDistance(WidgetTester tester, TargetDistance km) async {
    await tester.tap(find.text(AppStrings.matchDistanceText(km.km)));
    await tester.pumpAndSettle();
  }

  /// 등록을 누르고 화면이 자리를 잡을 때까지 돌린다.
  ///
  /// ⚠️ `pumpAndSettle`을 쓰지 못한다. 신청에 성공하면 대기방으로 가는데,
  /// 그 화면이 카운트다운 때문에 1초 타이머를 계속 돌려 영영 잠잠해지지 않는다.
  Future<void> tapCta(WidgetTester tester) async {
    await tester.tap(find.text(AppStrings.matchRegisterCta));
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

    testWidgets('⚠️ 거리가 시간보다 위에 있다', (tester) async {
      // 목록을 받으려면 거리가 먼저 있어야 한다 — 화면 순서가 데이터가
      // 흐르는 순서와 같아진다.
      await pumpRegister(tester);

      expect(
        tester.getTopLeft(find.text(AppStrings.matchDistanceLabel)).dy,
        lessThan(tester.getTopLeft(find.text(AppStrings.matchTimeLabel)).dy),
      );
    });

    testWidgets('⚠️ 거리를 고르기 전에는 시간을 못 고른다', (tester) async {
      await pumpRegister(tester);

      await tester.tap(find.text(AppStrings.matchTimePlaceholder));
      await tester.pumpAndSettle();

      // 시트 위젯은 비공개다. **제목으로** 찾는다.
      expect(find.text(AppStrings.matchSlotSheetTitle), findsNothing);
      expect(find.text(AppStrings.matchSlotsLockedByDistance), findsOneWidget);
    });

    testWidgets('거리를 고르면 시간을 고를 수 있다', (tester) async {
      await pumpRegister(tester);

      await pickDistance(tester, TargetDistance.km5);
      await tester.tap(find.text(AppStrings.matchTimePlaceholder));
      await tester.pumpAndSettle();

      expect(find.text(AppStrings.matchSlotSheetTitle), findsOneWidget);
    });

    testWidgets('⚠️ 둘 다 골라야 CTA가 열린다', (tester) async {
      // 하나만으로 열면 서버가 400으로 거절하고, 사용자는 왜인지 모른다.
      final matches = await pumpRegister(tester);
      expect(await ctaOpens(tester, matches), isFalse);

      await pickDistance(tester, TargetDistance.km5);
      expect(await ctaOpens(tester, matches), isFalse);

      await pickSlot(tester, '10:00');
      expect(await ctaOpens(tester, matches), isTrue);
    });

    testWidgets('고른 시간이 보인다', (tester) async {
      await pumpRegister(tester);

      await pickDistance(tester, TargetDistance.km5);
      await pickSlot(tester, '10:00');

      expect(find.text('10:00'), findsOneWidget);
    });

    testWidgets('⚠️ 마감된 시간대는 목록에 남되 눌리지 않는다', (tester) async {
      // 빼면 "10:00이 왜 없지"가 되고, 목록이 줄어드는 것도 이상하게 읽힌다.
      final matches = FakeMatchRepository(
        slotList: [
          FakeMatchRepository.slotAt('10:00', selectable: false),
          FakeMatchRepository.slotAt('10:30', waiting: 2),
        ],
      );
      await pumpRegister(tester, repository: matches);
      await pickDistance(tester, TargetDistance.km5);

      await tester.tap(find.text(AppStrings.matchTimePlaceholder));
      await tester.pumpAndSettle();

      expect(find.text('10:00'), findsOneWidget);
      expect(find.text(AppStrings.matchSlotClosed), findsOneWidget);

      await tester.tap(find.text('10:00'));
      await tester.pumpAndSettle();

      // 시트가 그대로다 — 눌려서 닫혔다면 마감된 슬롯이 골라진 것이다.
      expect(find.text(AppStrings.matchSlotSheetTitle), findsOneWidget);
    });

    testWidgets('⚠️ 전부 마감이면 비었음과 같은 화면이다', (tester) async {
      // 목록은 차 있는데 고를 것이 없다. 선택기를 열어 두면 시트에 `마감`만
      // 늘어서고 등록 버튼은 영영 잠긴 채라 고장난 화면으로 읽힌다.
      final matches = FakeMatchRepository(
        slotList: [FakeMatchRepository.slotAt('10:00', selectable: false)],
      );
      await pumpRegister(tester, repository: matches);

      await pickDistance(tester, TargetDistance.km5);

      expect(find.text(AppStrings.matchSlotsEmpty), findsOneWidget);
    });

    testWidgets('⚠️ 0명인 시각에는 숫자를 적지 않는다', (tester) async {
      // `0명 대기`는 비어 있다고 알리는 꼴이라 오히려 사람을 민다.
      await pumpRegister(tester);
      await pickDistance(tester, TargetDistance.km5);

      await tester.tap(find.text(AppStrings.matchTimePlaceholder));
      await tester.pumpAndSettle();

      // 가짜의 기본 목록은 3 · 0 · 4다.
      expect(find.text(AppStrings.matchWaitingCount(3)), findsOneWidget);
      expect(find.text(AppStrings.matchWaitingCount(0)), findsNothing);
    });

    testWidgets('시트는 시각마다 그 거리의 수를 그린다', (tester) async {
      await pumpRegister(tester);
      await pickDistance(tester, TargetDistance.km5);

      await tester.tap(find.text(AppStrings.matchTimePlaceholder));
      await tester.pumpAndSettle();

      expect(find.text(AppStrings.matchWaitingCount(3)), findsOneWidget);
      expect(find.text(AppStrings.matchWaitingCount(4)), findsOneWidget);
    });
  });

  group('대기 인원 줄', () {
    testWidgets('⚠️ 거리만 골랐을 때 합계가 등록 버튼 위에 선다', (tester) async {
      // 가짜의 기본 목록 3 + 0 + 4 = 7
      await pumpRegister(tester);
      await pickDistance(tester, TargetDistance.km3);

      final banner = find.text(AppStrings.matchWaitingTotal(3, 7));
      expect(banner, findsOneWidget);
      expect(
        tester.getTopLeft(banner).dy,
        lessThan(tester.getTopLeft(find.text(AppStrings.matchRegisterCta)).dy),
      );
    });

    testWidgets('⚠️ 시간까지 고르면 그 줄이 사라진다', (tester) async {
      // 시트에서 이미 그 시각의 수를 보고 고른 사람에게 같은 말을 한 번 더
      // 적는 셈이다.
      await pumpRegister(tester);
      await pickDistance(tester, TargetDistance.km3);
      await pickSlot(tester, '10:00');

      expect(find.textContaining('대기중이에요'), findsNothing);
    });

    testWidgets('⚠️ 합계가 0이면 그 줄이 아예 없다', (tester) async {
      final matches = FakeMatchRepository(
        slotList: [
          FakeMatchRepository.slotAt('10:00'),
          FakeMatchRepository.slotAt('10:30'),
        ],
      );
      await pumpRegister(tester, repository: matches);

      await pickDistance(tester, TargetDistance.km3);

      expect(find.textContaining('대기중이에요'), findsNothing);
    });

    testWidgets('⚠️ 합계 숫자가 자릿수대로 선다', (tester) async {
      // 거리를 바꾸면 자릿수가 흔들린다. 고정폭이 아니면 줄이 튄다.
      await pumpRegister(tester);
      await pickDistance(tester, TargetDistance.km3);

      final text = tester.widget<Text>(
        find.text(AppStrings.matchWaitingTotal(3, 7)),
      );
      expect(
        text.style?.fontFeatures,
        contains(const FontFeature.tabularFigures()),
      );
    });

    testWidgets('거리를 바꾸면 합계도 바뀐다', (tester) async {
      final matches = FakeMatchRepository();
      await pumpRegister(tester, repository: matches);
      await pickDistance(tester, TargetDistance.km3);

      matches.slotList = [FakeMatchRepository.slotAt('10:00', waiting: 12)];
      await pickDistance(tester, TargetDistance.km10);

      expect(find.text(AppStrings.matchWaitingTotal(10, 12)), findsOneWidget);
    });
  });

  group('운영 안내', () {
    testWidgets('⚠️ 등록 화면에 가기 전에 정책을 한 번 알린다', (tester) async {
      await pumpHome(tester);

      await tester.tap(find.text(AppStrings.homeMatchCta));
      await tester.pumpAndSettle();

      expect(find.text(AppStrings.matchPolicyTitle), findsOneWidget);
      // 아직 넘어가지 않았다.
      expect(find.text(AppStrings.matchRegisterTitle), findsNothing);
    });

    testWidgets('확인하면 등록 화면으로 간다', (tester) async {
      await pumpHome(tester);

      await tester.tap(find.text(AppStrings.homeMatchCta));
      await tester.pumpAndSettle();
      await tester.tap(find.text(AppStrings.matchPolicyConfirm));
      await tester.pumpAndSettle();

      expect(find.text(AppStrings.matchRegisterTitle), findsOneWidget);
    });

    testWidgets('⚠️ 다음에를 고르면 홈에 남는다', (tester) async {
      // 안내를 읽고 마음이 바뀔 수 있다. 외길이면 안내가 아니라 관문이다.
      await pumpHome(tester);

      await tester.tap(find.text(AppStrings.homeMatchCta));
      await tester.pumpAndSettle();
      await tester.tap(find.text(AppStrings.matchPolicyCancel));
      await tester.pumpAndSettle();

      expect(find.text(AppStrings.matchRegisterTitle), findsNothing);
      expect(find.text(AppStrings.homeMatchCta), findsOneWidget);
    });

    testWidgets('⚠️ 시각 범위를 적지 않는다', (tester) async {
      // 18:00~22:00은 서버 설정값이다. 문구에 박아 두면 설정이 바뀌는 날
      // 화면만 거짓말을 한다.
      await pumpHome(tester);

      await tester.tap(find.text(AppStrings.homeMatchCta));
      await tester.pumpAndSettle();

      expect(find.textContaining('18:00'), findsNothing);
      expect(find.textContaining('22:00'), findsNothing);
    });
  });

  group('마감 안내', () {
    testWidgets('⚠️ 등록을 눌렀는데 오늘이 끝났으면 팝업으로 알리고 홈으로 보낸다', (tester) async {
      // 마감 경합(409)을 받아 목록을 다시 받아 보니 **남은 자리가 없다.**
      // 그 슬롯만 잠그고 스낵바를 띄우면, 다시 고를 것이 없는 화면에 사람을
      // 세워 둔 채 "마감됐어요"만 말하는 셈이다.
      final matches = FakeMatchRepository(
        applyFailure: MatchFailure.slotClosed,
        slotList: [FakeMatchRepository.slotAt('10:00')],
      );
      await pumpRegister(tester, repository: matches);

      await pickDistance(tester, TargetDistance.km5);
      await pickSlot(tester, '10:00');

      // 누르는 사이에 마감됐다 — 다시 받으면 그 하나도 닫혀 있다.
      matches.slotList = [
        FakeMatchRepository.slotAt('10:00', selectable: false),
      ];
      await tester.tap(find.text(AppStrings.matchRegisterCta));
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

      await pickDistance(tester, TargetDistance.km5);
      await pickSlot(tester, '10:00');
      await tester.tap(find.text(AppStrings.matchRegisterCta));
      await tester.pumpAndSettle();

      expect(find.text(AppStrings.matchClosedTitle), findsNothing);
      expect(find.text(AppStrings.matchFailedSlotClosed), findsOneWidget);
    });

    testWidgets('⚠️ 들어오자마자는 팝업이 뜨지 않는다', (tester) async {
      // 진입에는 서버를 부르지 않는다 — 거리가 없어 부를 수가 없다.
      await pumpRegister(tester);

      expect(find.text(AppStrings.matchClosedTitle), findsNothing);
      expect(find.text(AppStrings.matchSlotsLockedByDistance), findsOneWidget);
    });

    testWidgets('⚠️ 다시 들어오면 지난번에 고른 거리가 남지 않는다', (tester) async {
      // 남으면 **기본값처럼** 선택돼 있고, 그 거리의 낡은 숫자까지 그대로 선다.
      await pumpRegister(tester);
      await pickDistance(tester, TargetDistance.km10);
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();

      await openRegister(tester);

      expect(find.text(AppStrings.matchSlotsLockedByDistance), findsOneWidget);
    });
  });

  group('목록 조회 실패', () {
    testWidgets('⚠️ 이유가 머문다 — 스낵바로 사라지지 않는다', (tester) async {
      // 신청용 실패와 같은 자리에 담으면 화면이 스낵바를 띄우고 곧바로 지워서,
      // 잠긴 이유가 한 프레임 만에 사라진다.
      final matches = FakeMatchRepository()
        ..slotsFailure = SlotLoadFailure.network;
      await pumpRegister(tester, repository: matches);

      await pickDistance(tester, TargetDistance.km3);
      await tester.pump(const Duration(seconds: 5));

      expect(find.text(AppStrings.matchSlotsLoadFailed), findsOneWidget);
      expect(find.text(AppStrings.matchSlotsRetry), findsOneWidget);
    });

    testWidgets('다시 시도를 누르면 또 부른다', (tester) async {
      final matches = FakeMatchRepository()
        ..slotsFailure = SlotLoadFailure.network;
      await pumpRegister(tester, repository: matches);
      await pickDistance(tester, TargetDistance.km3);

      matches.slotsFailure = null;
      await tester.tap(find.text(AppStrings.matchSlotsRetry));
      await tester.pumpAndSettle();

      // 거리 선택 1 · 다시 시도 2
      expect(matches.slotsCalls, 2);
      expect(find.text(AppStrings.matchSlotsLoadFailed), findsNothing);
    });

    testWidgets('⚠️ 세션이 만료되면 다시 로그인하라고 말한다', (tester) async {
      // "불러오지 못했어요 + 다시 시도"만 뜨면 눌러도 영원히 같은 화면이다.
      // 빠져나오려면 다시 로그인해야 한다는 걸 알 길이 없다. 신청 경로는 같은
      // 상황에서 이미 그렇게 말한다 — 한 화면 안에서 두 경로가 달라선 안 된다.
      final matches = FakeMatchRepository()
        ..slotsFailure = SlotLoadFailure.sessionExpired;
      await pumpRegister(tester, repository: matches);

      await pickDistance(tester, TargetDistance.km3);

      expect(find.text(AppStrings.matchFailedExpired), findsOneWidget);
      expect(find.text(AppStrings.matchSlotsLoadFailed), findsNothing);
      // 다시 시도해 봐야 같은 답이다. 권하지 않는다.
      expect(find.text(AppStrings.matchSlotsRetry), findsNothing);
    });

    testWidgets('⚠️ 실패해도 거리 칩은 잠기지 않는다', (tester) async {
      // 거리를 다시 고르는 것이 곧 다시 시도하는 길이다.
      final matches = FakeMatchRepository()
        ..slotsFailure = SlotLoadFailure.network;
      await pumpRegister(tester, repository: matches);
      await pickDistance(tester, TargetDistance.km3);

      matches.slotsFailure = null;
      await pickDistance(tester, TargetDistance.km10);

      // km3 1 · km10 2
      expect(matches.slotsCalls, 2);
      expect(find.text(AppStrings.matchSlotsLoadFailed), findsNothing);
    });
  });

  group('신청', () {
    testWidgets('⚠️ 서버가 준 문자열을 그대로 보낸다', (tester) async {
      // 앱이 "오늘 + 10:00"을 조립하면 자정 근처에서 엉뚱한 날짜가 나간다.
      final matches = await pumpRegister(tester);
      final expected = matches.slotList.first.raw;

      await pickDistance(tester, TargetDistance.km5);
      await pickSlot(tester, '10:00');
      await tapCta(tester);

      expect(matches.appliedSlotRaw, expected);
      expect(matches.appliedDistance, TargetDistance.km5);
    });

    testWidgets('신청이 되면 홈으로 돌아간다', (tester) async {
      // 모집 중에는 갈 화면이 따로 없다. 홈 히어로가 그 상태를 보여준다.
      await pumpRegister(tester);

      await pickDistance(tester, TargetDistance.km5);
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

      await pickDistance(tester, TargetDistance.km5);
      await pickSlot(tester, '10:00');
      await tester.tap(find.text(AppStrings.matchRegisterCta));
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

      await pickDistance(tester, TargetDistance.km5);
      await pickSlot(tester, '10:00');
      await tester.tap(find.text(AppStrings.matchRegisterCta));
      await tester.pumpAndSettle();

      expect(find.text(AppStrings.matchFailedCooldown(until)), findsOneWidget);
    });

    testWidgets('⚠️ 마감 경합이면 고른 시간대를 놓는다', (tester) async {
      // 그대로 두면 마감된 슬롯으로 등록을 눌러 같은 409를 다시 맞는다.
      final matches = FakeMatchRepository(
        applyFailure: MatchFailure.slotClosed,
      );
      await pumpRegister(tester, repository: matches);

      await pickDistance(tester, TargetDistance.km5);
      await pickSlot(tester, '10:00');

      // 이 사이에 마감됐다 — 서버가 409로 알려주고, 화면이 그 슬롯만 잠근다.
      await tester.tap(find.text(AppStrings.matchRegisterCta));
      await tester.pumpAndSettle();

      expect(find.text(AppStrings.matchFailedSlotClosed), findsOneWidget);
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

      await pickDistance(tester, TargetDistance.km5);
      await pickSlot(tester, '10:00');
      expect(matches.slotsCalls, 1);

      await tester.tap(find.text(AppStrings.matchRegisterCta));
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

      await pickDistance(tester, TargetDistance.km5);
      await pickSlot(tester, '10:00');
      await tester.tap(find.text(AppStrings.matchRegisterCta));
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

      await pickDistance(tester, TargetDistance.km5);
      await pickSlot(tester, '10:00');
      await tester.tap(find.text(AppStrings.matchRegisterCta));
      await tester.pumpAndSettle();

      expect(find.text(AppStrings.matchFailedNetwork), findsOneWidget);
    });
  });
}
