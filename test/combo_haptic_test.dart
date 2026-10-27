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
/// 유일한 통로라서 **언제 울리느냐**가 곧 기능이다. 통지마다 울리면 10초마다
/// 떨려 아무 뜻이 없고, 너무 성기면 붙은 줄을 모른다.
///
/// 여기서 검사하는 것은 둘이다 — **눈금에서만 울리는가**, 그리고 **함께
/// 이어진 사람이 늘면 세기가 올라가는가.**
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

  group('눈금에서만 울린다', () {
    test('⚠️ 붙는 순간(1)에 울린다', () async {
      // 1은 "이어졌다"와 같은 순간이다. 둘을 따로 두면 붙을 때 두 번 떨린다.
      await running();

      await push([peer('u-2', 1)]);

      expect(felt, ['HapticFeedbackType.lightImpact']);
    });

    test('⚠️ 눈금 사이에서는 조용하다', () async {
      // 통지는 10초마다 온다. 그때마다 울리면 달리는 내내 떨린다.
      final container = await running();
      await push([peer('u-2', 1)]);
      felt.clear();

      await push([peer('u-2', 2)]);

      expect(felt, isEmpty);
      expect(container.read(partyProvider).combos['u-2']?.comboCount, 2);
    });

    test('3·5·10에서 다시 울린다', () async {
      await running();
      for (final count in [1, 2, 3, 4, 5]) {
        await push([peer('u-2', count)]);
      }
      expect(felt.length, 3, reason: '1·3·5 세 번이다');

      felt.clear();
      for (final count in [6, 7, 8, 9, 10]) {
        await push([peer('u-2', count)]);
      }
      expect(felt.length, 1, reason: '10 한 번이다');
    });

    test('⚠️ 5를 넘기면 5마다다', () async {
      // 10마다는 100초라 그 사이 이어지는지 끊겼는지 알 수 없었다.
      await running();
      await push([peer('u-2', 10)]);
      felt.clear();

      for (final count in [11, 12, 13, 14, 15]) {
        await push([peer('u-2', count)]);
      }
      expect(felt.length, 1, reason: '15 한 번이다');

      felt.clear();
      for (final count in [16, 17, 18, 19, 20]) {
        await push([peer('u-2', count)]);
      }
      expect(felt.length, 1, reason: '20 한 번이다');
    });

    test('⚠️ 끊겼다 다시 이어지면 1부터 다시 울린다', () async {
      // 최고 기록을 넘을 때만 울리면, 오래 붙어 있다 한 번 놓친 사람은
      // 그 뒤로 아무 말도 듣지 못한다.
      await running();
      await push([peer('u-2', 20)]);
      await push(const []);
      felt.clear();

      await push([peer('u-2', 1)]);

      expect(felt, ['HapticFeedbackType.lightImpact']);
    });

    test('⚠️ 재연결로 건너뛰어도 한 번만 울린다', () async {
      // 0에서 7로 뛴다. 1·3·5를 몰아 울리면 세 번 떨려 뜻을 잃는다.
      await running();

      await push([peer('u-2', 7)]);

      expect(felt.length, 1);
    });
  });

  group('⚠️ 함께 이어진 사람이 늘면 세게, 여러 번 울린다', () {
    // 세기만으로는 구분이 어렵다 — 암밴드·주머니에 넣고 뛰면 기기에 따라
    // light 와 medium 이 거의 같게 느껴진다. **횟수가 확실한 쪽**이다.
    test('둘이면 약하게 한 번', () async {
      await running();
      await push([peer('u-2', 1)]);
      expect(felt, ['HapticFeedbackType.lightImpact']);
    });

    test('셋이면 중간으로 두 번', () async {
      await running();
      await push([peer('u-2', 1), peer('u-3', 1)]);
      expect(felt, [
        'HapticFeedbackType.mediumImpact',
        'HapticFeedbackType.mediumImpact',
      ]);
    });

    test('넷이면 세게 세 번', () async {
      await running();
      await push([peer('u-2', 1), peer('u-3', 1), peer('u-4', 1)]);
      expect(felt, [
        'HapticFeedbackType.heavyImpact',
        'HapticFeedbackType.heavyImpact',
        'HapticFeedbackType.heavyImpact',
      ]);
    });

    test('⚠️ 눈금은 가장 높은 콤보 하나로 센다', () async {
      // 상대마다 세면 4명 방에서 30초에 세 번 떨리고, 어느 상대 것인지도
      // 알 수 없다. 한 눈금에 한 번(머릿수만큼)이다.
      await running();
      await push([peer('u-2', 3), peer('u-3', 1)]);

      expect(felt, [
        'HapticFeedbackType.mediumImpact',
        'HapticFeedbackType.mediumImpact',
      ], reason: '셋이 이어졌으니 중간으로 두 번');
    });
  });

  group('끊김', () {
    test('콤보가 풀리면 울린다', () async {
      await running();
      await push([peer('u-2', 5)]);
      felt.clear();

      await push(const []);

      expect(felt, ['HapticFeedbackType.mediumImpact']);
    });

    test('⚠️ 아무 콤보도 없던 통지에는 울리지 않는다', () async {
      // 솔로이거나 아직 아무와도 안 겹친 구간이다. 10초마다 빈 통지가 온다.
      await running();

      await push(const []);
      await push(const []);

      expect(felt, isEmpty);
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
