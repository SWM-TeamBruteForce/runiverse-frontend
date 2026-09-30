import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runiverse/core/theme/app_theme.dart';
import 'package:runiverse/core/theme/v2/app_colors.dart';
import 'package:runiverse/core/widgets/v2/action_tile.dart';
import 'package:runiverse/core/widgets/v2/app_icon.dart';

/// `ActionTileV2`가 지키는 약속.
///
/// 홈 아래쪽에 나란히 앉는 두 칸이다(`혼자연습하기` · `친구랑 뛰기`).
///
/// ## ⚠️ 크기를 재는 것으로는 부족하다
///
/// `FieldActionV2`가 이걸로 한 번 속였다(스펙 9절) — `InkWell`의 **크기**는
/// 44였는데 실제로는 그 자리가 눌리지 않았다. 여기서는 **정말 눌리는지**를
/// 좌표로 찍어 본다.
void main() {
  Future<void> pump(
    WidgetTester tester, {
    VoidCallback? onTap,
    String label = '혼자연습하기',
    bool emphasized = true,
    double width = 182,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(),
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: width,
              child: ActionTileV2(
                icon: AppIcons.running,
                label: label,
                emphasized: emphasized,
                onTap: onTap ?? () {},
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('아이콘과 라벨이 보인다', (tester) async {
    await pump(tester);

    expect(find.text('혼자연습하기'), findsOneWidget);
    expect(find.byType(AppIcon), findsOneWidget);
  });

  testWidgets('⚠️ 아이콘 밖 · 칸 안을 눌러도 눌린다', (tester) async {
    // 아이콘 타일은 36이고 칸은 182다. 라벨 오른쪽의 빈 자리를 눌렀을 때
    // 반응해야 **칸 전체가 버튼**인 것이다. 아이콘만 눌린다면 너무 좁다.
    var tapped = 0;
    await pump(tester, onTap: () => tapped++);

    final tile = tester.getRect(find.byType(ActionTileV2));
    await tester.tapAt(Offset(tile.right - 4, tile.center.dy));
    await tester.pumpAndSettle();

    expect(tapped, 1, reason: '라벨 오른쪽 빈 자리가 안 눌린다');
  });

  testWidgets('⚠️ 손가락이 닿는 높이가 44를 넘는다', (tester) async {
    await pump(tester);

    expect(
      tester.getSize(find.byType(InkWell)).height,
      greaterThanOrEqualTo(44),
    );
  });

  testWidgets('⚠️ 강조 여부는 아이콘 타일의 면으로만 낸다', (tester) async {
    // 시안이 두 칸을 같은 크기·같은 배경으로 둔다. 칸 자체를 바꾸기 시작하면
    // 나란히 고르는 선택지가 주·보조로 읽힌다.
    await pump(tester, emphasized: true);
    final strong = tester.getSize(find.byType(ActionTileV2));

    await pump(tester, emphasized: false);
    final soft = tester.getSize(find.byType(ActionTileV2));

    expect(soft, strong, reason: '칸 크기가 달라졌다');
  });

  testWidgets('⚠️ 강조를 끄면 아이콘 면이 가라앉는다', (tester) async {
    final colors = AppColorsV2.dark;

    await pump(tester, emphasized: true);
    expect(_badgeColor(tester), colors.primary);

    await pump(tester, emphasized: false);
    expect(_badgeColor(tester), colors.primaryMuted);
  });

  testWidgets('⚠️ 라벨이 길어도 칸이 넘치지 않는다', (tester) async {
    // 두 칸이 화면을 반씩 나눠 갖는다. 문구는 기획이 정하므로 길어질 수 있고,
    // `Expanded` 가 빠지면 그 순간 칸에 오버플로 줄이 간다.
    await pump(tester, label: '아주아주 긴 문구가 들어오는 경우');

    expect(tester.takeException(), isNull);
  });
}

/// 아이콘이 앉은 타일의 면 색.
Color? _badgeColor(WidgetTester tester) {
  final box = tester.widget<Container>(
    find
        .ancestor(of: find.byType(AppIcon), matching: find.byType(Container))
        .first,
  );
  return (box.decoration! as BoxDecoration).color;
}
