import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:runiverse/core/strings/app_strings.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runiverse/core/theme/app_theme.dart';
import 'package:runiverse/core/widgets/v2/app_button.dart';
import 'package:runiverse/features/onboarding/presentation/onboarding_intro_page.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    final loader = FontLoader('SUIT');
    for (final weight in [
      'Regular',
      'Medium',
      'SemiBold',
      'Bold',
      'ExtraBold',
    ]) {
      loader.addFont(rootBundle.load('assets/fonts/SUIT-$weight.ttf'));
    }
    await loader.load();
  });
  const titles = [
    AppStrings.onboardingCard1Title,
    AppStrings.onboardingCard2Title,
    AppStrings.onboardingCard3Title,
    AppStrings.onboardingCard4Title,
  ];
  const bodies = [
    AppStrings.onboardingCard1Body,
    AppStrings.onboardingCard2Body,
    AppStrings.onboardingCard3Body,
    AppStrings.onboardingCard4Body,
  ];
  for (final config in [
    (
      name: 'extra tall',
      size: Size(384, 950),
      padding: EdgeInsets.zero,
      scale: 1.0,
    ),
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
    testWidgets(
      'onboarding balances content and keeps controls stable: ${config.name}',
      (tester) async {
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
        expect(artRect.center.dx, closeTo(config.size.width / 2, 0.01));
        final targetWidth = math.min(config.size.width - 48, 336.0);
        expect(
          artRect.width,
          inInclusiveRange(targetWidth * 0.8 - 0.01, targetWidth),
        );
        final titleTop = tester.getTopLeft(find.text(titles.first)).dy;
        final bodyBottom = tester.getBottomLeft(find.text(bodies.first)).dy;
        final viewport = tester.getRect(find.byType(PageView));

        final button = find.byType(AppButtonV2);
        final originalButtonRect = tester.getRect(button);
        expect(
          originalButtonRect.bottom,
          closeTo(config.size.height - config.padding.bottom - 32, 0.01),
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
        final contentFits = scroll.position.maxScrollExtent < 0.1;
        if (config.name == 'small' ||
            config.name == 'large text' ||
            config.name == 'landscape') {
          expect(scroll.position.maxScrollExtent, greaterThan(0));
          scroll.position.jumpTo(scroll.position.maxScrollExtent);
          await tester.pump();
          expect(tester.getRect(button), originalButtonRect);
        } else {
          expect(scroll.position.maxScrollExtent, closeTo(0, 0.1));
          expect(bodyBottom, lessThanOrEqualTo(viewport.bottom));
          expect(
            artRect.top - viewport.top,
            closeTo(viewport.bottom - bodyBottom, 0.1),
          );
        }

        for (var page = 0; page < 3; page++) {
          await tester.tap(find.text('다음'));
          await tester.pump();
          await tester.pump(const Duration(seconds: 1));
          expect(tester.takeException(), isNull);
          expect(tester.getRect(button), originalButtonRect);
          expect(
            tester.getTopLeft(find.text(titles[page + 1])).dy,
            closeTo(titleTop, 0.1),
          );
        }
        expect(find.text('시작하기'), findsOneWidget);
        if (contentFits) {
          final songCard = find
              .ancestor(
                of: find.text(AppStrings.onboardingSampleSong),
                matching: find.byType(Container),
              )
              .first;
          expect(
            tester.getBottomLeft(songCard).dy,
            closeTo(artRect.bottom, 0.1),
          );
        }
      },
    );
  }
}
