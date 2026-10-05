import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runiverse/core/strings/app_strings.dart';
import 'package:runiverse/core/theme/app_theme.dart';
import 'package:runiverse/features/session/presentation/run_controls.dart';

/// 러닝 중 하단 조작.
///
/// ## ⚠️ 패널티 안내를 잃지 않는 것이 이 그물의 목적이다
///
/// 예전에는 `중지` → 시트 안에 `목표의 80%를 채우지 못하면 20분 동안 매칭을
/// 신청할 수 없어요` 가 있었다. 시안대로 버튼 둘로 바꾸면서 **시트가 통째로
/// 사라졌다** — 안내도 같이 사라질 뻔했다.
///
/// 지금은 **종료를 누르고 있는 동안** 뜬다. 그만둘지 망설이는 바로 그
/// 순간이고, 달리는 내내 띄우면 읽지 않게 된다.
void main() {
  Future<void> pump(
    WidgetTester tester, {
    double? remainingKm,
    bool paused = false,
    VoidCallback? onFinish,
    VoidCallback? onPause,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(),
        home: Scaffold(
          body: RunControls(
            paused: paused,
            enabled: true,
            onPauseToggle: onPause ?? () {},
            onFinish: onFinish ?? () {},
            penaltyRemainingKm: remainingKm,
          ),
        ),
      ),
    );
    await tester.pump();
  }

  Finder finish() => find.bySemanticsLabel(AppStrings.runFinishHold);

  group('⚠️ 패널티 안내', () {
    testWidgets('누르기 전에는 뜨지 않는다', (tester) async {
      await pump(tester, remainingKm: 1.2);

      expect(find.text(AppStrings.runFinishPenaltyNotice), findsNothing);
    });

    testWidgets('⚠️ 종료를 누르고 있는 동안 뜬다', (tester) async {
      await pump(tester, remainingKm: 1.2);

      final gesture = await tester.startGesture(tester.getCenter(finish()));
      // ⚠️ **프레임이 둘 필요하다.** 첫 프레임에 `onTapDown` 이 불려
      // 애니메이션이 시작되고, 값이 0을 넘는 것은 그다음 프레임이다.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text(AppStrings.runFinishPenaltyNotice), findsOneWidget);
      expect(
        find.text(AppStrings.runFinishRemaining(1.2)),
        findsOneWidget,
        reason: '얼마나 더 달리면 되는지도 함께 말한다',
      );

      await gesture.up();
      await tester.pumpAndSettle();
    });

    testWidgets('⚠️ 솔로에게는 띄우지 않는다', (tester) async {
      // 목표가 없으면 제재도 없다. 겁줄 이유가 없다.
      await pump(tester);

      final gesture = await tester.startGesture(tester.getCenter(finish()));
      // ⚠️ **프레임이 둘 필요하다.** 첫 프레임에 `onTapDown` 이 불려
      // 애니메이션이 시작되고, 값이 0을 넘는 것은 그다음 프레임이다.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text(AppStrings.runFinishPenaltyNotice), findsNothing);

      await gesture.up();
      await tester.pumpAndSettle();
    });
  });

  group('⚠️ 종료는 길게 눌러야 한다', () {
    testWidgets('한 번 탭으로는 끝나지 않는다', (tester) async {
      var finished = 0;
      await pump(tester, onFinish: () => finished++);

      await tester.tap(finish());
      await tester.pump(const Duration(milliseconds: 500));

      expect(finished, 0);
    });

    testWidgets('끝까지 누르면 끝난다', (tester) async {
      var finished = 0;
      await pump(tester, onFinish: () => finished++);

      final gesture = await tester.startGesture(tester.getCenter(finish()));
      for (var i = 0; i < 30 && finished == 0; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      await gesture.up();
      await tester.pumpAndSettle();

      expect(finished, 1);
    });

    testWidgets('⚠️ 도중에 손을 떼면 처음으로 돌아간다', (tester) async {
      // 그 자리에서 멈추면 다음에 조금만 눌러도 끝나 버린다.
      var finished = 0;
      await pump(tester, onFinish: () => finished++);

      final gesture = await tester.startGesture(tester.getCenter(finish()));
      await tester.pump(const Duration(milliseconds: 600));
      await gesture.up();
      await tester.pumpAndSettle();

      // 다시 조금만 누른다.
      final again = await tester.startGesture(tester.getCenter(finish()));
      await tester.pump(const Duration(milliseconds: 600));
      await again.up();
      await tester.pumpAndSettle();

      expect(finished, 0, reason: '이어서 차면 두 번의 짧은 터치로 끝난다');
    });
  });

  testWidgets('⚠️ 두 버튼의 그림이 서로 다르다', (tester) async {
    // 처음엔 종료에 `AppIcons.stop` 을 썼는데, 시안 세트의 그 글리프가
    // `assets/icons/stop.svg` 를 열어 보면 **막대 둘**이다 — 오른쪽
    // 일시정지와 똑같이 보였다. **기기에서 나란히 놓고서야 드러났다.**
    await pump(tester);

    // 일시정지는 아이콘, 종료는 직접 그린 네모다. 둘이 같은 종류가 되면
    // (둘 다 `Icon` 이거나 둘 다 네모면) 구분이 사라진 것이다.
    expect(find.byType(Icon), findsOneWidget, reason: '아이콘은 일시정지 하나뿐이다');
  });

  testWidgets('일시정지는 한 번 누르면 된다', (tester) async {
    var toggled = 0;
    await pump(tester, onPause: () => toggled++);

    await tester.tap(find.bySemanticsLabel(AppStrings.runPauseCta));
    await tester.pump();

    expect(toggled, 1);
  });

  testWidgets('멈춘 뒤에는 `계속 달리기` 로 읽힌다', (tester) async {
    await pump(tester, paused: true);

    expect(find.bySemanticsLabel(AppStrings.runResumeCta), findsOneWidget);
    expect(find.bySemanticsLabel(AppStrings.runPauseCta), findsNothing);
  });
}
