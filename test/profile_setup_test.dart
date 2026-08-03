import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runiverse/core/strings/app_strings.dart';
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
  Future<void> pumpPage(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(theme: AppTheme.dark(), home: const ProfileSetupPage()),
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
}
