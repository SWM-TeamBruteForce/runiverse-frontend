import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runiverse/core/network/ws_client.dart';
import 'package:runiverse/core/network/ws_message.dart';
import 'package:runiverse/core/storage/token_store.dart';
import 'package:runiverse/features/auth/presentation/auth_provider.dart';
import 'package:runiverse/features/session/data/fake_location_repository.dart';
import 'package:runiverse/features/session/data/fake_track_repository.dart';
import 'package:runiverse/features/session/data/fake_user_status_repository.dart';
import 'package:runiverse/features/session/domain/finish_outcome.dart';
import 'package:runiverse/features/session/domain/run_numbers.dart';
import 'package:runiverse/features/session/domain/run_progress.dart';
import 'package:runiverse/features/session/domain/track_point.dart';
import 'package:runiverse/features/session/domain/run_snapshot.dart';
import 'package:runiverse/features/session/domain/running_channel.dart';
import 'package:runiverse/features/session/domain/user_status.dart';
import 'package:runiverse/features/session/presentation/party_provider.dart';
import 'package:runiverse/features/session/presentation/run_session_provider.dart';
import 'package:runiverse/features/session/presentation/running_connection_provider.dart';
import 'package:runiverse/features/session/presentation/user_status_provider.dart';

/// 콤보가 쌓일 때 울리는 진동.
///
/// ## ⚠️ 달리는 사람은 화면을 보지 않는다
///
/// 콤보 배지는 화면에 있지만, 뛰는 동안 폰은 암밴드나 주머니에 있다. 진동이
/// 유일한 통로라서 **언제 어떻게 울리느냐**가 곧 기능이다.
///
/// 울림은 세 가지다.
///
/// - **틱** — 콤보가 오를 때마다. 이어지고 있다는 신호다.
/// - **눈금** — 1·3·5·10, 그다음 10마다. 크고 길게(연타로 뭉친다).
/// - **끊김** — 목록에서 빠질 때. 빈 배열이면 전원이다.
///
/// 셋 다 **지금 함께 이어진 사람 수**만큼 세진다.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _PushChannel channel;
  late List<String> felt;

  setUp(() {
    felt = [];
    // ⚠️ `HapticFeedback`은 플랫폼 채널 한 통으로 나간다. 세기는 인자에만
    // 담기므로, 메서드만 세면 light 와 heavy 를 구분하지 못한다.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'HapticFeedback.vibrate') {
            felt.add('${call.arguments ?? 'vibrate'}');
          }
          return null;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  Future<ProviderContainer> makeContainer() async {
    final tokens = InMemoryTokenStore();
    await tokens.saveSession(
      userId: 'u-1',
      accessToken: 'a-1',
      refreshToken: 'r-1',
      isOnboarded: true,
    );
    channel = _PushChannel();
    return ProviderContainer.test(
      overrides: [
        tokenStoreProvider.overrideWithValue(tokens),
        locationRepositoryProvider.overrideWithValue(FakeLocationRepository()),
        trackRepositoryProvider.overrideWithValue(FakeTrackRepository()),
        userStatusRepositoryProvider.overrideWithValue(
          FakeUserStatusRepository(
            status: UserStatusRunning(
              runningRoomId: 13,
              isSolo: false,
              scheduledStartAt: DateTime(2026, 9, 18, 15, 5),
            ),
          ),
        ),
        runningChannelFactoryProvider.overrideWithValue((_) => channel),
      ],
    );
  }

  Future<void> settle() => Future<void>.delayed(Duration.zero);

  ComboPeer peer(String id, int count) => ComboPeer(
    userId: id,
    gapMeters: 12,
    comboCount: count,
    maxComboCount: count,
  );

  /// 보드를 붙이고 콤보 통지를 받을 준비를 마친다.
  Future<ProviderContainer> running() async {
    final container = await makeContainer();
    await container
        .read(runningConnectionProvider.notifier)
        .openMatched(13, targetDistanceMeters: 3000);
    container.read(partyProvider);
    await settle();
    felt.clear();
    return container;
  }

  /// 콤보 통지 한 번.
  ///
  /// ⚠️ **진동이 끝나기를 기다린다.** 머릿수만큼 연달아 울리므로 사이에 틈이
  /// 있다. `Duration.zero`만 흘리면 첫 번만 세고 나머지를 놓친다.
  Future<void> push(List<ComboPeer> peers) async {
    channel.combos_.add(RunCombo(peers));
    await Future<void>.delayed(const Duration(milliseconds: 300));
  }

  group('틱 — 콤보가 오를 때마다', () {
    test('⚠️ 붙는 순간은 틱만 울린다', () async {
      // 명세상 `comboCount`는 **붙는 순간 0**이다(No 9). 0은 눈금이 아니므로
      // 여기서 크게 울리면 10초 뒤 눈금 1에서 연달아 두 번 크게 떨린다.
      await running();

      await push([peer('u-2', 0)]);

      expect(felt, ['HapticFeedbackType.selectionClick']);
    });

    test('눈금이 아닌 자리에서도 오르면 울린다', () async {
      await running();
      await push([peer('u-2', 1)]);
      felt.clear();

      await push([peer('u-2', 2)]);

      expect(felt, ['HapticFeedbackType.selectionClick']);
    });

    test('⚠️ 같은 값이 겹쳐 오면 울리지 않는다', () async {
      // 명세: 같은 관계를 두고 양쪽 배치가 각각 메시지를 만들 수 있다. 값이
      // 같으면 화면이 안 바뀌므로 진동도 없어야 한다.
      await running();
      await push([peer('u-2', 2)]);
      felt.clear();

      await push([peer('u-2', 2)]);

      expect(felt, isEmpty);
    });
  });

  group('눈금 — 1·3·5·10 그다음 10마다', () {
    test('1·3·5에서 크게 울린다', () async {
      await running();
      for (final count in [0, 1, 2, 3, 4, 5]) {
        await push([peer('u-2', count)]);
      }

      // 0·2·4는 틱, 1·3·5는 눈금(둘이라 medium 두 번씩).
      expect(felt.where((f) => f.endsWith('selectionClick')).length, 3);
      expect(felt.where((f) => f.endsWith('mediumImpact')).length, 6);
    });

    test('⚠️ 10을 넘기면 10마다다 — 15는 눈금이 아니다', () async {
      await running();
      await push([peer('u-2', 10)]);
      felt.clear();

      for (final count in [11, 13, 15, 17, 19]) {
        await push([peer('u-2', count)]);
      }
      expect(
        felt.where((f) => f.endsWith('mediumImpact')),
        isEmpty,
        reason: '11~19 사이에는 눈금이 없다',
      );

      felt.clear();
      await push([peer('u-2', 20)]);
      expect(felt.where((f) => f.endsWith('mediumImpact')).length, 2);
    });

    test('⚠️ 재연결로 건너뛰어도 한 번만 울린다', () async {
      // 0에서 7로 뛴다. 1·3·5를 몰아 울리면 뜻을 잃는다.
      await running();

      await push([peer('u-2', 7)]);

      expect(felt.length, 2, reason: '눈금 한 번(두 번 연타)이다');
    });

    test('⚠️ 끊겼다 다시 이어지면 1부터 다시 울린다', () async {
      // 최고 기록을 넘을 때만 울리면, 오래 붙어 있다 한 번 놓친 사람은
      // 그 뒤로 아무 말도 듣지 못한다. 일시정지하면 서버도 0부터 새로 센다.
      await running();
      await push([peer('u-2', 20)]);
      await push(const []);
      felt.clear();

      await push([peer('u-2', 1)]);

      expect(felt, [
        'HapticFeedbackType.mediumImpact',
        'HapticFeedbackType.mediumImpact',
      ]);
    });

    test('⚠️ 눈금은 상대마다 따로 본다', () async {
      // "동일한 콤보 건"이 기준이다. 가장 높은 하나로 묶으면 뒤에 붙은
      // 사람의 눈금이 영영 안 울린다.
      await running();
      await push([peer('u-2', 9), peer('u-3', 0)]);
      felt.clear();

      // u-2는 10(눈금), u-3는 1(눈금). 한 메시지라 한 번만 울린다.
      await push([peer('u-2', 10), peer('u-3', 1)]);
      expect(felt.length, 2, reason: '셋이 이어졌으니 heavy 두 번');

      felt.clear();
      // u-2는 눈금이 아니지만 u-3는 3이라 눈금이다.
      await push([peer('u-2', 11), peer('u-3', 2)]);
      await push([peer('u-2', 12), peer('u-3', 3)]);
      expect(
        felt.where((f) => f.endsWith('heavyImpact')).length,
        2,
        reason: 'u-3의 3이 눈금이다',
      );
    });
  });

  group('⚠️ 함께 이어진 사람이 늘면 세진다', () {
    test('틱 — 둘 selectionClick · 셋 light · 넷 medium', () async {
      // ⚠️ 눈금에 닿지 않는 수로 올린다. 11~19 사이는 눈금이 없고, 새로
      // 붙는 상대는 0이라 역시 눈금이 아니다.
      await running();
      await push([peer('u-2', 11)]);
      felt.clear();

      await push([peer('u-2', 12)]);
      expect(felt, ['HapticFeedbackType.selectionClick']);

      felt.clear();
      await push([peer('u-2', 13), peer('u-3', 0)]);
      expect(felt, ['HapticFeedbackType.lightImpact']);

      felt.clear();
      await push([peer('u-2', 14), peer('u-3', 0), peer('u-4', 0)]);
      expect(felt, ['HapticFeedbackType.mediumImpact']);
    });

    test('눈금 — 둘 medium 두 번', () async {
      await running();
      await push([peer('u-2', 0)]);
      felt.clear();

      await push([peer('u-2', 1)]);

      expect(felt, [
        'HapticFeedbackType.mediumImpact',
        'HapticFeedbackType.mediumImpact',
      ]);
    });

    test('눈금 — 셋이면 heavy 두 번', () async {
      await running();
      await push([peer('u-2', 0), peer('u-3', 0)]);
      felt.clear();

      await push([peer('u-2', 1), peer('u-3', 0)]);

      expect(felt, [
        'HapticFeedbackType.heavyImpact',
        'HapticFeedbackType.heavyImpact',
      ]);
    });

    test('눈금 — 넷이면 heavy 세 번', () async {
      await running();
      await push([peer('u-2', 0), peer('u-3', 0), peer('u-4', 0)]);
      felt.clear();

      await push([peer('u-2', 1), peer('u-3', 0), peer('u-4', 0)]);

      expect(felt, [
        'HapticFeedbackType.heavyImpact',
        'HapticFeedbackType.heavyImpact',
        'HapticFeedbackType.heavyImpact',
      ]);
    });
  });

  group('끊김', () {
    test('⚠️ 빈 배열은 전원 해제다', () async {
      // 명세 규칙: 빈 배열을 받으면 콤보 표시를 모두 제거한다.
      final container = await running();
      await push([peer('u-2', 5)]);
      felt.clear();

      await push(const []);

      expect(felt, ['HapticFeedbackType.mediumImpact']);
      expect(container.read(partyProvider).combos, isEmpty);
    });

    test('⚠️ 콤보가 없는 동안 오는 빈 배열에는 울리지 않는다', () async {
      // 솔로이거나 아직 아무와도 안 겹친 구간이다.
      await running();

      await push(const []);
      await push(const []);

      expect(felt, isEmpty);
    });

    test('⚠️ 끊김이 눈금보다 먼저다', () async {
      // 한 메시지에 둘이 겹치면 연달아 떨려 뜻을 잃는다. 풀린 것은 달리는
      // 사람이 할 일이 있다는 신호고, 눈금은 칭찬이다.
      await running();
      await push([peer('u-2', 0), peer('u-3', 0)]);
      felt.clear();

      // u-2가 빠지고 u-3는 눈금(1)에 닿는다.
      await push([peer('u-3', 1)]);

      expect(felt, ['HapticFeedbackType.mediumImpact']);
    });
  });
}

class _PushChannel implements RunningChannel {
  final progress_ = StreamController<RunProgress>.broadcast();
  final combos_ = StreamController<RunCombo>.broadcast();
  final snapshots_ = StreamController<RunSnapshot>.broadcast();

  @override
  Stream<WsConnectionState> get states => const Stream.empty();

  @override
  WsConnectionState get state => WsConnectionState.connected;

  @override
  Stream<WsErrorCode> get errors => const Stream.empty();

  @override
  Stream<RunProgress> get progress => progress_.stream;

  @override
  Stream<RunCombo> get combos => combos_.stream;

  @override
  Stream<RunSnapshot> get snapshots => snapshots_.stream;

  @override
  Stream<void> get finished => const Stream.empty();

  @override
  Stream<RunNumbers> get serverNumbers => const Stream.empty();

  @override
  Future<void> start(int runningRoomId) async {}

  @override
  bool sendLocations(List<TrackPoint> points) => true;

  @override
  bool pause() => true;

  @override
  bool resume() => true;

  @override
  Future<FinishOutcome> finish({bool forced = false}) async =>
      const FinishConfirmed();

  @override
  Future<void> close() async {}
}
