import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runiverse/core/theme/app_theme.dart';
import 'package:runiverse/features/profile/data/fake_profile_image_repository.dart';
import 'package:runiverse/features/profile/domain/profile_image_failure.dart';
import 'package:runiverse/features/profile/presentation/background_image_provider.dart';
import 'package:runiverse/features/profile/presentation/profile_cover.dart';

/// 프로필 커버 — **사진이 없을 때 무엇을 그리는가.**
///
/// ## ⚠️ 세 상태가 같은 그림이다
///
/// 조회 중 · 안 올린 사람 · 조회 실패. 셋 다 기본 단색이고 회전 표시가 없다.
/// 커버는 화면 폭 전체라, 로딩 표시를 넣으면 **프로필을 열 때마다 큰 사각형이
/// 번쩍인다.** 아바타가 이미 같은 규칙으로 간다.
void main() {
  /// ⚠️ **커버는 스스로 조회하지 않는다.** 화면(`ProfilePage`)이 부른다. 그래서
  /// 조회한 뒤의 그림을 보려면 여기서 대신 불러 줘야 한다 — [loaded]가 거짓이면
  /// **조회 중** 상태 그대로다.
  Future<void> pumpCover(
    WidgetTester tester, {
    String? url,
    ProfileImageFailure? failWith,
    double topInset = 0,
    bool loaded = true,
  }) async {
    final repository = FakeProfileImageRepository(
      latency: Duration.zero,
      url: url,
      failWith: failWith,
    );
    final container = ProviderContainer.test(
      overrides: [
        backgroundImageRepositoryProvider.overrideWithValue(repository),
      ],
    );
    // ⚠️ **기다리지 않고 시작만 한다.** `pumpWidget` 전에 `await`하면 가짜
    // 시간을 진행시킬 `pump`가 아직 없어 **테스트가 멈춘다**(가짜 저장소 주석).
    if (loaded) {
      unawaited(
        container.read(backgroundImageControllerProvider.notifier).load(),
      );
    }
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.dark(),
          home: MediaQuery(
            data: MediaQueryData(padding: EdgeInsets.only(top: topInset)),
            child: const Scaffold(body: Column(children: [ProfileCover()])),
          ),
        ),
      ),
    );
    // ⚠️ **간격을 줘야 한다.** 인자 없는 `pump()`는 가짜 시간을 흘리지 않아
    // 조회 타이머가 영영 안 깨고, 테스트는 "남은 타이머"로 거부된다.
    await tester.pump(const Duration(milliseconds: 1));
    await tester.pump();
  }

  /// ⚠️ **테스트에서 `Image.network`는 늘 실패한다**(flutter_test가 HTTP를
  /// 막는다). 그래서 주소를 넣은 테스트는 **깨짐 → 한 번 다시 받기**가 실제로
  /// 돌고, 그 조회 타이머를 재워 주지 않으면 "남은 타이머"로 거부된다.
  Future<void> settleRetry(WidgetTester tester) async {
    await tester.pump(const Duration(milliseconds: 1));
    await tester.pump();
  }

  testWidgets('주소가 있으면 사진을 그린다', (tester) async {
    await pumpCover(tester, url: 'https://cdn.test/cover.jpg');

    expect(find.byType(Image), findsOneWidget);
    await settleRetry(tester);
  });

  group('⚠️ 세 상태가 모두 기본 단색이다', () {
    testWidgets('조회 중', (tester) async {
      await pumpCover(tester, loaded: false);

      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.byType(Image), findsNothing);
    });

    testWidgets('안 올린 사람', (tester) async {
      await pumpCover(tester, url: null);
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.byType(Image), findsNothing);
    });

    testWidgets('조회 실패', (tester) async {
      // 할 수 있는 일이 없다. 오류 표시를 띄우면 기본 배경 자리에 경고가 선다.
      await pumpCover(tester, failWith: ProfileImageFailure.network);
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.byType(Image), findsNothing);
    });
  });

  testWidgets('⚠️ 기본 배경일 때도 그늘막이 깔린다', (tester) async {
    // 상태에 따라 켜고 끄면 틀렸을 때 **시계가 사라지는 쪽으로** 틀린다.
    await pumpCover(tester, url: null);
    await tester.pump();

    expect(find.byKey(ProfileCover.scrimKey), findsOneWidget);
  });

  testWidgets('사진이 있을 때도 그늘막이 깔린다', (tester) async {
    await pumpCover(tester, url: 'https://cdn.test/cover.jpg');

    expect(find.byKey(ProfileCover.scrimKey), findsOneWidget);
    await settleRetry(tester);
  });

  testWidgets('⚠️ 위 여백을 받지 않는다 — 상태바 뒤까지 올라간다', (tester) async {
    // SafeArea 안에 있으면 커버 위에 바탕색 띠가 생기고, 시안의 "사진이 시계
    // 뒤까지"가 성립하지 않는다.
    await pumpCover(tester, url: null, topInset: 40);
    await tester.pump();

    expect(tester.getTopLeft(find.byType(ProfileCover)).dy, 0);
  });

  testWidgets('비율이 시안과 같다 — 412:200', (tester) async {
    await pumpCover(tester, url: null);
    await tester.pump();

    final size = tester.getSize(find.byType(ProfileCover));
    expect(size.height, closeTo(size.width * 200 / 412, 0.5));
  });
}
