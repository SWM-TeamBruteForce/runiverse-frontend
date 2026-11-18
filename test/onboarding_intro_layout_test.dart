import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runiverse/core/theme/app_theme.dart';
import 'package:runiverse/core/widgets/v2/app_button.dart';
import 'package:runiverse/features/onboarding/presentation/onboarding_intro_page.dart';

void main() {
  for (final config in [
    (name: 'tall', size: Size(384, 832), padding: EdgeInsets.zero, scale: 1.0),
    (
      name: 'safe areas',
      size: Size(384, 832),
      padding: EdgeInsets.only(top: 34, bottom: 48),
      scale: 1.0,
    ),
    (
      name: 'small',
      size: Size(320, 568),
      padding: EdgeInsets.only(top: 24, bottom: 24),
      scale: 1.0,
    ),
    (
      name: 'large text',
      size: Size(384, 832),
      padding: EdgeInsets.only(top: 34, bottom: 48),
      scale: 2.0,
    ),
    (
      name: 'landscape',
      size: Size(640, 360),
      padding: EdgeInsets.only(top: 24, bottom: 24),
      scale: 1.0,
    ),
  ]) {
    testWidgets('onboarding preserves artwork width: ${config.name}', (
      tester,
    ) async {
      tester.view.physicalSize = config.size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              padding: config.padding,
              viewPadding: config.padding,
              textScaler: TextScaler.linear(config.scale),
            ),
            child: child!,
          ),
          home: const OnboardingIntroPage(),
        ),
      );
      await tester.pump(const Duration(milliseconds: 50));
      expect(tester.takeException(), isNull);
      final art = find.byWidgetPredicate(
        (widget) =>
            widget is Image &&
            widget.image is AssetImage &&
            (widget.image as AssetImage).assetName.endsWith(
              'onboarding_home.webp',
            ),
      );
      final artRect = tester.getRect(art);
      expect(artRect.left, closeTo(24, 0.01));
      expect(artRect.width, closeTo(config.size.width - 48, 0.01));

      final button = find.byType(AppButtonV2);
      final originalButtonRect = tester.getRect(button);
      expect(
        originalButtonRect.bottom,
        lessThanOrEqualTo(config.size.height - config.padding.bottom),
      );
      expect(originalButtonRect.height, 56);
      final scroll = tester.state<ScrollableState>(
        find
            .descendant(
              of: find.byType(SingleChildScrollView).first,
              matching: find.byType(Scrollable),
            )
            .first,
      );
      if (config.name == 'small' ||
          config.name == 'large text' ||
          config.name == 'landscape') {
        expect(scroll.position.maxScrollExtent, greaterThan(0));
        scroll.position.jumpTo(scroll.position.maxScrollExtent);
        await tester.pump();
        expect(tester.getRect(button), originalButtonRect);
      } else {
        expect(scroll.position.maxScrollExtent, closeTo(0, 0.1));
      }

      for (var page = 0; page < 3; page++) {
        await tester.tap(find.text('다음'));
        await tester.pump();
        await tester.pump(const Duration(seconds: 1));
        expect(tester.takeException(), isNull);
        expect(tester.getRect(button), originalButtonRect);
      }
      expect(find.text('시작하기'), findsOneWidget);
    });
  }
}
