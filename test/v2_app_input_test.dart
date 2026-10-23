import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runiverse/core/theme/app_theme.dart';
import 'package:runiverse/core/theme/v2/app_colors.dart';
import 'package:runiverse/core/theme/v2/app_radius.dart';
import 'package:runiverse/core/widgets/v2/app_input.dart';

/// `AppInputV2`가 지키는 약속.
///
/// 모양을 픽셀로 재지 않는다 — 디자인이 바뀌면 전부 빨개져 아무것도 못 지킨다.
/// **바뀌면 화면이 고장나는 것**만 본다.
///
/// - 라벨 유무가 칸의 모양을 정한다 (이 부품의 유일한 암묵 규칙이다)
/// - 톤이 테두리와 helper 색을 함께 바꾼다
/// - `obscureText`가 글자를 가린다
/// - `key`가 [EditableText]까지 닿는다 — 화면 테스트가 칸을 이 손잡이로 찾는다
void main() {
  Future<void> pump(WidgetTester tester, Widget input) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(),
        home: Scaffold(
          body: Padding(padding: EdgeInsets.zero, child: input),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// 칸을 그리는 바깥 상자. [TextField]가 아니라 이것이 배경·반경·테두리를 든다.
  BoxDecoration decorationOf(WidgetTester tester) =>
      tester
              .widget<Container>(
                find
                    .ancestor(
                      of: find.byType(TextField),
                      matching: find.byType(Container),
                    )
                    .first,
              )
              .decoration!
          as BoxDecoration;

  AppColorsV2 colorsOf(WidgetTester tester) => Theme.of(
    tester.element(find.byType(TextField)),
  ).extension<AppColorsV2>()!;

  testWidgets('라벨이 있으면 라벨이 칸 안에 보인다', (tester) async {
    await pump(
      tester,
      AppInputV2(controller: TextEditingController(), label: '이메일'),
    );

    // 칸 위가 아니라 안이다. 위젯 트리에서 [TextField]와 조상을 공유한다.
    expect(find.text('이메일'), findsOneWidget);
  });

  testWidgets('⚠️ 라벨이 없으면 반경이 작아진다', (tester) async {
    // 이 부품의 유일한 암묵 규칙이다. 깨지면 로그인 칸이 회원가입 칸 모양이 된다.
    await pump(tester, AppInputV2(controller: TextEditingController()));

    expect(decorationOf(tester).borderRadius, AppRadius.md);
  });

  testWidgets('⚠️ 라벨이 있으면 반경이 커진다', (tester) async {
    await pump(
      tester,
      AppInputV2(controller: TextEditingController(), label: '이메일'),
    );

    expect(decorationOf(tester).borderRadius, AppRadius.lg);
  });

  testWidgets('⚠️ 힌트가 값과 같은 크기로 그려진다', (tester) async {
    // 힌트가 값보다 작으면 **첫 글자를 넣는 순간 줄 높이가 바뀌어** 칸이 흔들린다.
    // 시안도 둘을 같은 글자로 둔다.
    //
    // (힌트가 사라지는 것 자체는 Flutter의 `InputDecorator`가 한다.
    //  우리 약속이 아니라서 보지 않는다 — 글자를 넣어도 힌트 위젯은 트리에
    //  투명하게 남는다.)
    await pump(
      tester,
      AppInputV2(controller: TextEditingController(), hint: '이메일 입력'),
    );

    final field = tester.widget<TextField>(find.byType(TextField));
    final colors = colorsOf(tester);

    expect(field.decoration?.hintStyle?.fontSize, field.style?.fontSize);
    expect(field.decoration?.hintStyle?.color, colors.textTertiary);
    expect(field.style?.color, colors.textPrimary);
  });

  testWidgets('넣은 글자가 controller에 들어간다', (tester) async {
    final controller = TextEditingController();
    await pump(tester, AppInputV2(controller: controller, hint: '이메일 입력'));

    await tester.enterText(find.byType(TextField), 'a@b.com');

    expect(controller.text, 'a@b.com');
  });

  testWidgets('⚠️ 오류 톤이 테두리와 helper 색을 함께 바꾼다', (tester) async {
    // 색 하나만 바뀌면 색맹인 사용자에게 아무 정보가 아니다.
    await pump(
      tester,
      AppInputV2(
        controller: TextEditingController(),
        helper: '비밀번호가 다릅니다',
        tone: AppInputToneV2.error,
      ),
    );

    final colors = colorsOf(tester);
    expect(decorationOf(tester).border?.top.color, colors.error);
    expect(
      tester.widget<Text>(find.text('비밀번호가 다릅니다')).style?.color,
      colors.error,
    );
  });

  testWidgets('톤이 기본이면 테두리가 보이지 않는다', (tester) async {
    await pump(tester, AppInputV2(controller: TextEditingController()));

    // ⚠️ `null`이 아니라 투명이다. 테두리를 없앴다 그렸다 하면 칸이 1px씩
    // 커져 포커스를 옮길 때마다 줄이 흔들린다.
    expect(decorationOf(tester).border?.top.color, Colors.transparent);
  });

  testWidgets('obscureText가 글자를 가린다', (tester) async {
    await pump(
      tester,
      AppInputV2(controller: TextEditingController(), obscureText: true),
    );

    expect(
      tester.widget<TextField>(find.byType(TextField)).obscureText,
      isTrue,
    );
  });

  testWidgets('⚠️ key로 글자를 넣을 수 있다', (tester) async {
    // 화면 테스트가 칸을 이 손잡이로 찾는다(`profile_edit_page_test`).
    // `super.key`를 빠뜨리면 조용히 닿지 않게 된다.
    const key = ValueKey('nickname');
    final controller = TextEditingController();
    await pump(tester, AppInputV2(key: key, controller: controller));

    await tester.enterText(find.byKey(key), '주주');

    expect(controller.text, '주주');
  });

  testWidgets('suffix가 칸 안 오른쪽에 붙는다', (tester) async {
    await pump(
      tester,
      AppInputV2(
        controller: TextEditingController(),
        label: '이메일',
        suffix: const Text('인증하기'),
      ),
    );

    final field = tester.getRect(find.byType(TextField));
    final suffix = tester.getRect(find.text('인증하기'));

    expect(suffix.left, greaterThan(field.right));
  });

  testWidgets('counter가 없으면 helper 줄이 생기지 않는다', (tester) async {
    await pump(tester, AppInputV2(controller: TextEditingController()));

    // 빈 줄이 생기면 칸마다 아래 여백이 달라진다.
    expect(find.byType(Row), findsOneWidget);
  });
}
