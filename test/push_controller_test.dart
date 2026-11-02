import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runiverse/core/storage/device_id_store.dart';
import 'package:runiverse/features/auth/presentation/auth_provider.dart';
import 'package:runiverse/features/auth/presentation/auth_state.dart';
import 'package:runiverse/features/notification/domain/device_repository.dart';
import 'package:runiverse/features/notification/domain/push_landing.dart';
import 'package:runiverse/features/notification/domain/push_messaging.dart';
import 'package:runiverse/features/notification/presentation/push_provider.dart';

/// 푸시 기기 등록과 눌린 푸시.
///
/// ## ⚠️ 등록이 빠지면 아무도 모른다
///
/// 서버는 등록된 기기에만 보낸다. 앱이 등록을 놓치면 오류 화면도 없이 그
/// 사람에게만 푸시가 안 온다. 그래서 명세 2-1이 정한 때마다 보내는지를 본다.
void main() {
  const me = AuthSignedIn('u-1', isOnboarded: true);
  const signedOut = AuthSignedOut(returning: true);

  ({
    ProviderContainer container,
    _FakeMessaging messaging,
    _FakeDevices devices,
    _Auth auth,
  })
  build({
    AuthState initial = const AuthUnknown(),
    OpenedPush? initialOpened,
    DeviceIdStore deviceIds = const _FixedDeviceId(),
  }) {
    final messaging = _FakeMessaging()..initial = initialOpened;
    final devices = _FakeDevices();
    final container = ProviderContainer(
      overrides: [
        pushMessagingProvider.overrideWithValue(messaging),
        deviceRepositoryProvider.overrideWithValue(devices),
        deviceIdStoreProvider.overrideWithValue(deviceIds),
        authControllerProvider.overrideWith(() => _Auth(initial)),
      ],
    );
    addTearDown(container.dispose);
    container.read(pushProvider.notifier).start();
    return (
      container: container,
      messaging: messaging,
      devices: devices,
      auth: container.read(authControllerProvider.notifier) as _Auth,
    );
  }

  PushController push(ProviderContainer c) => c.read(pushProvider.notifier);

  // 등록은 토큰 → 기기 식별자 → 서버로 이어진다. 그 사슬이 다 끝날 때까지 기다린다.
  Future<void> settle() => Future<void>.delayed(Duration.zero);

  group('언제 올리는가', () {
    test('로그인 상태가 되면 토큰과 기기 식별자를 올린다', () async {
      final app = build(initial: me);
      await settle();

      expect(app.devices.sent, ['device-1/fcm-1']);
    });

    test('같은 계정 안에서 상태만 바뀌면 다시 올리지 않는다', () async {
      final app = build();
      app.auth.set(const AuthSignedIn('u-1', isOnboarded: false));
      await settle();
      // 프로필을 채웠다. 계정은 그대로다.
      app.auth.set(me);
      await settle();

      expect(app.devices.sent, hasLength(1));
    });

    test('다시 로그인하면 다시 올린다', () async {
      // 서버는 로그인·로그아웃 때 기기를 전부 끈다. 다시 켜야 한다.
      final app = build(initial: me);
      await settle();
      app.auth.set(signedOut);
      app.auth.set(const AuthSignedIn('u-2', isOnboarded: true));
      await settle();

      expect(app.devices.sent, hasLength(2));
    });

    test('토큰이 바뀌면 새 토큰으로 올린다', () async {
      final app = build(initial: me);
      await settle();
      app.messaging.refreshes.add('fcm-2');
      await settle();

      expect(app.devices.sent.last, 'device-1/fcm-2');
    });

    test('⚠️ 올리는 중에 토큰이 바뀌면 앞 등록이 끝난 뒤에 보낸다', () async {
      // 동시에 내보내면 서버가 새 토큰을 옛 토큰으로 덮어쓸 수 있다.
      final app = build(initial: me);
      final hold = Completer<void>();
      app.devices.hold = hold;
      await settle();

      app.messaging.refreshes.add('fcm-2');
      await settle();
      expect(app.devices.sent, ['device-1/fcm-1']);

      hold.complete();
      await settle();
      expect(app.devices.sent, ['device-1/fcm-1', 'device-1/fcm-2']);
    });

    test('로그인 전에 생긴 토큰은 보내지 않는다', () async {
      final app = build(initial: signedOut);
      app.messaging.refreshes.add('fcm-2');
      await settle();

      expect(app.devices.sent, isEmpty);
    });
  });

  group('실패와 복귀', () {
    test('망 문제로 실패하면 복귀 때 한 번 더 보낸다', () async {
      final app = build(initial: me);
      app.devices.failWith = DeviceFailure.network;
      await settle();
      app.devices.failWith = null;

      await push(app.container).resume();
      // 성공했으니 다음 복귀에는 보내지 않는다.
      await push(app.container).resume();

      expect(app.devices.sent, hasLength(2));
    });

    test('토큰 갱신이 망 문제로 실패해 세션 만료로 와도 복귀 때 보낸다', () async {
      // `TokenRefresher`는 거절과 망 실패를 둘 다 `null`로 돌려준다. 정말
      // 끝난 세션이면 로그아웃 상태가 되어 보내지 않는다.
      final app = build(initial: me);
      app.devices.failWith = DeviceFailure.sessionExpired;
      await settle();
      app.devices.failWith = null;

      await push(app.container).resume();

      expect(app.devices.sent, hasLength(2));
    });

    test('⚠️ 업데이트가 필요하면 복귀해도 보내지 않는다', () async {
      // 같은 403이 돌아올 뿐이다.
      final app = build(initial: me);
      app.devices.failWith = DeviceFailure.updateRequired;
      await settle();

      await push(app.container).resume();

      expect(app.devices.sent, hasLength(1));
    });

    test('⚠️ 기기 식별자를 못 읽어도 던지지 않고 복귀 때 보낸다', () async {
      // 던지면 셸이 기다리지 않는 자리라 치명 오류로 기록된다.
      final app = build(initial: me, deviceIds: _FlakyDeviceId());
      await settle();
      expect(app.devices.sent, isEmpty);

      await push(app.container).resume();

      expect(app.devices.sent, ['device-1/fcm-1']);
    });

    test('토큰이 아직 없으면 복귀 때 다시 묻는다', () async {
      final app = build();
      app.messaging.currentToken = null;
      app.auth.set(me);
      await settle();
      expect(app.devices.sent, isEmpty);

      app.messaging.currentToken = 'fcm-1';
      await push(app.container).resume();

      expect(app.devices.sent, ['device-1/fcm-1']);
    });

    test('권한 창을 닫는 사이에 토큰이 생겼으면 그때 보낸다', () async {
      final app = build();
      app.messaging.currentToken = null;
      app.auth.set(me);
      await settle();

      final dialog = Completer<void>();
      app.messaging.permissionHold = dialog;
      final asking = push(app.container).askPermission();
      await settle();
      // 창이 떠 있는 사이에 토큰이 생긴다.
      app.messaging.currentToken = 'fcm-1';
      dialog.complete();
      await asking;
      // 한 번 실행에 한 번만 묻는다.
      await push(app.container).askPermission();

      expect(app.devices.sent, ['device-1/fcm-1']);
      expect(app.messaging.permissionAsks, 1);
    });

    test('⚠️ 나가 있던 등록이 로그아웃 뒤에 실패해도 다시 보내지 않는다', () async {
      final app = build(initial: me);
      final hold = Completer<void>();
      app.devices
        ..hold = hold
        ..failWith = DeviceFailure.network;
      await settle();

      app.auth.set(signedOut);
      hold.complete();
      await settle();
      await push(app.container).resume();

      expect(app.devices.sent, hasLength(1));
    });
  });

  group('눌린 푸시', () {
    const friendRequest = OpenedPush(
      messageId: 'm-1',
      data: {'type': 'FRIEND_REQUESTED', 'actorId': 'u-9'},
    );

    test('뒤에 있던 앱에서 누른 푸시를 셸이 한 번만 꺼내 간다', () async {
      final app = build(initial: me);
      app.messaging.taps.add(
        const OpenedPush(
          messageId: 'm-1',
          data: {'type': 'MATCH_CONFIRMED', 'runningRoomId': '130'},
        ),
      );
      await settle();

      expect(push(app.container).take(), isA<PushLandingRoom>());
      expect(push(app.container).take(), isNull);
    });

    test('꺼진 앱을 연 푸시는 로그인 판정 전에도 받아 둔다', () async {
      // 스플래시가 세션을 되살리는 동안 도착한다.
      final app = build(initialOpened: friendRequest);
      await settle();

      expect(app.container.read(pushProvider), isA<PushLandingProfile>());
    });

    test('⚠️ 셸이 연 뒤에 같은 누름이 또 와도 다시 열지 않는다', () async {
      // 두 겹으로 쌓이면 뒤로가기를 눌러도 같은 화면이 또 나온다.
      final app = build(initial: me, initialOpened: friendRequest);
      await settle();
      expect(push(app.container).take(), isA<PushLandingProfile>());

      app.messaging.taps.add(friendRequest);
      await settle();

      expect(push(app.container).take(), isNull);
    });

    group('셸이 없는 사이', () {
      // 출발 1분 전 대기방으로 옮길 때(`LaunchGate`) 셸이 내려간다. 그 사이 누름을
      // 남겨 두면 러닝을 마치고 홈에 돌아온 순간 한참 전에 누른 화면이 열린다.

      test('⚠️ 셸이 내려간 사이에 누른 푸시는 버린다', () async {
        final app = build(initial: me);
        push(app.container)
          ..attachShell()
          ..detachShell();

        app.messaging.taps.add(friendRequest);
        await settle();
        push(app.container).attachShell();

        expect(push(app.container).take(), isNull);
      });

      test('셸이 서기 전에 누른 푸시는 받아 둔다', () async {
        // 꺼진 앱을 연 누름이다.
        final app = build(initial: me, initialOpened: friendRequest);
        await settle();
        push(app.container).attachShell();

        expect(push(app.container).take(), isA<PushLandingProfile>());
      });

      test('⚠️ 꺼진 앱을 연 누름이 두 통로로 어느 순서로 와도 한 번 연다', () async {
        // 두 통로가 같은 누름을 준다(implementation-notes 15-7). 순서는 정해져 있지 않다.
        final app = build(initial: me, initialOpened: friendRequest);
        app.messaging.taps.add(friendRequest);
        await settle();
        push(app.container).attachShell();

        expect(push(app.container).take(), isA<PushLandingProfile>());
        expect(push(app.container).take(), isNull);
      });

      test('⚠️ 받아 둔 직후 셸이 내려갔으면 다음 셸에서 열지 않는다', () async {
        // 누른 프레임에 바로 출발 직전 이동이 겹쳐 셸이 옮기지 못한 경우다.
        final app = build(initial: me);
        push(app.container).attachShell();
        app.messaging.taps.add(friendRequest);
        await settle();

        push(app.container)
          ..detachShell()
          ..attachShell();

        expect(push(app.container).take(), isNull);
      });

      test('셸을 갈아끼우는 사이에 하나라도 서 있으면 받아 둔다', () async {
        // 새 셸이 먼저 서고 옛 셸이 나중에 내려갈 수 있다.
        final app = build(initial: me);
        push(app.container)
          ..attachShell()
          ..attachShell()
          ..detachShell();

        app.messaging.taps.add(friendRequest);
        await settle();

        expect(push(app.container).take(), isA<PushLandingProfile>());
      });

      test('로그아웃 뒤 다시 들어오면 셸이 서기 전 누름을 받아 둔다', () async {
        // 가입하는 사람은 셸 전에 프로필 입력을 거친다. 앞 로그인에 셸이 섰던
        // 이력 때문에 버리면, 처음 켠 사람과 동작이 달라진다.
        final app = build(initial: me);
        push(app.container)
          ..attachShell()
          ..detachShell();
        app.auth
          ..set(signedOut)
          ..set(const AuthSignedIn('u-2', isOnboarded: false));

        app.messaging.taps.add(friendRequest);
        await settle();
        push(app.container).attachShell();

        expect(push(app.container).take(), isA<PushLandingProfile>());
      });
    });

    test('⚠️ 로그아웃하면 눌러 둔 자리를 버린다', () async {
      // 남겨 두면 다음에 들어온 다른 계정이 앞 사람의 화면을 연다.
      final app = build(initial: me);
      app.messaging.taps.add(
        const OpenedPush(messageId: 'm-1', data: {'type': 'RUNNING_REMINDER'}),
      );
      await settle();

      app.auth.set(signedOut);

      expect(app.container.read(pushProvider), isNull);
    });
  });
}

