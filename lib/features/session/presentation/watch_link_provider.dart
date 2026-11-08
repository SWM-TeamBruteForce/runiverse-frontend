import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:runiverse/core/storage/body_profile_provider.dart';
import 'package:runiverse/core/strings/app_strings.dart';
import 'package:runiverse/core/watch/watch_channel.dart';
import 'package:runiverse/features/auth/presentation/auth_provider.dart';
import 'package:runiverse/features/auth/presentation/auth_state.dart';
import 'package:runiverse/features/record/domain/run_detail.dart';
import 'package:runiverse/features/record/presentation/record_provider.dart';
import 'package:runiverse/features/session/domain/party_board.dart';
import 'package:runiverse/features/session/domain/run_session_state.dart';
import 'package:runiverse/features/session/domain/running_room.dart';
import 'package:runiverse/features/session/domain/watch_payload.dart';
import 'package:runiverse/features/session/presentation/party_provider.dart';
import 'package:runiverse/features/session/presentation/run_control_provider.dart';
import 'package:runiverse/features/session/presentation/run_session_provider.dart';
import 'package:runiverse/features/session/presentation/running_connection_provider.dart';

/// 워치 통로. `null` 이면 워치와 주고받지 않는다.
///
/// 네이티브 쪽이 안드로이드에만 있어 기본은 `null` 이고 `main.dart` 가 안드로이드에서만
/// 끼운다 — 테스트·iOS에서 받기를 걸면 멈추거나 `MissingPluginException` 이 난다.
final watchChannelProvider = Provider<WatchChannel?>((ref) => null);

final watchLinkProvider = NotifierProvider<WatchLinkController, void>(
  WatchLinkController.new,
);

/// 러닝 상태를 워치로 보내고 워치 명령을 받는다. 메시지와 보내는 규칙은 워치 레포
/// `docs/phone-communication.md` 가 정본이다.
///
/// 앱 루트에서 시작한다. 러닝을 시작하며 워치 앱을 켤 때 받기 등록이 끝나 있어야
/// 켜자마자 오는 `WATCH_SYNC` 를 받는다.
class WatchLinkController extends Notifier<void> {
  /// 워치 화면이 켜진 동안 상태를 보내는 간격.
  static const _tick = Duration(seconds: 1);

  /// 이만큼 화면 신호가 없으면 꺼진 것으로 본다. 워치는 켜진 동안 10초마다 알린다.
  static const _visibleFor = Duration(seconds: 15);

  /// 워치 앱 켜기가 "아직 받을 준비 안 됨"이면 이 간격으로 이만큼 더 시도한다.
  ///
  /// 폰 앱을 켤 때 워치에 닿지 못했으면 받기 등록이 러닝을 시작하는 그 순간에야
  /// 다시 걸려, 첫 켜기는 늘 등록이 끝나기 전에 닿는다.
  static const _launchRetryGap = Duration(seconds: 1);
  static const _launchRetries = 3;

  /// 받기 등록이 실패하면 이만큼 뒤에 다시 구독한다. 안 하면 앱을 다시 켤 때까지
  /// 워치가 보내는 것을 못 받는다.
  static const _relistenAfter = Duration(seconds: 5);

  /// 보내기 요청에 이만큼 답이 없으면 실패로 본다. 답을 끝내 못 받은 요청을 진행 중으로
  /// 세어 두면 그 뒤 1초 전송이 앱을 다시 켤 때까지 전부 걸러진다.
  static const _sendTimeout = Duration(seconds: 3);

  WatchChannel? _channel;
  StreamSubscription<WatchMessage>? _messages;
  Timer? _relisten;
  Timer? _ticker;
  Timer? _visibility;
  var _started = false;
  var _visible = false;

  /// 나가 있는 전송 수. 1초 전송은 이게 0이 될 때까지 [_queued] 로 미룬다.
  var _inFlight = 0;

  /// 앞 전송이 끝나기를 기다리는 1초 전송이 있는가. 끝나면 최신 상태 하나를 보낸다.
  var _queued = false;

  /// 마지막으로 보낸 러닝 시간(초). 달리는 중엔 이게 바뀔 때 보낸다.
  int? _sentSecond;

