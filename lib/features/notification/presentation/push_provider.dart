import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:runiverse/core/storage/device_id_store.dart';
import 'package:runiverse/features/auth/presentation/auth_provider.dart';
import 'package:runiverse/features/auth/presentation/auth_state.dart';
import 'package:runiverse/features/notification/data/http_device_repository.dart';
import 'package:runiverse/features/notification/domain/device_repository.dart';
import 'package:runiverse/features/notification/domain/push_landing.dart';
import 'package:runiverse/features/notification/domain/push_messaging.dart';

/// 푸시 SDK. 기본은 [NoopPushMessaging]이고, 진짜는 `main.dart`가 끼운다.
///
/// ⚠️ **main의 override를 지우면 푸시가 조용히 멈춘다.** 토큰이 없으니 서버에
/// 기기를 올리지 않고, 서버는 보낼 곳이 없다.
final pushMessagingProvider = Provider<PushMessaging>(
  (ref) => const NoopPushMessaging(),
);

/// 기기 식별자를 어디에 둘 것인가.
///
/// 셸을 띄우는 위젯 테스트도 override하지 않아도 된다 — 토큰이 없으면 읽지 않는다.
final deviceIdStoreProvider = Provider<DeviceIdStore>(
  (ref) => SecureDeviceIdStore(),
);

final deviceRepositoryProvider = Provider<DeviceRepository>(
  (ref) => HttpDeviceRepository(
    ref.watch(dioProvider),
    ref.watch(tokenStoreProvider),
    ref.watch(tokenRefresherProvider),
  ),
);

/// 푸시 기기 등록과 눌린 푸시. 상태는 **눌렸지만 아직 옮기지 않은 자리**다.
final pushProvider = NotifierProvider<PushController, PushLanding?>(
  PushController.new,
);

/// 이 기기를 서버에 푸시 받을 곳으로 올리고, 눌린 푸시를 셸에 넘긴다.
///
/// ## 언제 올리는가 — 명세 2-1
///
/// | 때 | 여기서 |
/// |---|---|
/// | 스플래시가 세션을 되살렸다 · 로그인·가입했다 · 계정을 바꿨다 | 로그인 상태의 `userId`가 바뀔 때 |
/// | 토큰이 처음 생겼다 · 바뀌었다 | [PushMessaging.tokenRefreshes] |
/// | 포그라운드 복귀 | [resume] — 앞선 등록이 실패로 남았을 때만 |
///
/// 로그아웃하면 나가 있는 등록의 결과를 버리고 다시 보내지 않는다. 서버는
/// 로그아웃 때 이 계정의 기기를 이미 끈다 — 앱이 따로 해제하지 않는다.
///
/// ## 왜 셸이 아니라 앱 루트에서 시작하는가
///
/// 가입한 사람은 셸에 닿기 전에 프로필 입력을 거친다. 셸에서 시작하면 그
/// 화면을 마치기 전까지 등록이 미뤄진다.
class PushController extends Notifier<PushLanding?> {
  late final PushMessaging _messaging;
  final _subscriptions = <StreamSubscription<Object?>>[];
  var _started = false;

  /// 기기를 맡긴 계정. 로그아웃이면 `null`이다.
  String? _userId;

  /// 등록 순번. **로그아웃하거나 새 등록이 시작되면 올라간다** — 그 전에 나간
  /// 등록이 늦게 끝나도 결과를 버린다.
  var _attempt = 0;

  /// 마지막 등록이 다시 보낼 만한 이유로 실패했는가. 복귀 때 이것만 다시 보낸다.
  var _failed = false;

  /// 서버로 나가는 등록을 한 줄로 세운다.
  ///
  /// ⚠️ **동시에 내보내지 않는다.** 옛 토큰을 올리는 중에 새 토큰이 오면, 서버가
  /// 새 것을 먼저 받고 옛 것으로 덮어쓸 수 있다. 그러면 푸시는 죽은 토큰으로
  /// 가고, 앱은 성공으로 알아 다시 보내지도 않는다.
  Future<void> _sending = Future<void>.value();

  var _askedPermission = false;

  /// 이미 받은 누름의 `messageId`.
  ///
  /// ⚠️ **같은 누름이 두 번 올 수 있다.** 꺼진 앱을 연 누름이 두 번 들어온 것을
  /// 에뮬레이터에서 봤다(2026-10-31). 셸이 화면을 연 뒤에 두 번째가 오면 같은 화면이
  /// 두 겹 쌓이므로, 들어오는 타이밍에 기대지 않고 ID로 거른다.
  final _handled = <String>{};

