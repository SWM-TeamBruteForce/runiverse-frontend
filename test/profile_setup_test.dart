import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runiverse/core/storage/token_store.dart';
import 'package:runiverse/core/strings/app_strings.dart';
import 'package:runiverse/features/auth/presentation/auth_provider.dart';
import 'package:runiverse/features/onboarding/data/fake_onboarding_repository.dart';
import 'package:runiverse/features/onboarding/domain/onboarding_failure.dart';
import 'package:runiverse/features/onboarding/presentation/onboarding_provider.dart';
import 'package:runiverse/core/theme/app_theme.dart';
import 'package:runiverse/core/widgets/app_button.dart';
import 'package:runiverse/features/onboarding/presentation/profile_setup_page.dart';

/// 프로필 등록(S04)의 상태 전이 — 질문이 하나씩 열리는가.
///
/// 이 화면의 핵심 규칙은 두 가지다.
/// **답하기 전에는 다음 질문이 보이지 않는다**, 그리고 **답한 것은 눌러서 되돌아갈 수 있다.**
/// 되돌아가기가 없으면 자동 진행은 밀려가는 느낌만 준다.
///
/// 휠 시트는 여기서 다루지 않는다. 시트 안 동작은 별개 위젯의 몫이고,
/// 여기서 볼 것은 화면이 단계를 어떻게 넘기느냐다.
void main() {
  Future<void> pumpPage(
    WidgetTester tester, {
    FakeOnboardingRepository? onboarding,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          // 앱은 SecureTokenStore를 쓰는데 그것은 플랫폼 채널을 부른다.
          // 테스트에는 채널이 없다.
          tokenStoreProvider.overrideWithValue(InMemoryTokenStore()),
          onboardingRepositoryProvider.overrideWithValue(
            onboarding ?? FakeOnboardingRepository(latency: Duration.zero),
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.dark(),
          home: const ProfileSetupPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// 하단 CTA. 화면에 [AppButton]이 여럿 있을 수 있어 라벨로 집는다.
  bool nextEnabled(WidgetTester tester) {
    final button = tester.widget<AppButton>(
      find.widgetWithText(AppButton, AppStrings.profileNext),
    );
    return button.onPressed != null;
  }

  Future<void> typeNickname(WidgetTester tester, String value) async {
    await tester.enterText(find.byType(TextField), value);
    await tester.pumpAndSettle();
  }

  Future<void> confirmNickname(WidgetTester tester) async {
    await tester.tap(find.text(AppStrings.profileNicknameConfirm));
    await tester.pumpAndSettle();
  }

  /// 다섯 질문을 끝까지 채운다.
  ///
  /// 휠은 굴리지 않고 **확인만 누른다** — 초기값이 그대로 답이 된다. 무슨 값이
  /// 들어갔는지는 여기서 볼 것이 아니고, 필요한 건 "다 채운 상태"뿐이다.
  /// 휠 시트를 열고 초기값 그대로 닫는다.
  Future<void> pickThroughSheet(WidgetTester tester) async {
    await tester.tap(find.text(AppStrings.profileTapToPick));
    await tester.pumpAndSettle();
    await tester.tap(find.text('확인'));
    await tester.pumpAndSettle();
  }

  Future<void> fillEverything(WidgetTester tester) async {
    await typeNickname(tester, '러너42');
    await confirmNickname(tester);

    // ⚠️ 단계를 **하나씩 적는다.** "칩이 보이면 누른다" 같은 조건으로 돌리면
    // 답한 줄에 남은 `남성`을 눌러 성별 질문으로 되돌아간다 —
    // `_AnsweredRow`가 고른 값을 그대로 글자로 그리기 때문이다.
    await pickThroughSheet(tester); // 생년월일
    await tester.tap(find.text(AppStrings.profileGenderMale)); // 칩은 즉시 넘어간다
    await tester.pumpAndSettle();
    await pickThroughSheet(tester); // 키·몸무게

    // 페이스는 건너뛴다. 재본 적 없는 사람의 길이고, 값이 `null`이어도 제출된다.
    await tester.tap(find.text(AppStrings.profilePaceSkip));
    await tester.pumpAndSettle();
  }

  testWidgets('처음에는 닉네임 질문 하나만 보인다', (tester) async {
    await pumpPage(tester);

    expect(find.text(AppStrings.profileNicknameQuestion), findsOneWidget);
    // 아직 묻지 않은 질문은 그려지지 않는다.
    expect(find.text(AppStrings.profileBirthQuestion), findsNothing);
    expect(find.text(AppStrings.profileGenderQuestion), findsNothing);
    expect(nextEnabled(tester), isFalse);
  });

  testWidgets('닉네임이 2자 미만이면 확인이 눌리지 않는다', (tester) async {
    await pumpPage(tester);
    await typeNickname(tester, '가');

    final confirm = tester.widget<AppButton>(
      find.widgetWithText(AppButton, AppStrings.profileNicknameConfirm),
    );
    expect(confirm.onPressed, isNull);
    expect(find.text(AppStrings.profileNicknameTooShort), findsOneWidget);
  });

  testWidgets('12자를 넘겨 붙여넣으면 잘리고 경고가 뜬다', (tester) async {
    await pumpPage(tester);
    await typeNickname(tester, '가나다라마바사아자차카타파하');

    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.controller!.text.characters.length, 12);
    expect(find.text(AppStrings.profileNicknameTooLong), findsOneWidget);
  });

  testWidgets('닉네임을 확인하면 다음 질문이 나타난다', (tester) async {
    await pumpPage(tester);
    await typeNickname(tester, '러너42');
    await confirmNickname(tester);

    expect(find.text(AppStrings.profileBirthQuestion), findsOneWidget);
    // 답한 것은 라벨과 함께 위에 남는다.
    expect(find.text(AppStrings.profileNicknameLabel), findsOneWidget);
    expect(find.text('러너42'), findsOneWidget);
  });

  testWidgets('답한 줄을 누르면 그 질문으로 돌아간다', (tester) async {
    await pumpPage(tester);
    await typeNickname(tester, '러너42');
    await confirmNickname(tester);
    expect(find.text(AppStrings.profileBirthQuestion), findsOneWidget);

    await tester.tap(find.text(AppStrings.profileNicknameLabel));
    await tester.pumpAndSettle();

    expect(find.text(AppStrings.profileNicknameQuestion), findsOneWidget);
    expect(find.text(AppStrings.profileBirthQuestion), findsNothing);
  });

  testWidgets('칩을 고르면 곧바로 다음 질문으로 넘어간다', (tester) async {
    await pumpPage(tester);
    await typeNickname(tester, '러너42');
    await confirmNickname(tester);

    // 생년월일은 시트라 여기서 건너뛸 수 없다. 성별 단계까지 못 가므로
    // 칩 자동 진행은 성별 화면이 열린 뒤에 확인한다.
    expect(find.text(AppStrings.profileGenderQuestion), findsNothing);
  });

  testWidgets('마지막 답이 채워지기 전에는 다음이 잠겨 있다', (tester) async {
    await pumpPage(tester);
    await typeNickname(tester, '러너42');
    await confirmNickname(tester);

    expect(nextEnabled(tester), isFalse);
  });

  testWidgets('⚠️ 채우지 않고 나가는 문이 없다', (tester) async {
    await pumpPage(tester);

    // **인증 직후에는 채우고 지나간다.** 나가는 문을 눈에 보이게 두면 대부분
    // 그것을 누르고, 매칭도 기록도 쓸 수 없는 사람이 늘어난다.
    //
    // 갇히지는 않는다 — 앱을 끄고 다시 열면 자동 로그인이 홈으로 보내고
    // 거기서 `ProfilePromptCard`가 이어받는다. 그 경로는 이 화면 밖의 일이다.
    expect(find.byType(TextButton), findsNothing);
    expect(nextEnabled(tester), isFalse);
  });

  // ── 닉네임 중복 확인 ─────────────────────────────────────────

  testWidgets('확인을 누르면 서버에 겹치는지 묻는다', (tester) async {
    final onboarding = FakeOnboardingRepository(latency: Duration.zero);
    await pumpPage(tester, onboarding: onboarding);
    await typeNickname(tester, '러너42');
    await confirmNickname(tester);

    expect(onboarding.availabilityCalls, 1);
    expect(find.text(AppStrings.profileBirthQuestion), findsOneWidget);
  });

  testWidgets('⚠️ 이미 있는 이름이면 다음 질문이 열리지 않는다', (tester) async {
    // 제출 때까지 미루면 네 질문을 지나 다시 여기로 돌아와야 한다.
    final onboarding = FakeOnboardingRepository(latency: Duration.zero)
      ..taken.add('러너42');
    await pumpPage(tester, onboarding: onboarding);
    await typeNickname(tester, '러너42');
    await confirmNickname(tester);

    expect(find.text(AppStrings.profileNicknameTaken), findsOneWidget);
    expect(find.text(AppStrings.profileBirthQuestion), findsNothing);
  });

  testWidgets('⚠️ 물어보지 못한 것을 이미 있다고 말하지 않는다', (tester) async {
    // 둘을 묶으면 네트워크가 잠깐 끊긴 것 때문에 쓸 수 있는 이름을 버리게 된다.
    await pumpPage(
      tester,
      onboarding: FakeOnboardingRepository(
        latency: Duration.zero,
        availabilityFailure: OnboardingFailure.network,
      ),
    );
    await typeNickname(tester, '러너42');
    await confirmNickname(tester);

    expect(find.text(AppStrings.profileNicknameCheckFailed), findsOneWidget);
    expect(find.text(AppStrings.profileNicknameTaken), findsNothing);
    // 판정하지 못했으니 넘기지도 않는다.
    expect(find.text(AppStrings.profileBirthQuestion), findsNothing);
  });

  testWidgets('묻는 동안 확인이 잠긴다', (tester) async {
    await pumpPage(
      tester,
      onboarding: FakeOnboardingRepository(
        latency: const Duration(milliseconds: 200),
      ),
    );
    await typeNickname(tester, '러너42');
    await tester.tap(find.text(AppStrings.profileNicknameConfirm));
    await tester.pump();

    // 두 번 누르면 요청이 두 번 나가고 늦게 온 답이 이긴다.
    final confirm = tester.widget<AppButton>(
      find.widgetWithText(AppButton, AppStrings.profileNicknameConfirm),
    );
    expect(confirm.onPressed, isNull);
    expect(find.text(AppStrings.profileNicknameChecking), findsOneWidget);

    await tester.pumpAndSettle();
  });

  // ── 제출 실패 ───────────────────────────────────────────────

  /// 다 채우고 제출해 [failure]로 실패시킨다.
  Future<void> submitFailing(
    WidgetTester tester,
    OnboardingFailure failure,
  ) async {
    await pumpPage(
      tester,
      onboarding: FakeOnboardingRepository(
        latency: Duration.zero,
        failWith: failure,
      ),
    );
    await fillEverything(tester);
    expect(nextEnabled(tester), isTrue, reason: '다 채웠는데 다음이 잠겨 있다');

    await tester.tap(find.text(AppStrings.profileNext));
    await tester.pumpAndSettle();
  }

  testWidgets('⚠️ 닉네임이 겹치면 닉네임 질문으로 되돌아간다', (tester) async {
    // 서버는 **이미 온보딩됨**과 **닉네임 중복**을 같은 409로 던진다.
    // 이 이유만 고칠 자리가 정해져 있으므로 거기로 데려간다 —
    // 마지막 화면에 세워두면 무엇을 고쳐야 하는지 스스로 찾아야 한다.
    await submitFailing(tester, OnboardingFailure.nicknameTaken);

    expect(find.text(AppStrings.profileNicknameQuestion), findsOneWidget);
    expect(find.text(AppStrings.profileNicknameTaken), findsOneWidget);
    // 아래에 같은 말이 또 뜨면 안 된다.
    expect(find.text(AppStrings.profileSubmitFailed), findsNothing);
  });

  testWidgets('이름을 고치면 겹친다는 말이 사라진다', (tester) async {
    await submitFailing(tester, OnboardingFailure.nicknameTaken);

    // 고치는 순간 서버의 거절은 낡은 말이 된다.
    await typeNickname(tester, '러너99');

    expect(find.text(AppStrings.profileNicknameTaken), findsNothing);
    expect(find.text(AppStrings.profileNicknameOk), findsOneWidget);
  });

  testWidgets('다른 실패는 채운 것을 그대로 두고 마지막에 알린다', (tester) async {
    await submitFailing(tester, OnboardingFailure.network);

    // 다섯 개를 다시 채우게 하지 않는다.
    expect(find.text(AppStrings.profileSubmitFailed), findsOneWidget);
    expect(find.text(AppStrings.profileNicknameQuestion), findsNothing);
    expect(nextEnabled(tester), isTrue);
  });
}