  /// 폰 앱이 켜질 때마다 새 값.
  final _phoneInstanceId = _newId();
  var _stateSequence = 0;
  var _statusVersion = 0;

  /// 마지막으로 처리한 워치 명령.
  String? _lastRequestId;

  /// 이번 러닝을 시작한 계정. 로그인이 만료돼도 세션은 남아서, 그 뒤 들어온 명령을
  /// 가리는 데 쓴다.
  String? _runOwnerId;

  /// 마지막으로 알린 단계. 바뀔 때만 [_statusVersion] 을 올린다.
  _Stage _stage = _Stage.none;

  /// 연결이 종료를 처리하는 중인가([RunningConnectionState.settling] 을 따라 선다).
  /// 폰 버튼·워치 명령은 그보다 먼저 [RunControlState.finishing] 이 선다 — 둘을 합친
  /// 값은 [_isFinishing].
  ///
  /// [RunningConnectionState.settling] 이 내려가도 방이 그대로일 때만 푼다(보류·거절로
  /// 러닝이 이어짐). 확정되면 연결이 먼저 비워지고 세션이 나중에 끝나서, 그 사이에
  /// 풀면 워치가 `종료 중` → 달리는 중 → 결과로 깜빡인다.
  var _finishing = false;

  /// 종료 답을 기다리는 중인가. 단계와 보낼 값이 같은 판정을 쓴다 — 갈리면 번호만
  /// 오르고 `종료 중` 은 안 뜬다.
  bool get _isFinishing => _finishing || ref.read(runControlProvider).finishing;

  /// 마지막으로 본 이번 러닝의 방. 연결이 비워져도 결과에 방 번호를 싣는다.
  RunningRoom? _room;

  /// 지난 러닝의 방. 연결 쪽은 요약을 닫아도 끝난 방을 들고 있어, 새 솔로 방이
  /// 늦게 열리면 그 번호가 워치로 간다.
  RunningRoom? _lastRunRoom;

  /// 이번 러닝에서 워치 앱을 켰는가.
  var _launched = false;

  /// 켜기를 "준비 안 됨"으로 끝까지 못 보냈는가. 받기를 다시 걸면 한 번 더 시도한다.
  var _launchGaveUp = false;

  /// 끝난 러닝의 서버 기록. 폰 요약(S15)과 같은 조회다.
  ProviderSubscription<AsyncValue<RunDetail>>? _detail;
  int? _detailRoomId;

  @override
  void build() {
    ref.onDispose(_stop);
  }

  /// 앱이 뜰 때 한 번 부른다.
  void start() {
    if (_started) return;
    _started = true;

    final channel = ref.read(watchChannelProvider);
    if (channel == null) return;
    _channel = channel;

    _listen(channel);
    ref.listen(
      runSessionControllerProvider,
      (_, next) => _onSession(next),
      fireImmediately: true,
    );
    ref.listen(runningConnectionProvider, _onConnection);
    ref.listen(partyProvider, _onParty);
    ref.listen(runControlProvider, (_, _) {
      _syncDetail();
      _syncStage();
    });
  }

  void _listen(WatchChannel channel) {
    _messages = channel.messages.listen(
      _onMessage,
      // 받기가 실패하면 구독을 풀었다가 다시 건다 — 다시 걸 때 네이티브가 등록을 새로 한다.
      // 그사이에도 보내기는 계속한다.
      onError: (Object error) {
        debugPrint('[watch] 받기 실패 · $error');
        unawaited(_messages?.cancel());
        _messages = null;
        _relisten?.cancel();
        _relisten = Timer(_relistenAfter, () {
          _listen(channel);
          final session = ref.read(runSessionControllerProvider);
          if (_launchGaveUp &&
              (session is RunRunning || session is RunPaused)) {
            unawaited(_launch());
          }
        });
      },
    );
  }