  /// 지금 서 있는 셸 수. 셸이 세워질 때 [attachShell], 내려갈 때 [detachShell].
  ///
  /// 수로 센다 — 갈아끼울 때 새 셸이 먼저 서고 옛 셸이 나중에 내려갈 수 있다.
  var _shells = 0;

  /// 이 로그인에서 셸이 한 번이라도 섰는가. 꺼진 앱을 연 누름은 셸이 서기 전에
  /// 온다 — 그때는 받아 둔다.
  var _shellSeen = false;

  /// 셸이 모두 내려갈 때마다 올라간다. 받아 둔 자리가 어느 셸 때의 것인지 가린다.
  var _shellEpoch = 0;
  var _landingEpoch = 0;

  @override
  PushLanding? build() {
    _messaging = ref.read(pushMessagingProvider);
    ref.onDispose(() {
      for (final subscription in _subscriptions) {
        unawaited(subscription.cancel());
      }
    });
    return null;
  }

  /// 앱이 뜰 때 한 번 부른다. 로그인 상태와 토큰·눌린 푸시를 듣기 시작한다.
  void start() {
    if (_started) return;
    _started = true;

    ref.listen(
      authControllerProvider,
      (_, next) => _onAuth(next),
      fireImmediately: true,
    );
    _subscriptions
      ..add(_messaging.tokenRefreshes.listen(_onToken, onError: _onError))
      ..add(
        _messaging.opened.listen(
          (push) => _onOpened(push, from: 'opened'),
          onError: _onError,
        ),
      );
    unawaited(_readInitialOpened());
  }

  /// 포그라운드로 돌아왔다. **앞선 등록이 실패로 남았을 때만** 다시 보낸다.
  Future<void> resume() async {
    if (_failed && _userId != null) await _register();
  }

  /// 알림 권한을 묻는다. 한 번 실행에 한 번만 묻는다.
  ///
  /// ⚠️ **안드로이드는 한 번 거절해도 다음 실행에 한 번 더 뜬다.** OS가 두 번째
  /// 거절부터 창을 막는다. 러닝 출발(`ensureRunNotification`)도 같은 권한을
  /// 같은 방식으로 묻는다.
  Future<void> askPermission() async {
    if (_askedPermission) return;
    _askedPermission = true;
    await _messaging.requestPermission();
    // iOS는 설치 직후 APNs 토큰이 늦게 올 수 있다. 창을 닫는 사이에 생겼으면
    // 지금 보낸다.
    if (_failed && _userId != null) await _register();
  }

  /// 셸이 옮길 자리를 꺼내 간다. 꺼내면 비운다 — 같은 푸시로 두 번 옮기지 않는다.
  ///
  /// ⚠️ **받은 뒤 셸이 내려갔으면 내주지 않는다.** 누른 직후 출발 직전 이동으로
  /// 셸이 내려가 옮기지 못한 자리다. 러닝을 마치고 홈에 돌아온 순간 열리면
  /// 한참 전에 누른 화면이 갑자기 뜬다.
  PushLanding? take() {
    final landing = state;
    if (landing != null) state = null;
    return _landingEpoch == _shellEpoch ? landing : null;
  }

  /// 셸이 섰다. 셸의 `initState`가 부른다.
  void attachShell() {
    _shells++;
    _shellSeen = true;
  }

  /// 셸이 내려갔다. 셸의 `dispose`가 부른다.
  ///
  /// 여기서 [state]를 바꾸지 않는다 — 위젯이 내려가는 도중에 provider를 바꾸면
  /// Riverpod이 막는다. 받아 둔 자리는 [take]가 셸 차수로 거른다.
  void detachShell() {
    assert(_shells > 0, '붙이지 않은 셸을 뗐다');
    _shells--;
    if (_shells == 0) _shellEpoch++;
  }

  void _onAuth(AuthState auth) {
    switch (auth) {
      case AuthUnknown():
        return;
      case AuthSignedIn(:final userId):
        // 닉네임·온보딩처럼 같은 계정 안에서 상태만 바뀐 것이면 보내지 않는다.
        if (userId == _userId) return;
        _userId = userId;
        unawaited(_register());
      case AuthSignedOut():
        _userId = null;
        _attempt++;
        _failed = false;
        // ⚠️ **눌러 둔 자리도 버린다.** 남겨 두면 다음에 들어온 다른 계정이
        // 앞 사람의 화면을 연다.
        if (state != null) state = null;
        // 다음 로그인도 셸이 서기 전 누름은 받아 둔다(처음 켠 것과 같게).
        // 셸 수는 두지 않는다 — 아직 서 있는 셸이 내려가면서 뺀다.
        _shellSeen = false;
    }
  }

