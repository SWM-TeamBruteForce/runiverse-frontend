import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runiverse/core/theme/app_theme.dart';
import 'package:runiverse/core/widgets/v2/app_button.dart';

/// 버튼 크기 — **높이·가로 여백·글자가 함께 간다.**
///
/// ## ⚠️ v1 에 있던 것을 되살린 자리다
///
/// 옛 `AppButton`에는 `AppButtonSize {md(44), lg(56)}`가 있었는데 v2 로 오면서
/// 56 하나로 못 박혔다. 그래서 아바타 옆에 서는 작은 액션도 화면 하단 CTA 와
/// 같은 덩치가 됐다 — 프로필 탭의 `프로필 편집`이 **121×54** 로 측정됐고
/// 시안(`158:3933`)은 **99×41** 이다.
///
/// 셋 중 하나만 줄이면 안 된다. 높이만 줄이면 납작해지고, 글자를 그대로 두면
/// 가로가 안 줄어든다.
void main() {
  Future<Size> pump(WidgetTester tester, AppButtonV2Size size) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(),
        home: Scaffold(
          // ⚠️ **`Center` 에 두면 안 된다.** `expand: false` 인데도 가로가 화면
          // 폭으로 나온다 — 안쪽 `Container` 가 `alignment` 를 갖고 있어
          // 제약이 유한하면 꽉 채운다. 실제 쓰임(아바타 옆 `Row`)처럼 두면
          // 주 축 제약이 무한이라 내용 크기로 줄어든다.
          body: Row(
            children: [
              AppButtonV2(
                label: '프로필 편집',
                size: size,
                expand: false,
                onPressed: () {},
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    // ⚠️ **`AppButtonV2` 자체를 재면 안 된다.** 바깥이 `Semantics`·`Material`
    // 이라 부모 제약을 그대로 받아 화면 폭이 나온다. 실제로 눌리는 상자는
    // 안쪽 `InkWell` 이다.
    return tester.getSize(find.byType(InkWell));
  }

  testWidgets('기본은 56이다 — 바꾸지 않은 화면이 흔들리면 안 된다', (tester) async {
    expect((await pump(tester, AppButtonV2Size.regular)).height, 56);
  });

  testWidgets('⚠️ compact 는 44다', (tester) async {
    // 44 는 손가락이 닿는 바닥이다. 시안의 41 은 그 아래라 쓸 수 없다.
    expect((await pump(tester, AppButtonV2Size.compact)).height, 44);
  });

  testWidgets('⚠️ compact 는 가로도 줄어든다', (tester) async {
    // 높이만 줄이고 가로 여백·글자를 그대로 두면 납작하고 긴 버튼이 된다.
    final regular = await pump(tester, AppButtonV2Size.regular);
    final compact = await pump(tester, AppButtonV2Size.compact);

    expect(compact.width, lessThan(regular.width), reason: '높이만 줄면 덩치는 그대로다');
  });
}