  void _onMessage(WatchMessage message) {
    switch (message.event) {
      // syncId 가 없으면 돌려줄 수 없다 — 워치는 그 답을 못 읽고 버린다.
      case WatchEvents.watchSync when message.data['syncId'] is String:
        unawaited(_sendSynced(message.data['syncId'] as String));
      case WatchEvents.watchVisibilityUpdate:
        _onVisibility(message.data['isVisible'] == true);
      // requestId 가 없으면 답할 수 없다 — 워치는 3초 뒤 SYNC 로 다시 맞춘다.
      case WatchEvents.watchPause ||
              WatchEvents.watchResume ||
              WatchEvents.watchFinish
          when message.data['requestId'] is String:
        _onCommand(message);
      case _:
        break;
    }
  }

  /// 워치 명령을 폰 버튼과 같은 길로 처리한다. 답은 바뀐 상태다.
  void _onCommand(WatchMessage message) {
    final requestId = message.data['requestId'] as String;
    if (requestId == _lastRequestId) {
      unawaited(_sendState());
      return;
    }

    final rejection = _rejectionOf(message.data);
    if (rejection != null) {
      debugPrint('[watch] ${message.event} 거절 · ${rejection.code}');
      unawaited(
        _send(
          WatchEvents.error,
          () => {
            'code': rejection.code,
            'message': rejection.message,
            'sourceType': message.event,
            'requestId': requestId,
          },
        ),
      );
      return;
    }

    // 먼저 적어 둔다 — 아래에서 단계가 바뀌면 그 자리에서 상태가 나간다.
    _lastRequestId = requestId;
    final sent = _stateSequence;
    final control = ref.read(runControlProvider.notifier);
    switch (message.event) {
      case WatchEvents.watchPause:
        control.pause();
      case WatchEvents.watchResume:
        control.resume();
      case WatchEvents.watchFinish:
        unawaited(
          control.finishByWatch(forced: message.data['forced'] == true),
        );
      case _:
        break;
    }
    // 단계가 안 바뀌어 아직 안 나갔다. 답이 없으면 워치가 3초 동안 잠긴다.
    if (_stateSequence == sent) unawaited(_sendState());
  }

  /// 명령을 거절할 이유. `null` 이면 받는다.
  _Rejection? _rejectionOf(Map<String, dynamic> command) {
    final session = ref.read(runSessionControllerProvider);
    if (session is! RunRunning && session is! RunPaused) {
      return _Rejection.noRun;
    }
    final auth = ref.read(authControllerProvider);
    if (auth is! AuthSignedIn || auth.userId != _runOwnerId) {
      return _Rejection.notRunOwner;
    }
    if (command['phoneInstanceId'] != _phoneInstanceId) {
      return _Rejection.otherPhoneInstance;
    }
    if (command['statusVersion'] != _statusVersion) {
      return _Rejection.staleStatus;
    }
    final roomId = command['runningRoomId'];
    final connection = ref.read(runningConnectionProvider);
    if (roomId != null && roomId != (_liveRoom(connection) ?? _room)?.id) {
      return _Rejection.otherRoom;
    }
    return null;
  }

  void _onVisibility(bool visible) {
    _visibility?.cancel();
    _visibility = null;
    _visible = visible;
    if (visible) {
      _visibility = Timer(_visibleFor, () => _onVisibility(false));
      // 화면이 꺼진 사이 놓친 결과를 되찾게 러닝이 끝났어도 보낸다.
      unawaited(_sendState());
    }
    _syncTicker();
  }

  void _onSession(RunSessionState session) {
    if (session is RunIdle || session is RunPreparing) {
      // 러닝을 마치고 돌아온 순간 연결에 남은 방이 지난 방이다. 출발 전끼리 오갈 때
      // 다시 잡으면 그사이 열린 새 방을 지난 방으로 만든다.
      if (_stage != _Stage.none) {
        _lastRunRoom = ref.read(runningConnectionProvider).room;
      }
      _launched = false;
      _launchGaveUp = false;
      _finishing = false;
      _room = null;
    }
    if (session is RunFinished) _finishing = false;

    if (!_launched && session is RunRunning) {
      _launched = true;
      final auth = ref.read(authControllerProvider);
      _runOwnerId = auth is AuthSignedIn ? auth.userId : null;
      unawaited(_launch());
    }
    // 단계보다 먼저 건다 — 끝났다는 첫 상태부터 "받는 중"이어야 숫자가 바뀌지 않는다.
    _syncDetail();
    _syncStage();
    _syncTicker();
    _sendOnSecond(session);
  }

