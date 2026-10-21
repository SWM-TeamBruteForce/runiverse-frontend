import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runiverse/core/strings/app_strings.dart';
import 'package:runiverse/core/theme/app_theme.dart';
import 'package:runiverse/features/matching/domain/room_info.dart';
import 'package:runiverse/features/matching/presentation/match_countdown_page.dart';
import 'package:runiverse/features/matching/presentation/match_room_provider.dart';
import 'package:runiverse/features/session/data/fake_location_repository.dart';
import 'package:runiverse/features/session/domain/location_repository.dart';
import 'package:runiverse/features/session/presentation/run_session_provider.dart';

/// 출발 대기실 — **설정에 다녀온 사람을 받는가.**
///
/// ## 왜 이 화면이 제일 중요한가
///
/// 매칭 러닝에는 출발 준비 화면이 없다. `LaunchGate`가 **출발 30초 전에** 여기로
/// 밀어 넣고, 그때 권한 팝업이 처음 뜬다. iOS는 한 번 거절하면 곧바로
/// `deniedForever`라 **설정 앱에 다녀와야** 하는데, 권한을 들어올 때 한 번만
/// 읽으면 켜고 돌아와도 "위치 권한이 없어요"가 그대로 남는다.
///
/// ⚠️ **팝업이 30초 전에 뜨는 것 자체**는 이 테스트가 다루지 않는다. 정본은
/// 매칭 등록(S08)에서 묻게 되어 있고, 그 복원은 따로 할 일이다.
void main() {
  late FakeLocationRepository location;

  /// 아직 쏘지 않는 대기실.
  ///
  /// ## ⚠️ 출발 시각을 **달력에 박으면 안 된다**
  ///
  /// `MatchRoomState.launch`는 `launchAt`이 없으면 **방의 `scheduledStartAt`으로
  /// 내려간다.** 그래서 "시각을 안 줬으니 안 쏜다"가 아니다 — 박아 둔 시각이
  /// 지나는 순간 카운트다운이 돌고 `_launch()`가 러닝 화면으로 넘어가려다
  /// `No GoRouter found in context`로 죽는다.
  ///
  /// 실제로 그렇게 깨졌다(2026-10-20에 쓰고 하루 뒤 빨개졌다). **지금으로부터
  /// 떨어진 시각**으로 둬야 날짜가 바뀌어도 같은 뜻이다.
  MatchRoomState waiting() => MatchRoomState(
    room: RoomInfo(
      runningRoomId: 7,
      status: RoomStatus.matched,
      scheduledStartAt: DateTime.now().add(const Duration(hours: 1)),
      players: const [
        RoomPlayer(userId: 'u-1', nickname: '나', isDeleted: false),
      ],
    ),
  );

  Future<void> pumpCountdown(
    WidgetTester tester, {
    required LocationAccess access,
  }) async {
    location = FakeLocationRepository(access: access);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          locationRepositoryProvider.overrideWithValue(location),
          // 진짜 컨트롤러는 매칭 스트림에 붙는다. `build`만 갈아 끼워 방
          // 하나를 세운다 — 서버도 타이머도 필요 없다.
          matchRoomProvider.overrideWith(() => _Waiting(waiting())),
        ],
        child: MaterialApp(
          theme: AppTheme.dark(),
          home: const MatchCountdownPage(),
        ),
      ),
    );
    // ⚠️ `pumpAndSettle`을 쓸 수 없다. 이 화면은 100ms마다 다시 그리는
    // 타이머를 돌려서 영영 멎지 않는다.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
  }

  /// 타이머를 끊는다. 두고 끝내면 "Timer is still pending"으로 죽는다.
  Future<void> leave(WidgetTester tester) =>
      tester.pumpWidget(const SizedBox.shrink());

  /// 앱이 뒤로 갔다 돌아온다. **곧장 `resumed`로 보낼 수 없다** —
  /// 생명주기는 단계를 건너뛰지 못한다.
  Future<void> leaveAndReturn(WidgetTester tester) async {
    for (final state in const [
      AppLifecycleState.inactive,
      AppLifecycleState.hidden,
      AppLifecycleState.paused,
      AppLifecycleState.hidden,
      AppLifecycleState.inactive,
      AppLifecycleState.resumed,
    ]) {
      tester.binding.handleAppLifecycleStateChanged(state);
    }
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
  }

  testWidgets('⚠️ 권한을 켜고 오면 안내가 사라진다', (tester) async {
    await pumpCountdown(tester, access: LocationAccess.deniedForever);
    expect(find.text(AppStrings.matchCountdownGpsDenied), findsOneWidget);

    // 설정 앱에서 켜고 돌아온다.
    location.access = LocationAccess.granted;
    await leaveAndReturn(tester);

    // 고치기 전에는 출발할 때까지 이 문구가 남아 있었다.
    expect(find.text(AppStrings.matchCountdownGpsDenied), findsNothing);
    await leave(tester);
  });

  testWidgets('⚠️ 이미 허용된 상태면 다시 묻지 않는다', (tester) async {
    // 돌아올 때마다 `prepare()`를 다시 부르면 **방금 연 위치 구독을 끊고
    // 새로 연다.** 출발 직전이라 그 사이의 좌표가 통째로 빈다.
    await pumpCountdown(tester, access: LocationAccess.granted);
    expect(location.ensureAccessCount, 1);

    await leaveAndReturn(tester);

    expect(location.ensureAccessCount, 1);
    await leave(tester);
  });
}

/// 방 하나를 들고 가만히 있는 컨트롤러. [build]만 갈아 끼운다.
class _Waiting extends MatchRoomController {
  _Waiting(this.initial);

  final MatchRoomState initial;

  @override
  MatchRoomState build() => initial;
}
