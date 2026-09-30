import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runiverse/core/theme/app_theme.dart';
import 'package:runiverse/core/theme/v2/app_colors.dart';
import 'package:runiverse/core/theme/v2/app_sizes.dart';
import 'package:runiverse/core/widgets/v2/field_action.dart';

/// `FieldActionV2`가 지키는 약속.
///
/// 입력 칸 **안**에 앉는 작은 버튼이다(`인증하기` `재전송` `중복확인`).
/// 작아야 칸이 안 밀리고, 그러면서도 손가락은 닿아야 한다 — 이 둘이 부딪히는
/// 자리라 여기만 본다.
void main() {
  Future<void> pump(WidgetTester tester, Widget child) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(),
        home: Scaffold(body: Center(child: child)),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('⚠️ 누르는 영역이 44를 지킨다', (tester) async {
    await pump(tester, FieldActionV2(label: '인증하기', onPressed: () {}));

    final tap = tester.getSize(find.byType(InkWell));
    expect(tap.height, greaterThanOrEqualTo(AppSizes.touchDefault));
    expect(tap.width, greaterThanOrEqualTo(AppSizes.touchDefault));
  });

  testWidgets('⚠️ 그런데 칸의 높이는 밀지 않는다', (tester) async {
    // 44px 짜리를 그대로 넣었다가 비밀번호 칸이 53에서 79로 커진 적이 있다
    // (PR #100). 자리는 작게 차지하고 누르는 영역만 넘쳐야 한다.
    await pump(tester, FieldActionV2(label: '인증하기', onPressed: () {}));

    expect(
      tester.getSize(find.byType(FieldActionV2)).height,
      lessThan(AppSizes.touchDefault),
    );
  });

  testWidgets('눌리면 알려준다', (tester) async {
    var tapped = 0;
    await pump(tester, FieldActionV2(label: '중복확인', onPressed: () => tapped++));

    await tester.tap(find.byType(FieldActionV2));
    await tester.pumpAndSettle();

    expect(tapped, 1);
  });

  testWidgets('⚠️ onPressed 가 null 이면 눌리지 않는다', (tester) async {
    // 재전송은 쿨다운 동안 잠긴다. 잠긴 채로 눌리면 서버가 막는다.
    await pump(tester, const FieldActionV2(label: '재전송', onPressed: null));

    expect(tester.widget<InkWell>(find.byType(InkWell)).onTap, isNull);
  });

  testWidgets('⚠️ 잠겨도 글자가 면에 묻히지 않는다', (tester) async {
    // 처음엔 잠긴 글자에 `textDisabled`를 썼는데, 다크에서 그 값이 이 버튼의
    // 면(`borderStrong`)과 **같은 #434343**이라 글자 없는 회색 알약으로 보였다.
    // 에뮬레이터에서야 드러난 종류라 여기서 못 박는다.
    await pump(tester, const FieldActionV2(label: '재전송', onPressed: null));

    final colors = Theme.of(
      tester.element(find.byType(FieldActionV2)),
    ).extension<AppColorsV2>()!;
    final face =
        tester
                .widget<Container>(
                  find
                      .ancestor(
                        of: find.text('재전송'),
                        matching: find.byType(Container),
                      )
                      .first,
                )
                .decoration!
            as BoxDecoration;

    expect(
      tester.widget<Text>(find.text('재전송')).style?.color,
      isNot(face.color),
    );
    expect(face.color, colors.borderStrong);
  });

  testWidgets('글자가 그대로 보인다', (tester) async {
    await pump(tester, FieldActionV2(label: '인증하기', onPressed: () {}));

    expect(find.text('인증하기'), findsOneWidget);
  });
}