  void _onConnection(
    RunningConnectionState? previous,
    RunningConnectionState next,
  ) {
    final room = _liveRoom(next);
    final roomArrived = room != null && !identical(room, _room);
    _room = room ?? _room;

    final session = ref.read(runSessionControllerProvider);
    final running = session is RunRunning || session is RunPaused;
    if (running && next.settling) {
      _finishing = true;
    } else if (_finishing &&
        previous?.settling == true &&
        !next.settling &&
        room != null) {
      _finishing = false;
    } else if (_finishing &&
        next.trackRejected &&
        !next.settling &&
        room != null &&
        next.finishedRoomId == null) {
      // 구간 번호 거부로 끝내려다 확인을 못 받았다. 폰 러닝 화면은 달리는 중으로 남으니
      // 워치도 풀어 준다 — 안 풀면 폰에서 종료할 때까지 `종료 중`에 갇힌다.
      _finishing = false;
    }
    _syncDetail();
    _syncStage();
    // 출발은 방을 기다리지 않아 첫 상태엔 방 번호·목표가 없다. 방이 세워지면 바로
    // 고쳐 보낸다 — 화면이 꺼진 워치는 다음 신호까지 그 값을 들고 있다.
    if (running && roomArrived) unawaited(_sendState());
  }

  /// `RunSummaryPage` 가 서버 기록을 부르는 조건(끝남·종료 확인·확정 대기 아님)에서
  /// 같은 조회를 듣는다. 확정 전에 부르면 빈 기록이 온다.
  void _syncDetail() {
    final session = ref.read(runSessionControllerProvider);
    final connection = ref.read(runningConnectionProvider);
    final room = _liveRoom(connection);
    final roomId =
        session is RunFinished &&
            room != null &&
            connection.finishedRoomId == room.id &&
            !connection.settling
        ? room.id
        : null;
    if (roomId == _detailRoomId) return;

    _detail?.close();
    _detail = null;
    _detailRoomId = roomId;
    if (roomId == null) return;
    _detail = ref.listen(
      runDetailProvider(roomId),
      (_, _) => unawaited(_sendState()),
    );
  }

  /// 결과 숫자의 출처. `RunSummaryPage` 의 `shown` 과 같은 순서다.
  WatchResult _result() {
    final lookup = _detail?.read();
    if (lookup == null) return const WatchResultMeasured();
    final detail = lookup.value;
    final mine = detail?.players.where((p) => p.isMe).firstOrNull;
    // 너무 짧게 달려 내 기록이 안 남으면 조회가 성공해도 숫자가 비어 앱 값을 쓴다.
    if (detail != null && mine != null && mine.hasRecord) {
      return WatchResultConfirmed(
        distanceMeters: detail.distanceMeters,
        duration: detail.duration,
        averagePace: detail.averagePace,
      );
    }
    // 처음 받다 오류가 나면 다시 시도를 기다리지 않고 바로 앱 값으로 간다.
    if (!lookup.hasError && !lookup.hasValue) return const WatchResultLoading();
    return const WatchResultMeasured();
  }

  /// 콤보 순간을 알린다. 워치는 화면이 꺼져 있어도 진동한다.
  void _onParty(PartyBoard? previous, PartyBoard next) {
    if (previous == null || identical(previous.combos, next.combos)) return;

    // 러닝이 끝나 비워진 보드는 끊김이 아니다. 비울 때는 `const PartyBoard()` 를 넣고
    // 갱신은 늘 새 객체를 만들어서, 그 객체와 같은지로 가른다. 명단·진행이 비었는지로
    // 가르면 복구 때 그것들보다 먼저 온 콤보까지 버려진다.
    if (identical(next, const PartyBoard())) return;

    // 다시 붙을 때 스냅샷으로 한 번에 얹힌 콤보도 알리지 않는다 — 폰도 콤보
    // 통지에서만 진동한다. 콤보 통지는 콤보만 바꾼다.
    if (!identical(previous.roster, next.roster) ||
        !identical(previous.progress, next.progress)) {
      return;
    }

    final moments = WatchPayload.comboMoments(
      before: previous.combos,
      after: next.combos,
    );
    for (final moment in moments) {
      unawaited(
        _send(
          WatchEvents.watchComboTriggered,
          () => {
            'eventId': _newId(),
            'userId': moment.userId,
            'comboCount': moment.comboCount,
            'kind': moment.kind.wire,
          },
        ),
      );
    }
  }