  void _onToken(String token) {
    // 로그인 전이면 그때 보낸다.
    if (_userId == null) return;
    unawaited(_register(token: token));
  }

  Future<void> _register({String? token}) {
    final attempt = ++_attempt;
    _failed = false;
    final sent = _sending.then((_) => _send(attempt, token));
    // 앞 등록이 뜻밖의 오류로 끝나도 줄은 이어 간다. 그 오류는 [sent]를
    // 기다리는 쪽이 받는다 — 여기서 삼키는 것이 아니다.
    _sending = sent.then<void>((_) {}, onError: (Object _) {});
    return sent;
  }

  Future<void> _send(int attempt, String? token) async {
    // 줄을 기다리는 사이에 로그아웃했거나 더 새 등록이 들어왔다. 새 것만 보낸다.
    if (!ref.mounted || attempt != _attempt) return;

    try {
      final pushToken = token ?? await _messaging.token();
      if (!ref.mounted || attempt != _attempt) return;
      if (pushToken == null) {
        _failed = true;
        return;
      }

      final deviceId = await ref.read(deviceIdStoreProvider).read();
      if (!ref.mounted || attempt != _attempt) return;
      await ref
          .read(deviceRepositoryProvider)
          .register(deviceId: deviceId, pushToken: pushToken);
      if (attempt == _attempt) debugPrint('[push] 기기를 등록했다');
    } on DeviceException catch (error) {
      if (attempt != _attempt) return;
      debugPrint('[push] 기기를 등록하지 못했다 · ${error.failure.name}');
      _failed = switch (error.failure) {
        DeviceFailure.network => true,
        // ⚠️ **세션 만료도 다시 보낸다.** 토큰 갱신이 망 문제로 실패해도 이것으로
        // 온다(`TokenRefresher`가 둘 다 `null`이다). 정말 끝난 세션이면 곧
        // 로그아웃 상태가 되어 [resume]이 보내지 않는다.
        DeviceFailure.sessionExpired => true,
        // 다시 보내도 같은 답이다.
        DeviceFailure.updateRequired || DeviceFailure.unknown => false,
      };
    } on Object catch (error) {
      if (attempt != _attempt) return;
      // 기기 저장소 같은 플랫폼 쪽 실패다. 복귀 때 다시 해 본다.
      //
      // ⚠️ **던지지 않는다.** 셸은 [resume]·[askPermission]을 기다리지 않고
      // 부르므로, 던지면 처리되지 않은 오류가 되어 Crashlytics에 치명 오류로 쌓인다.
      debugPrint('[push] 기기를 등록하지 못했다 · ${error.runtimeType}');
      _failed = true;
    }
  }

  Future<void> _readInitialOpened() async {
    final push = await _messaging.initialOpened();
    if (!ref.mounted || push == null) return;
    _onOpened(push, from: 'initial');
  }

  /// [from]은 로그에만 쓴다 — 두 번 왔을 때 어느 통로인지 가리려고 남긴다.
  void _onOpened(OpenedPush push, {required String from}) {
    final id = push.messageId;
    debugPrint('[push] 푸시를 눌렀다 · ${push.data['type']} · $from');
    if (id != null && !_handled.add(id)) {
      debugPrint('[push] 이미 받은 누름이다. 버린다');
      return;
    }
    final landing = PushLanding.of(push.data);
    if (landing == null) return;
    // 로그아웃 상태면 받지 않는다(위 [_onAuth]와 같은 이유).
    if (ref.read(authControllerProvider) is AuthSignedOut) return;
    // ⚠️ **셸이 섰다가 내려간 사이에 누른 것은 버린다.** 출발 직전부터 러닝을
    // 마칠 때까지다. 남겨 두면 홈에 돌아온 순간 한참 전에 누른 화면이 열린다.
    // 알림함에는 남아 있다.
    if (_shellSeen && _shells == 0) {
      debugPrint('[push] 셸이 없는 사이의 누름이다. 버린다');
      return;
    }
    _landingEpoch = _shellEpoch;
    state = landing;
  }

  void _onError(Object error) {
    debugPrint('[push] 푸시 스트림 오류 · $error');
  }
}
