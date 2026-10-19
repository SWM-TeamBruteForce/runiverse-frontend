import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runiverse/core/theme/app_theme.dart';
import 'package:runiverse/core/theme/tokens/app_spacing.dart';
import 'package:runiverse/core/theme/v2/run_palette.dart';
import 'package:runiverse/core/widgets/v2/party_chip.dart';

/// 파티원 칩 — **아바타 중심 간격이 고른가.**
///
/// 칩 하나는 아바타 아래에 이름을 붙여서 폭이 닉네임 길이를 따라간다.
/// 그대로 늘어놓으면 이름이 길고 짧은 사람이 섞일 때 아바타가 들쭉날쭉해진다.
/// 여기서는 칸을 똑같이 나눴는지, 그러면서 좁은 화면에서 넘치지 않는지를 본다.
void main() {
  /// 칩 안의 동그라미. 간격을 재는 기준은 칩이 아니라 **아바타**다.
  Finder avatarIn(int index) => find.descendant(
    of: find.byType(PartyChip).at(index),
    matching: find.byType(Container),
  );

  Future<void> pump(
    WidgetTester tester,
    List<String> names, {
    double width = 375,
    double maxChipWidth = AppSpacing.space10,
    double size = 30,
    bool showName = true,
  }) async {
    tester.view.physicalSize = Size(width * 2, 1600);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(),
        home: Scaffold(
          body: Center(
            child: PartyChipRow(
              maxChipWidth: maxChipWidth,
              children: [
                for (var i = 0; i < names.length; i++)
                  PartyChip(
                    name: names[i],
                    accent: RunPaletteV2.lane(i),
                    size: size,
                    showName: showName,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('⚠️ 이름 길이가 달라도 아바타 중심 간격이 같다', (tester) async {
    // 한 자 · 세 자 · 열여섯 자. 칩 폭을 이름에 맡기면 여기서 벌어진다.
    await pump(tester, const ['나', '김도윤', '열여섯자까지되는긴닉네임이야']);

    final first = tester.getCenter(avatarIn(0)).dx;
    final second = tester.getCenter(avatarIn(1)).dx;
    final third = tester.getCenter(avatarIn(2)).dx;

    expect(second - first, moreOrLessEquals(third - second, epsilon: 0.01));
  });

  testWidgets('⚠️ 넷이 좁은 화면에서도 넘치지 않는다', (tester) async {
    await pump(tester, const ['나', '김도윤', '이서연', '열여섯자까지되는긴닉네임이야'], width: 320);

    expect(tester.takeException(), isNull);
    expect(tester.getRect(avatarIn(0)).left, greaterThanOrEqualTo(0));
    expect(tester.getRect(avatarIn(3)).right, lessThanOrEqualTo(320));
  });

  testWidgets('둘일 때는 칸이 상한까지만 넓어진다', (tester) async {
    // 상한이 없으면 남은 폭을 둘이 나눠 가져 아바타가 양쪽으로 벌어진다.
    await pump(tester, const ['나', '너']);

    expect(
      tester.getSize(find.byType(PartyChip).first).width,
      AppSpacing.space10,
    );
  });

  testWidgets('⚠️ 긴 이름을 한 줄로 줄여 칩 높이를 맞춘다', (tester) async {
    await pump(tester, const ['나', '열여섯자까지되는긴닉네임이야']);

    // 줄이지 않으면 긴 이름이 두 줄로 내려가 이 둘의 높이가 달라진다.
    expect(
      tester.getSize(find.byType(PartyChip).at(0)),
      tester.getSize(find.byType(PartyChip).at(1)),
    );
  });

  testWidgets('이름이 없으면 칸이 아바타 지름과 같다', (tester) async {
    // 3-2-1 구간. 이름이 없으니 칸을 넓힐 이유가 없다.
    await pump(
      tester,
      const ['나', '김도윤', '이서연', '박지훈'],
      maxChipWidth: AppSpacing.space9,
      size: AppSpacing.space9,
      showName: false,
    );

    expect(
      tester.getSize(find.byType(PartyChip).first).width,
      AppSpacing.space9,
    );
  });

  testWidgets('아무도 없으면 아무것도 그리지 않는다', (tester) async {
    await pump(tester, const []);

    expect(find.byType(PartyChip), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