  /// 일시정지·재개·종료 단계가 바뀌었으면 번호를 올리고 바로 보낸다.
  ///
  /// 러닝이 사라진 것(폰 요약을 닫음·서버가 끝냄·강퇴)도 바로 보낸다 — 폰에서
  /// 닫으면 워치 결과 화면도 같이 닫힌다.
  void _syncStage() {
    final stage = _stageOf(ref.read(runSessionControllerProvider));
    if (stage == _stage) return;
    _stage = stage;
    _statusVersion++;
    unawaited(_sendState());
  }

  _Stage _stageOf(RunSessionState session) {
    final pending = ref.read(runControlProvider).goalPendingMeters != null;
    return switch (session) {
      RunRunning() || RunPaused() when _isFinishing => _Stage.finishing,
      RunRunning() when pending => _Stage.pendingRunning,
      RunPaused() when pending => _Stage.pendingPaused,
      RunRunning() => _Stage.running,
      RunPaused() => _Stage.paused,
      RunFinished() => _Stage.finished,
      RunIdle() || RunPreparing() => _Stage.none,
    };
  }

  /// 워치 화면이 켜져 있고 러닝이 끝나기 전(일시정지 포함)이면 1초 전송을 돌린다.
  void _syncTicker() {
    final session = ref.read(runSessionControllerProvider);
    final wanted = _visible && (session is RunRunning || session is RunPaused);
    if (!wanted) {
      _ticker?.cancel();
      _ticker = null;
      _queued = false;
      return;
    }
    _ticker ??= Timer.periodic(_tick, (_) {
      // 달리는 중엔 [_sendOnSecond] 가 보낸다. 시간이 멈춘 일시정지만 1초마다.
      if (ref.read(runSessionControllerProvider) is RunRunning) return;
      _sendLatest();
    });
  }

  /// 달리는 중엔 폰 화면 시간이 바뀌는 순간 보낸다. 따로 1초 타이머로 읽으면
  /// 화면이 바뀌기 직전·직후를 오가며 읽어 워치 시간이 2초씩 뛴다.
  void _sendOnSecond(RunSessionState session) {
    if (_ticker == null || session is! RunRunning) return;
    if (session.metrics.clockElapsed.inSeconds == _sentSecond) return;
    _sendLatest();
  }

  /// 앞 전송이 안 끝났으면 건너뛰지 않고, 끝나는 대로 최신 하나를 보낸다.
  /// 건너뛰면 그 초가 빠져 워치 시간이 2초 뛴다.
  void _sendLatest() {
    if (_inFlight > 0) {
      _queued = true;
      return;
    }
    unawaited(_sendState());
  }

  Future<void> _sendState() => _send(WatchEvents.watchStateUpdated, _state);

  Future<void> _sendSynced(String syncId) => _send(
    WatchEvents.watchSynced,
    () => WatchPayload.synced(
      _state(),
      syncId: syncId,
      birthday: ref.read(bodyProfileProvider).birthday,
    ),
  );

  /// 지금 상태 한 벌. 만들 때마다 [_stateSequence] 를 올린다(SYNCED 포함).
  ///
  /// 어느 길로 나가든 최신 상태라 기다리던 1초 전송도 이것으로 갈음한다.
  Map<String, Object?> _state() {
    final connection = ref.read(runningConnectionProvider);
    final session = ref.read(runSessionControllerProvider);
    _queued = false;
    _sentSecond = session is RunRunning
        ? session.metrics.clockElapsed.inSeconds
        : null;
    return WatchPayload.state(
      phoneInstanceId: _phoneInstanceId,
      stateSequence: ++_stateSequence,
      statusVersion: _statusVersion,
      lastRequestId: _lastRequestId,
      session: session,
      room: _liveRoom(connection) ?? _room,
      board: ref.read(partyProvider),
      isServerConnected: connection.isReady,
      finishing: _isFinishing,
      goalPendingMeters: ref.read(runControlProvider).goalPendingMeters,
      result: _result(),
      unknownNickname: AppStrings.runPartyUnknown,
      now: ref.read(runClockProvider)(),
    );
  }

