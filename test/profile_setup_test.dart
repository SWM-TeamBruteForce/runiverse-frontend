import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:runiverse/app/router/app_routes.dart';
import 'package:runiverse/core/storage/body_profile_provider.dart';
import 'package:runiverse/core/storage/body_profile_store.dart';
import 'package:runiverse/core/storage/sign_in_memory_store.dart';
import 'package:runiverse/core/storage/token_store.dart';
import 'package:runiverse/core/strings/app_strings.dart';
import 'package:runiverse/core/theme/app_theme.dart';
import 'package:runiverse/core/widgets/v2/app_button.dart';
import 'package:runiverse/core/widgets/v2/field_action.dart';
import 'package:runiverse/features/auth/presentation/auth_provider.dart';
import 'package:runiverse/features/onboarding/data/fake_onboarding_repository.dart';
import 'package:runiverse/features/onboarding/domain/body_rule.dart';
import 'package:runiverse/features/onboarding/domain/nickname_rule.dart';
import 'package:runiverse/features/onboarding/domain/onboarding_failure.dart';
import 'package:runiverse/features/onboarding/presentation/onboarding_provider.dart';
import 'package:runiverse/features/onboarding/presentation/profile_setup_page.dart';

/// 프로필 등록(S04) — **한 화면 폼**이 지키는 것.
///
/// ## ⚠️ 2026-09-30에 화면이 바뀌었다
///
/// 한 번에 하나씩 묻던 화면이었다. 그때 보던 것들은 이제 없다.
///
/// | 사라진 규칙 | 왜 |
/// |---|---|
/// | 답하기 전에는 다음 질문이 안 보인다 | 여섯 칸이 처음부터 다 보인다 |
/// | 답한 줄을 누르면 그 질문으로 돌아간다 | 아무 칸이나 바로 고친다 |
/// | 칩을 고르면 곧바로 다음으로 넘어간다 | 넘어갈 단계가 없다 |
///
/// 대신 **고르던 값을 치게 되면서** 지켜야 할 것이 생겼다 — 못 만들 값을
/// 막는 일이다. 규칙 자체는 `body_rule_test.dart`가 보고, 여기서는 화면이
/// 그 규칙을 **쓰는지**를 본다.
///
/// 닉네임 규칙은 화면이 바뀌어도 그대로다. 그 부분은 옮겨 왔다.
void main() {
  Future<void> pumpPage(
    WidgetTester tester, {
    FakeOnboardingRepository? onboarding,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          // 앱은 SecureTokenStore를 쓰는데 그것은 플랫폼 채널을 부른다.
          tokenStoreProvider.overrideWithValue(InMemoryTokenStore()),
          signInMemoryStoreProvider.overrideWithValue(
            InMemorySignInMemoryStore(),
          ),
          onboardingRepositoryProvider.overrideWithValue(
            onboarding ?? FakeOnboardingRepository(latency: Duration.zero),
          ),
          // ⚠️ 전송에 성공하면 신체 정보를 기기에 남긴다. 기본 구현이
          // 플랫폼 채널을 부르는데 테스트에는 채널이 없어 거기서 멈춘다.
          bodyProfileStoreProvider.overrideWithValue(
            InMemoryBodyProfileStore(),
          ),
        ],
        // ⚠️ 라우터를 붙인다. 전송에 성공하면 화면을 떠나는데, `MaterialApp`
        // 만으로는 `context.canPop()`(go_router)이 설 자리가 없어 거기서
        // 죽는다 — 옛 테스트가 성공 제출을 한 번도 안 눌러본 이유다.
        child: MaterialApp.router(
          theme: AppTheme.dark(),
          routerConfig: GoRouter(
            initialLocation: '/setup',
            routes: [
              GoRoute(
                path: '/setup',
                builder: (_, _) => const ProfileSetupPage(),
              ),
              GoRoute(
                path: AppRoutes.home,
                builder: (_, _) => const SizedBox.shrink(),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  // 칸 순서. 페이스는 [TextField]가 아니라 누르면 시트가 열리는 칸이다.
  const nicknameField = 0;
  const birthField = 1;
  const heightField = 2;
  const weightField = 3;

  Future<void> type(WidgetTester tester, int index, String value) async {
    await tester.enterText(find.byType(TextField).at(index), value);
    await tester.pumpAndSettle();
  }

  /// 하단 CTA가 눌리는가.
  bool nextEnabled(WidgetTester tester) {
    final button = tester.widget<AppButtonV2>(
      find.widgetWithText(AppButtonV2, AppStrings.profileNext),
    );
    return button.onPressed != null;
  }

  /// 닉네임 칸 안의 '중복확인'. 겹치는 것을 이미 알면 잠겨 있어야 한다.
  bool confirmEnabled(WidgetTester tester) {
    final action = tester.widget<FieldActionV2>(
      find.widgetWithText(FieldActionV2, AppStrings.profileNicknameConfirm),
    );
    return action.onPressed != null;
  }

  /// 닉네임 칸 안의 '중복확인'을 누른다.
  ///
  /// ⚠️ 글자가 아니라 **버튼 자체**를 겨냥한다. 누르는 영역이 알약보다 넓어
  /// 글자 위를 `InkWell` 이 덮고 있다 — 글자를 겨냥하면 "안 닿는다"고 경고한다.
  Future<void> confirmNickname(WidgetTester tester) async {
    await tester.tap(
      find.widgetWithText(FieldActionV2, AppStrings.profileNicknameConfirm),
    );
    await tester.pumpAndSettle();
  }

  /// 입력이 멎은 뒤 자동 확인이 돌 만큼 시간을 보낸다.
  Future<void> settleAutoCheck(WidgetTester tester) async {
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
  }

  /// 만 14세를 넉넉히 넘긴 생일. `yyyyMMdd` 여덟 자리.
  String adultBirth() {
    final year = DateTime.now().year - 30;
    return '${year}0116';
  }

  /// 페이스를 뺀 전부를 채운다. **페이스는 비워도 넘어간다.**
  Future<void> fillForm(WidgetTester tester) async {
    await type(tester, nicknameField, '러너42');
    await confirmNickname(tester);
    await type(tester, birthField, adultBirth());
    await tester.tap(find.text(AppStrings.profileGenderMale));
    await tester.pumpAndSettle();
    await type(tester, heightField, '175');
    await type(tester, weightField, '65');
  }

  /// 페이스 칸의 '건너뛰기'를 누른다.
  ///
  /// ⚠️ **먼저 끌어올린다.** 폼 맨 아래라 600px 짜리 테스트 화면에서는
  /// y=691 — 화면 밖이다. 바로 누르면 "닿지 않는다"고 경고하고 실패한다.
  Future<void> skipPace(WidgetTester tester) async {
    final button = find.widgetWithText(AppButtonV2, AppStrings.profilePaceSkip);
    await tester.ensureVisible(button);
    await tester.pumpAndSettle();
    await tester.tap(button);
    await tester.pumpAndSettle();
  }

  group('한 화면 폼', () {
    testWidgets('⚠️ 여섯 항목이 처음부터 다 보인다', (tester) async {
      // 단계형에서는 닉네임 하나만 보였다. 그 규칙이 사라진 자리다.
      await pumpPage(tester);

      expect(find.text(AppStrings.profileNicknameLabel), findsOneWidget);
      expect(find.text(AppStrings.profileBirthLabel), findsOneWidget);
      expect(find.text(AppStrings.profileGenderMale), findsOneWidget);
      expect(find.text(AppStrings.profileHeightLabel), findsOneWidget);
      expect(find.text(AppStrings.profileWeightLabel), findsOneWidget);
      expect(find.text(AppStrings.profilePaceLabel), findsOneWidget);
    });

    testWidgets('아무것도 안 채우면 다음이 잠겨 있다', (tester) async {
      await pumpPage(tester);

      expect(nextEnabled(tester), isFalse);
    });

    testWidgets('⚠️ 채우지 않고 나가는 문이 없다', (tester) async {
      // 프로필을 비워두면 매칭도 기록도 설 자리가 없다.
      // 시안에는 뒤로가기와 건너뛰기가 있지만 넣지 않았다.
      //
      // ⚠️ **`onboardingSkip` 과 `profilePaceSkip` 은 글자가 똑같다**(`건너뛰기`).
      // 그래서 "없다"로는 볼 수 없다 — 페이스 버튼이 걸린다. 대신 **개수**로 본다:
      // 이 화면의 건너뛰기는 페이스 칸의 것 하나뿐이다. 폼을 빠져나가는 문이
      // 생기면 둘이 되어 여기서 걸린다 — 그것이 어떤 위젯이든.
      await pumpPage(tester);

      expect(find.text(AppStrings.onboardingSkip), findsOneWidget);
      expect(
        find.widgetWithText(AppButtonV2, AppStrings.profilePaceSkip),
        findsOneWidget,
      );
      expect(find.byType(BackButton), findsNothing);
    });

    testWidgets('⚠️ 페이스를 비워도 다음이 열린다', (tester) async {
      // `null`은 미측정이다. 기본값을 몰래 채우면 고르지 않은 색을 갖게 된다.
      await pumpPage(tester);
      await fillForm(tester);

      expect(nextEnabled(tester), isTrue);
    });

    testWidgets('⚠️ 건너뛰기 버튼이 눈썹 문구와 함께 보인다', (tester) async {
      // 비워도 넘어갈 수 있다는 것을 **보여주는** 유일한 장치다. 안내 한 줄만
      // 두었을 때 "건너뛰기가 없어졌냐"는 말이 나왔다 — 읽히지 않았다.
      await pumpPage(tester);

      expect(find.text(AppStrings.profilePaceSkipEyebrow), findsOneWidget);
      expect(
        find.widgetWithText(AppButtonV2, AppStrings.profilePaceSkip),
        findsOneWidget,
      );
    });

    testWidgets('건너뛰기를 누르면 칸이 측정 전으로 바뀐다', (tester) async {
      // 누르고도 아무 변화가 없으면 눌리지 않는 버튼으로 읽힌다.
      // 담는 값은 그대로 `null`이고, **골랐다는 사실만** 칸에 비친다.
      await pumpPage(tester);
      expect(find.text(AppStrings.profilePaceHint), findsOneWidget);

      await skipPace(tester);

      expect(find.text(AppStrings.profilePaceUnmeasured), findsOneWidget);
      expect(find.text(AppStrings.profilePaceHint), findsNothing);
    });

    testWidgets('건너뛴 뒤에는 건너뛰기가 사라진다', (tester) async {
      // 이미 그 상태가 됐으니 눌러도 바뀔 것이 없다. 남겨 두면 죽은 버튼이다.
      // 다시 고르려면 칸을 누른다.
      await pumpPage(tester);

      await skipPace(tester);

      expect(
        find.widgetWithText(AppButtonV2, AppStrings.profilePaceSkip),
        findsNothing,
      );
      expect(find.text(AppStrings.profilePaceSkipEyebrow), findsNothing);
    });

    testWidgets('건너뛴 뒤에도 다음이 열린다', (tester) async {
      await pumpPage(tester);
      await fillForm(tester);

      await skipPace(tester);

      expect(nextEnabled(tester), isTrue);
    });

    testWidgets('하나라도 비면 다음이 잠긴다', (tester) async {
      await pumpPage(tester);
      await fillForm(tester);
      expect(nextEnabled(tester), isTrue);

      await type(tester, weightField, '');
      expect(nextEnabled(tester), isFalse);
    });

    testWidgets('성별을 안 고르면 다음이 잠긴다', (tester) async {
      await pumpPage(tester);
      await type(tester, nicknameField, '러너42');
      await confirmNickname(tester);
      await type(tester, birthField, adultBirth());
      await type(tester, heightField, '175');
      await type(tester, weightField, '65');

      expect(nextEnabled(tester), isFalse);

      await tester.tap(find.text(AppStrings.profileGenderFemale));
      await tester.pumpAndSettle();
      expect(nextEnabled(tester), isTrue);
    });
  });

  group('⚠️ 휠이 막아주던 값', () {
    testWidgets('없는 날짜를 치면 알려주고 잠근다', (tester) async {
      await pumpPage(tester);
      await fillForm(tester);

      await type(tester, birthField, '19990231');

      expect(find.text(AppStrings.profileBirthMalformed), findsOneWidget);
      expect(nextEnabled(tester), isFalse);
    });

    testWidgets('아직 오지 않은 날을 치면 그렇게 말한다', (tester) async {
      // ⚠️ 나이 판정에도 걸리지만 그때 나오는 말은 "너무 어려요"다.
      // 미래 날짜에 그 문구를 보이면 무엇이 잘못됐는지 모른다.
      await pumpPage(tester);
      await fillForm(tester);

      final year = DateTime.now().year + 1;
      await type(tester, birthField, '${year}0116');

      expect(find.text(AppStrings.profileBirthFuture), findsOneWidget);
      expect(find.text(AppStrings.profileBirthTooYoung), findsNothing);
      expect(nextEnabled(tester), isFalse);
    });

    testWidgets('만 14세 미만이면 잠근다', (tester) async {
      await pumpPage(tester);
      await fillForm(tester);

      final year = DateTime.now().year - 10;
      await type(tester, birthField, '${year}0116');

      expect(find.text(AppStrings.profileBirthTooYoung), findsOneWidget);
      expect(nextEnabled(tester), isFalse);
    });

    testWidgets('범위 밖의 키를 치면 잠근다', (tester) async {
      await pumpPage(tester);
      await fillForm(tester);

      // 휠에서는 고를 수 없던 값이다.
      await type(tester, heightField, '700');

      expect(
        find.text(
          AppStrings.profileHeightOutOfRange(
            BodyRule.minHeight,
            BodyRule.maxHeight,
          ),
        ),
        findsOneWidget,
      );
      expect(nextEnabled(tester), isFalse);
    });

    testWidgets('범위 밖의 몸무게를 치면 잠근다', (tester) async {
      await pumpPage(tester);
      await fillForm(tester);

      await type(tester, weightField, '5');

      expect(
        find.text(
          AppStrings.profileWeightOutOfRange(
            BodyRule.minWeight,
            BodyRule.maxWeight,
          ),
        ),
        findsOneWidget,
      );
      expect(nextEnabled(tester), isFalse);
    });

    testWidgets('⚠️ 빈 칸을 틀렸다고 하지 않는다', (tester) async {
      // 아직 안 친 것뿐이다. 화면을 열자마자 빨간 글씨가 셋이면 겁을 준다.
      await pumpPage(tester);

      expect(find.text(AppStrings.profileBirthMalformed), findsNothing);
      expect(find.textContaining('cm 사이로'), findsNothing);
      expect(find.textContaining('kg 사이로'), findsNothing);
    });
  });

  group('닉네임', () {
    testWidgets('2자 미만이면 중복확인이 눌리지 않는다', (tester) async {
      await pumpPage(tester);
      await type(tester, nicknameField, '가');

      expect(confirmEnabled(tester), isFalse);
      expect(find.text(AppStrings.profileNicknameTooShort), findsOneWidget);
    });

    testWidgets('상한을 넘겨 붙여넣으면 잘리고 경고가 뜬다', (tester) async {
      // 상한을 상수로 잡는다. 숫자를 박아두면 규칙이 바뀔 때 테스트가
      // **잘못된 상한을 지키라고** 우기게 된다.
      await pumpPage(tester);
      await type(tester, nicknameField, '가' * (NicknameRule.max + 3));

      final field = tester.widget<TextField>(
        find.byType(TextField).at(nicknameField),
      );
      expect(field.controller!.text.characters.length, NicknameRule.max);
      expect(find.text(AppStrings.profileNicknameTooLong), findsOneWidget);
    });

    testWidgets('입력이 멎으면 누르지 않아도 알아서 확인한다', (tester) async {
      final repo = FakeOnboardingRepository(latency: Duration.zero);
      await pumpPage(tester, onboarding: repo);

      await type(tester, nicknameField, '러너42');
      expect(repo.availabilityCalls, 0);

      await settleAutoCheck(tester);
      expect(repo.availabilityCalls, 1);
      expect(find.text(AppStrings.profileNicknameOk), findsOneWidget);
    });

    testWidgets('⚠️ 타이핑하는 동안에는 요청이 한 번만 나간다', (tester) async {
      final repo = FakeOnboardingRepository(latency: Duration.zero);
      await pumpPage(tester, onboarding: repo);

      await type(tester, nicknameField, '러');
      await type(tester, nicknameField, '러너');
      await type(tester, nicknameField, '러너4');
      await type(tester, nicknameField, '러너42');
      await settleAutoCheck(tester);

      expect(repo.availabilityCalls, 1);
    });

    testWidgets('⚠️ 형식만 통과한 것을 쓸 수 있다고 말하지 않는다', (tester) async {
      // 곧 "이미 있다"로 뒤집힐 수 있는 말이다.
      await pumpPage(tester);
      await type(tester, nicknameField, '러너42');

      expect(find.text(AppStrings.profileNicknameCheckPending), findsOneWidget);
      expect(find.text(AppStrings.profileNicknameOk), findsNothing);
    });

    testWidgets('겹치는 이름은 알려주고 중복확인을 잠근다', (tester) async {
      final repo = FakeOnboardingRepository(latency: Duration.zero)
        ..taken.add('러너42');
      await pumpPage(tester, onboarding: repo);

      await type(tester, nicknameField, '러너42');
      await settleAutoCheck(tester);

      expect(find.text(AppStrings.profileNicknameTaken), findsOneWidget);
      expect(confirmEnabled(tester), isFalse);
      expect(nextEnabled(tester), isFalse);
    });

    testWidgets('⚠️ 물어보지 못한 것을 이미 있다고 말하지 않는다', (tester) async {
      // 묶으면 네트워크가 잠깐 끊긴 것 때문에 쓸 수 있는 이름을 버리게 된다.
      final repo = FakeOnboardingRepository(
        latency: Duration.zero,
        availabilityFailure: OnboardingFailure.network,
      );
      await pumpPage(tester, onboarding: repo);

      await type(tester, nicknameField, '러너42');
      await settleAutoCheck(tester);

      expect(find.text(AppStrings.profileNicknameCheckFailed), findsOneWidget);
      expect(find.text(AppStrings.profileNicknameTaken), findsNothing);
    });

    testWidgets('⚠️ 확인에 실패한 뒤 다시 누르면 다시 물어본다', (tester) async {
      // 실패한 확인도 답을 남기는데 그것을 답으로 치면 **눌리는데 아무 일도
      // 일어나지 않는 버튼**이 된다.
      final repo = FakeOnboardingRepository(
        latency: Duration.zero,
        availabilityFailure: OnboardingFailure.network,
      );
      await pumpPage(tester, onboarding: repo);

      await type(tester, nicknameField, '러너42');
      await settleAutoCheck(tester);

      expect(find.text(AppStrings.profileNicknameCheckFailed), findsOneWidget);
      expect(repo.availabilityCalls, 1);

      // 눌리는 버튼은 반드시 무언가를 해야 한다.
      expect(confirmEnabled(tester), isTrue, reason: '재시도할 방법이 없다');
      await confirmNickname(tester);
      expect(repo.availabilityCalls, 2);
    });

    testWidgets('이름을 고치면 지난 답이 사라진다', (tester) async {
      final repo = FakeOnboardingRepository(latency: Duration.zero)
        ..taken.add('러너42');
      await pumpPage(tester, onboarding: repo);

      await type(tester, nicknameField, '러너42');
      await settleAutoCheck(tester);
      expect(find.text(AppStrings.profileNicknameTaken), findsOneWidget);

      await type(tester, nicknameField, '러너43');
      expect(find.text(AppStrings.profileNicknameTaken), findsNothing);
    });

    testWidgets('⚠️ 서버가 답하기 전에는 다음이 열리지 않는다', (tester) async {
      // 형식만 맞는 이름으로 넘어가면 서버가 409로 거절한다.
      //
      // ⚠️ 닉네임을 **마지막에** 친다. 다른 칸을 치는 동안 `pumpAndSettle` 이
      // 시간을 흘려보내 자동 확인이 이미 끝나 버린다.
      await pumpPage(tester);
      await type(tester, birthField, adultBirth());
      await tester.tap(find.text(AppStrings.profileGenderMale));
      await tester.pumpAndSettle();
      await type(tester, heightField, '175');
      await type(tester, weightField, '65');

      await tester.enterText(find.byType(TextField).at(nicknameField), '러너42');
      await tester.pump();
      expect(nextEnabled(tester), isFalse, reason: '아직 물어보지 않았다');

      await settleAutoCheck(tester);
      expect(nextEnabled(tester), isTrue);
    });
  });

  group('보내기', () {
    testWidgets('다 채우고 누르면 보낸다', (tester) async {
      final repo = FakeOnboardingRepository(latency: Duration.zero);
      await pumpPage(tester, onboarding: repo);
      await fillForm(tester);

      await tester.tap(find.text(AppStrings.profileNext));
      await tester.pumpAndSettle();

      expect(repo.submitted, isNotNull);
      expect(repo.submitted!.nickname, '러너42');
      expect(repo.submitted!.heightCm, 175);
      expect(repo.submitted!.weightKg, 65);
      // 페이스를 안 골랐으니 미측정이다.
      expect(repo.submitted!.paceSecondsPerKm, isNull);
    });

    testWidgets('⚠️ 실패해도 채운 것을 지우지 않는다', (tester) async {
      final repo = FakeOnboardingRepository(
        latency: Duration.zero,
        failWith: OnboardingFailure.network,
      );
      await pumpPage(tester, onboarding: repo);
      await fillForm(tester);

      await tester.tap(find.text(AppStrings.profileNext));
      await tester.pumpAndSettle();

      expect(find.text(AppStrings.profileSubmitFailed), findsOneWidget);
      expect(
        tester
            .widget<TextField>(find.byType(TextField).at(nicknameField))
            .controller!
            .text,
        '러너42',
      );
      expect(nextEnabled(tester), isTrue);
    });

    testWidgets('⚠️ 닉네임이 겹치면 그 칸에서 말한다', (tester) async {
      // 단계형에서는 그 질문으로 되돌아갔다. 한 화면 폼에서는 되돌아갈 곳이
      // 없으니 **그 칸의 helper**가 말한다 — 아래 실패 줄에 묻히면 안 된다.
      final repo = FakeOnboardingRepository(
        latency: Duration.zero,
        failWith: OnboardingFailure.nicknameTaken,
      );
      await pumpPage(tester, onboarding: repo);
      await fillForm(tester);

      await tester.tap(find.text(AppStrings.profileNext));
      await tester.pumpAndSettle();

      expect(find.text(AppStrings.profileNicknameTaken), findsOneWidget);
      expect(find.text(AppStrings.profileSubmitFailed), findsNothing);
    });
  });
}
