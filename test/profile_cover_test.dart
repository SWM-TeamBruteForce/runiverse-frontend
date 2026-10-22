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

  testWidgets('⚠️ 그늘막을 깔지 않는다', (tester) async {
    // 커버가 상태바 **아래에서** 시작하도록 바뀌면서(화면이 위 여백을 받는다)
    // 사진 위에 지킬 글자가 없어졌다.
    //
    // 그늘막을 남겨 두면 사진 위쪽에 **회색 막대**만 얹힌다 — 실제로 기기에서
    // "배경 사진 윗부분이 너무 가린다"로 드러났다(2026-10-23).
    //
    // ⚠️ **열쇠로 찾지 않는다.** 그늘막과 함께 열쇠도 지웠으므로, 열쇠를 보는
    // 그물은 다시 깔아도 통과한다. 그라데이션 자체를 찾는다.
    await pumpCover(tester, url: null, topInset: 40);
    await tester.pump();

    expect(
      find.byWidgetPredicate((w) {
        final decoration = w is DecoratedBox ? w.decoration : null;
        return decoration is BoxDecoration && decoration.gradient != null;
      }),
      findsNothing,
    );
  });

  testWidgets('⚠️ 사진을 잘라내지 않는다', (tester) async {
    // `BoxFit.cover`는 커버 비율(412:200)에 맞춰 **남는 쪽을 베어낸다.** 세로
    // 사진을 올린 사람은 가운데 띠만 보게 된다 — 기기에서 "일부분이 잘린 것처럼
    // 보인다"로 드러났다(2026-10-23). 비율은 지키고 **전체**를 넣는다.
    await pumpCover(tester, url: 'https://cdn.test/cover.jpg');

    final image = tester.widget<Image>(find.byType(Image));
    expect(image.fit, BoxFit.contain);
    await settleRetry(tester);
  });

  testWidgets('⚠️ 위 여백을 스스로 받지 않는다', (tester) async {
    // 여백을 주는 것은 화면(`ProfilePage`)의 `SafeArea`다. 커버가 또 받으면
    // 상태바 높이만큼 두 번 밀려 내려간다.
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
