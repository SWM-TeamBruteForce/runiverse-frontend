import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runiverse/core/theme/app_theme.dart';
import 'package:runiverse/core/widgets/v2/app_button.dart';
import 'package:runiverse/core/widgets/wheel_picker_sheet.dart';

/// 휠 바텀시트 — 생년월일 · 키 · 몸무게를 고르는 자리.
///
/// ## ⚠️ 그물이 하나도 없던 파일이다
///
/// 278줄짜리 공용 위젯인데 **여는 테스트가 없었다.** 새 토큰으로 옮길 때
/// 전체 1,097개가 통과했지만 그중 이 파일을 지나는 것은 하나도 없었다 —
/// 통과가 아무것도 증명하지 않는 상태였다.
///
/// 디자인 시스템에 없는 컴포넌트라 모양을 못 박지는 않는다. **고른 값이
/// 그대로 돌아오는가**와 **옮긴 세대의 버튼을 쓰는가**만 본다.
void main() {
  /// 고른 값을 담아 두는 그릇. **시트가 닫힌 뒤에 읽어야 한다** —
  /// 여는 시점에 읽으면 아직 `null` 이라 아무것도 검증하지 못한다.
  final result = <String, List<int>?>{};

  Future<void> open(
    WidgetTester tester, {
    required List<WheelColumn> columns,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                result['picked'] = await showWheelPickerSheet(
                  context,
                  title: '생년월일',
                  columns: columns,
                );
              },
              child: const Text('열기'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('열기'));
    await tester.pumpAndSettle();
  }

  List<WheelColumn> columns() => [
    const WheelColumn(unit: '년', values: [1990, 1991, 1992], initial: 1991),
    const WheelColumn(unit: '월', values: [1, 2, 3], initial: 3),
  ];

  testWidgets('제목과 확인 버튼이 뜬다', (tester) async {
    await open(tester, columns: columns());

    expect(find.text('생년월일'), findsOneWidget);
    expect(find.byType(AppButtonV2), findsOneWidget);
  });

  testWidgets('⚠️ 아무것도 안 돌리고 확인하면 처음 값이 그대로 온다', (tester) async {
    // 휠을 건드리지 않았는데 다른 값이 오면, 사용자가 본 것과 저장되는 것이
    // 어긋난다. 생년월일에서 그 어긋남은 **나중에 발견된다.**
    await open(tester, columns: columns());

    await tester.tap(find.byType(AppButtonV2));
    await tester.pumpAndSettle();

    expect(result['picked'], [1991, 3], reason: '처음 놓인 값 그대로여야 한다');
  });

  testWidgets('⚠️ 취소하면 아무 값도 돌려주지 않는다', (tester) async {
    await open(tester, columns: columns());

    Navigator.of(tester.element(find.byType(AppButtonV2))).pop();
    await tester.pumpAndSettle();

    expect(result['picked'], isNull);
  });
}