class _FakeMessaging implements PushMessaging {
  String? currentToken = 'fcm-1';
  OpenedPush? initial;
  var permissionAsks = 0;

  /// 채우면 권한 창이 떠 있는 것처럼 [requestPermission]이 여기서 기다린다.
  Completer<void>? permissionHold;
  final refreshes = StreamController<String>.broadcast();
  final taps = StreamController<OpenedPush>.broadcast();

  @override
  Future<void> requestPermission() async {
    permissionAsks++;
    await permissionHold?.future;
  }

  @override
  Future<String?> token() async => currentToken;

  @override
  Stream<String> get tokenRefreshes => refreshes.stream;

  @override
  Future<OpenedPush?> initialOpened() async => initial;

  @override
  Stream<OpenedPush> get opened => taps.stream;
}

/// 받은 등록을 `기기/토큰`으로 적어 둔다.
class _FakeDevices implements DeviceRepository {
  final sent = <String>[];
  DeviceFailure? failWith;

  /// 채워 두면 서버 응답을 그때까지 붙잡는다.
  Completer<void>? hold;

  @override
  Future<void> register({
    required String deviceId,
    required String pushToken,
  }) async {
    sent.add('$deviceId/$pushToken');
    await hold?.future;
    final failure = failWith;
    if (failure != null) throw DeviceException(failure);
  }
}

class _FixedDeviceId implements DeviceIdStore {
  const _FixedDeviceId();

  @override
  Future<String> read() async => 'device-1';
}

/// 처음 한 번은 플랫폼 오류로 실패한다(Keystore·Keychain 일시 오류).
class _FlakyDeviceId implements DeviceIdStore {
  var _failed = false;

  @override
  Future<String> read() async {
    if (!_failed) {
      _failed = true;
      throw StateError('저장소를 읽지 못했다');
    }
    return 'device-1';
  }
}

/// 테스트가 상태를 바꿔 끼우는 컨트롤러.
class _Auth extends AuthController {
  _Auth(this.initial);

  final AuthState initial;

  @override
  AuthState build() => initial;

  void set(AuthState next) => state = next;
}
