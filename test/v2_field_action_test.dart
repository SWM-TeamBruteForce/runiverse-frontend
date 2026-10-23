import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runiverse/core/theme/app_theme.dart';
import 'package:runiverse/core/theme/v2/app_colors.dart';
import 'package:runiverse/core/theme/v2/app_sizes.dart';
import 'package:runiverse/core/widgets/v2/app_input.dart';
import 'package:runiverse/core/widgets/v2/field_action.dart';

/// `FieldActionV2`가 지키는 약속.
///
/// 입력 칸 **안**에 앉는 작은 버튼이다(`인증하기` `재전송` `중복확인`).
/// 작아 보여야 칸이 안 밀리고, 그러면서도 손가락은 닿아야 한다.
///
/// ## ⚠️ 크기를 재는 것으로는 부족했다
///
/// 처음엔 `InkWell`의 **크기**가 44인지만 봤다. `OverflowBox`로 키운 크기라
/// 테스트는 통과했는데 **실제로는 눌리지 않았다** — Flutter 는 부모의 경계
/// 밖을 히트 테스트하지 않는다.
///
/// 그래서 지금은 **정말 눌리는지**를 본다. 알약 밖 · 칸 안인 좌표를 찍는다.
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

  /// 칸 안에 넣어 띄운다. 이 버튼이 실제로 사는 자리다.
  Future<void> pumpInField(WidgetTester tester, {VoidCallback? onPressed}) {
    return pump(
      tester,
      // ⚠️ `Column(mainAxisSize: min)` 으로 감싼다. 그냥 두면 칸이 화면
      // 높이(600)를 다 채워 높이를 잴 수 없다.
      SizedBox(
        width: 364,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AppInputV2(
              controller: TextEditingController(),
              label: '이메일',
              hint: '이메일 입력',
              suffix: FieldActionV2(label: '인증하기', onPressed: onPressed),
            ),
          ],
        ),
      ),
    );
  }

  testWidgets('⚠️ 칸 안에서 누르는 영역이 44를 넘는다', (tester) async {
    await pumpInField(tester, onPressed: () {});

    final tap = tester.getSize(find.byType(InkWell));
    expect(tap.height, greaterThanOrEqualTo(AppSizes.touchDefault));
  });

  testWidgets('⚠️ 알약 위쪽 여백을 눌러도 눌린다', (tester) async {
    // 크기만 재면 못 잡는 것. 알약은 36이고 칸은 71이라, 그 사이 여백을
    // 눌렀을 때 반응해야 누르는 영역이 진짜 넓은 것이다.
    var tapped = 0;
    await pumpInField(tester, onPressed: () => tapped++);

    final pill = tester.getRect(find.text('인증하기'));
    final area = tester.getRect(find.byType(FieldActionV2));

    await tester.tapAt(Offset(pill.center.dx, area.top + 2));
    await tester.pumpAndSettle();

    expect(tapped, 1, reason: '알약 밖인데 칸 안인 곳이 안 눌린다');
  });

  testWidgets('⚠️ 그런데 칸의 높이는 밀지 않는다', (tester) async {
    // 44px 짜리를 그대로 넣었다가 비밀번호 칸이 53에서 79로 커진 적이 있다
    // (PR #100). 라벨 있는 칸의 높이는 71이어야 한다.
    await pumpInField(tester, onPressed: () {});

    expect(tester.getSize(find.byType(AppInputV2)).height, closeTo(71, 2));
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