  /// 연결이 들고 있는 이번 러닝의 방. 지난 방이면 `null`.
  RunningRoom? _liveRoom(RunningConnectionState connection) {
    final room = connection.room;
    return identical(room, _lastRunRoom) ? null : room;
  }

  /// 결과는 버린다. 못 받은 것은 워치가 3초 감시와 SYNC 로 다시 맞춘다.
  ///
  /// 보낼 값도 여기서 만든다 — 만들다 던져도 리스너·타이머 밖으로 새지 않게.
  Future<void> _send(
    String event,
    Map<String, Object?> Function() build,
  ) async {
    final channel = _channel;
    if (channel == null) return;
    _inFlight++;
    try {
      await channel.send(event, build()).timeout(_sendTimeout);
    } on Object catch (error) {
      debugPrint('[watch] $event 를 보내지 못했다 · $error');
    } finally {
      _inFlight--;
      if (_queued && _inFlight == 0) unawaited(_sendState());
    }
  }

  /// 워치 앱을 켠다. 받을 준비가 안 돼 켜기 요청을 못 보냈을 때만 다시 시도한다 —
  /// 요청이 한 번 나갔으면 다시 켜지 않는다.
  Future<void> _launch() async {
    final channel = _channel;
    if (channel == null) return;
    _launchGaveUp = false;
    for (var attempt = 0; attempt <= _launchRetries; attempt++) {
      if (attempt > 0) {
        await Future<void>.delayed(_launchRetryGap);
        // 기다리는 사이 provider 가 버려졌으면 ref 를 읽지 않는다.
        if (_channel == null) return;
        final session = ref.read(runSessionControllerProvider);
        if (session is! RunRunning && session is! RunPaused) return;
      }
      try {
        final result = await channel.launchApp();
        debugPrint('[watch] 워치 앱 켜기 · ${result.name}');
        if (result != WatchLaunchResult.notListening) return;
      } on Object catch (error) {
        debugPrint('[watch] 워치 앱을 켜지 못했다 · $error');
        return;
      }
    }
    _launchGaveUp = true;
  }

  void _stop() {
    _channel = null;
    _relisten?.cancel();
    _ticker?.cancel();
    _visibility?.cancel();
    _detail?.close();
    unawaited(_messages?.cancel());
  }

  static final _random = Random.secure();

  /// 8자리 16진수. 겹치지만 않으면 되는 값이다.
  static String _newId() =>
      _random.nextInt(1 << 32).toRadixString(16).padLeft(8, '0');
}

/// 워치에 알리는 단계. 바뀔 때 `statusVersion` 이 오른다.
enum _Stage {
  none,
  running,
  paused,
  finishing,
  pendingRunning,
  pendingPaused,
  finished,
}

/// 워치 명령을 거절하는 이유. 워치는 `code` 를 읽지 않고 `requestId` 만 보지만,
/// 디코더가 `code`·`message` 를 필수로 읽어 비우면 메시지를 통째로 버린다.
enum _Rejection {
  noRun('NO_RUN', '진행 중인 러닝이 없다'),
  notRunOwner('NOT_RUN_OWNER', '러닝을 시작한 계정이 로그인돼 있지 않다'),
  otherPhoneInstance('OTHER_PHONE_INSTANCE', '폰 앱이 다시 켜졌다'),
  staleStatus('STALE_STATUS', '누른 뒤 러닝 단계가 바뀌었다'),
  otherRoom('OTHER_ROOM', '다른 방의 명령이다');

  const _Rejection(this.code, this.message);

  final String code;
  final String message;
}
