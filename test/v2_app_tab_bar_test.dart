// `Tristate`가 여기 있다. `package:flutter/semantics.dart`는 안 내보낸다.
import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runiverse/core/strings/app_strings.dart';
import 'package:runiverse/core/theme/app_theme.dart';
import 'package:runiverse/core/theme/v2/app_colors.dart';
import 'package:runiverse/core/widgets/v2/app_icon.dart';
import 'package:runiverse/core/widgets/v2/app_tab_bar.dart';

/// `AppTabBarV2`가 지키는 약속.
///
/// ## ⚠️ 이 화면에는 읽을 글자가 하나도 없다
///
/// 시안이 아이콘만 두기로 해서(CLAUDE.md Scope) `find.text`로 잡을 것이
/// 없다. 그래서 여기서는 **[Semantics]가 무엇을 말하는지**를 본다 — 그것이
/// 라벨을 대신하는 유일한 것이고, 빠져도 화면은 멀쩡해 보인다.
void main() {
  const tabs = [
    AppTabSpec(icon: AppIcons.home, label: '홈'),
    AppTabSpec(icon: AppIcons.book, label: '기록'),
    AppTabSpec(icon: AppIcons.photo, label: '기록카드'),
    AppTabSpec(icon: AppIcons.profile, label: '프로필'),
  ];

  Future<List<int>> pump(
    WidgetTester tester, {
    int current = 0,
    double? width,
    Set<int> badges = const {},
  }) async {
    if (width != null) {
      tester.view.physicalSize = Size(width * 3, 2400);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
    }

    final taps = <int>[];
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(),
        home: Scaffold(
          extendBody: true,
          bottomNavigationBar: AppTabBarV2(
            tabs: tabs,
            currentIndex: current,
            badges: badges,
            onSelected: taps.add,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return taps;
  }

  /// 그 탭이 내보내는 semantics 를 찾는다.
  Finder tab(String label) => find.bySemanticsLabel(label);

  testWidgets('⚠️ 글자가 없어도 이름은 읽힌다', (tester) async {
    // 라벨을 안 붙이면 스크린리더에게 이 바는 **빈 그림 네 개**다.
    // 그리고 눈으로는 전혀 티가 안 난다 — 그래서 여기서 못 박는다.
    final handle = tester.ensureSemantics();
    await pump(tester);

    for (final spec in tabs) {
      expect(tab(spec.label), findsOneWidget, reason: '${spec.label}을 못 읽는다');
    }
    handle.dispose();
  });

  testWidgets('⚠️ 선택된 탭이 선택됐다고 말한다', (tester) async {
    // 선택 표시가 흰 알약 하나뿐이라, 보이지 않는 사람에게는 이 값이
    // 지금 어느 탭인지 아는 **유일한 길**이다.
    final handle = tester.ensureSemantics();
    await pump(tester, current: 2);

    final chosen = tester.getSemantics(tab('기록카드')).getSemanticsData();
    expect(chosen.label, '기록카드');
    expect(chosen.flagsCollection.isSelected, Tristate.isTrue);

    // ⚠️ **이름과 탭 액션이 같은 마디에 있어야 한다.**
    //
    // 처음엔 `Semantics(excludeSemantics: true)`로 감쌌는데, 그러면 아래
    // `InkWell`의 탭 액션까지 같이 지워진다 — 스크린리더가 `기록카드`라고
    // 읽어 주지만 **두 번 눌러도 아무 일이 없다.** 눈으로는 멀쩡하다.
    expect(
      chosen.hasAction(SemanticsAction.tap),
      isTrue,
      reason: '스크린리더가 이 탭을 누를 수 없다',
    );

    final other = tester.getSemantics(tab('홈')).getSemanticsData();
    expect(
      other.flagsCollection.isSelected,
      isNot(Tristate.isTrue),
      reason: '둘이 선택됐다',
    );
    handle.dispose();
  });

  testWidgets('누르면 그 자리 번호를 준다', (tester) async {
    // 번호가 곧 라우터의 branch 번호다. 어긋나면 엉뚱한 탭이 열린다.
    final handle = tester.ensureSemantics();
    final taps = await pump(tester);

    await tester.tap(tab('기록카드'));
    await tester.tap(tab('프로필'));
    await tester.pumpAndSettle();

    expect(taps, [2, 3]);
    handle.dispose();
  });

  testWidgets('이미 열린 탭을 다시 눌러도 알려준다', (tester) async {
    // 셸이 "같은 탭을 다시 누르면 그 탭의 첫 화면으로"를 하려면 이게 와야 한다.
    final handle = tester.ensureSemantics();
    final taps = await pump(tester);

    await tester.tap(tab('홈'));
    await tester.pumpAndSettle();

    expect(taps, [0]);
    handle.dispose();
  });

  testWidgets('⚠️ 선택된 아이콘이 알약에 묻히지 않는다', (tester) async {
    // `textPrimary`(#FAFAFA)가 알약 면 `bgInverse`와 **같은 값**이다.
    // 기본색을 그대로 쓰면 선택된 탭만 아이콘이 사라진다 — `FieldActionV2`가
    // 정확히 이 사고를 냈다(스펙 9절).
    await pump(tester);

    final colors = AppColorsV2.dark;
    final icons = tester.widgetList<AppIcon>(find.byType(AppIcon)).toList();

    expect(icons.first.color, colors.primary, reason: '선택된 아이콘');
    expect(icons.first.color, isNot(colors.bgInverse));
    for (final icon in icons.skip(1)) {
      expect(icon.color, colors.textTertiary, reason: '나머지');
    }
  });

  testWidgets('⚠️ 손가락이 닿는 넓이가 44를 넘는다', (tester) async {
    // 아이콘은 24 다. 아이콘만 누를 수 있으면 너무 좁다.
    await pump(tester);

    for (final spec in tabs) {
      final size = tester.getSize(
        find.descendant(of: tab(spec.label), matching: find.byType(InkWell)),
      );
      expect(size.height, greaterThanOrEqualTo(44), reason: spec.label);
      expect(size.width, greaterThanOrEqualTo(44), reason: spec.label);
    }
  });

  /// 좁은 화면 — **넷이 다 들어가는가.**
  ///
  /// 칸을 86으로 못 박으면 넷에 344가 필요하다. 바 안쪽 폭은 `화면 폭 − 56`
  /// 이라 **400보다 좁은 기기에서 넘친다** — 흔한 안드로이드 폰도, 일반형
  /// 아이폰(393)도 거기 든다. 넘친 자리는 둥근 모서리에 깎이고, 릴리스
  /// 빌드는 넘침 경고도 안 띄운다. 그래서 테스트 기본 폭(800)으로는 영영
  /// 안 잡힌다.
  group('좁은 화면', () {
    for (final width in [320.0, 360.0, 384.0, 393.0]) {
      testWidgets('⚠️ ${width.toInt()}에서 마지막 탭이 안 깎인다', (tester) async {
        await pump(tester, width: width);

        expect(tester.takeException(), isNull, reason: '넘쳤다');

        final bar = tester.getRect(find.byType(ClipRRect));
        final last = tester.getRect(find.byType(InkWell).last);
        // 바 안쪽 여백(4) 안에 들어와야 둥근 모서리에 안 닿는다.
        expect(last.right, lessThanOrEqualTo(bar.right - 4));
        expect(
          tester.getRect(find.byType(InkWell).first).left,
          greaterThanOrEqualTo(bar.left + 4),
        );
      });
    }

    testWidgets('⚠️ 좁아져도 손가락이 닿는 넓이는 남는다', (tester) async {
      await pump(tester, width: 320);

      for (final spec in tabs) {
        final size = tester.getSize(
          find.descendant(of: tab(spec.label), matching: find.byType(InkWell)),
        );
        expect(size.width, greaterThanOrEqualTo(44), reason: spec.label);
      }
    });

    testWidgets('넓으면 시안대로 86에서 멈춘다', (tester) async {
      // 남는 폭을 나눠 가지면 큰 화면에서 알약이 터무니없이 길어진다.
      await pump(tester, width: 430);

      expect(tester.getSize(find.byType(InkWell).first).width, 86);
    });
  });

  testWidgets('⚠️ 본문 위에 뜬다 — 자리를 빼앗지 않는다', (tester) async {
    // `extendBody: true`가 켜져 있어야 본문이 바 뒤까지 내려온다.
    // 이게 깨지면 바 아래에 빈 띠가 생긴다.
    await pump(tester);

    // ⚠️ `AppTabBarV2` 자체가 아니라 **보이는 면**을 잰다. 위젯의 사각형에는
    // 띄우려고 준 여백이 들어 있어서, 그걸 재면 늘 바닥에 닿아 있다.
    final bar = tester.getRect(find.byType(ClipRRect));
    final screen = tester.getRect(find.byType(Scaffold));

    expect(bar.bottom, lessThan(screen.bottom), reason: '바닥에 붙어 있다');
    expect(bar.left, greaterThan(screen.left), reason: '좌우가 안 비었다');
    expect(bar.height, 60, reason: '시안은 60이다');
  });

  /// 알림 점 — **읽지 않은 알림이 있다는 유일한 전역 신호다.**
  ///
  /// 알림함이 프로필 탭 안에 있어서, 다른 탭에 있을 때 알려 줄 자리가 여기
  /// 하나뿐이다.
  group('알림 점', () {
    testWidgets('badges에 든 탭에만 점이 선다', (tester) async {
      await pump(tester, badges: {3});

      // 점은 글자가 아니라 그림이다. 색으로 센다.
      final dots = find.byKey(const ValueKey('tab-badge-3'));
      expect(dots, findsOneWidget);
      expect(find.byKey(const ValueKey('tab-badge-0')), findsNothing);
    });

    testWidgets('비어 있으면 아무 점도 없다', (tester) async {
      await pump(tester);

      for (var i = 0; i < tabs.length; i++) {
        expect(find.byKey(ValueKey('tab-badge-$i')), findsNothing);
      }
    });

    testWidgets('⚠️ 점이 있으면 읽히는 이름이 바뀐다', (tester) async {
      // **점을 그림으로만 두면 스크린리더가 읽을 것이 없다.** 이 바에는
      // 글자가 하나도 없어서 `Semantics(label:)`이 전부다.
      final handle = tester.ensureSemantics();
      await pump(tester, badges: {3});

      expect(
        find.bySemanticsLabel('프로필, ${AppStrings.notificationUnreadSemantics}'),
        findsOneWidget,
      );
      // 점이 없는 탭의 이름은 그대로다.
      expect(find.bySemanticsLabel('홈'), findsOneWidget);
      handle.dispose();
    });

    testWidgets('점이 없으면 이름은 그대로다', (tester) async {
      final handle = tester.ensureSemantics();
      await pump(tester);

      expect(find.bySemanticsLabel('프로필'), findsOneWidget);
      handle.dispose();
    });
  });
}
