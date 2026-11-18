import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:runiverse/features/home/domain/home_notice.dart';

/// 홈 공지 두 자리가 보는 값.
///
/// 둘 다 `null`이면 **그 자리를 내린다** — 아직 안 왔거나, 90초 동안 새 값이
/// 없었다.
class HomeNoticeState {
  const HomeNoticeState({this.waitingCount, this.activity});

  /// 매칭 버튼 위 `오늘 N명 대기`.
  final int? waitingCount;

  /// 공지 띠.
  final HomeActivity? activity;
}

/// 앱 스트림의 홈 공지를 들고 있는다.
///
/// ## ⚠️ 받는 곳은 앱 스트림이다
///
/// 이 provider는 연결을 열지 않는다. 알림이 쓰는 연결로 같이 오고,
/// `NotificationController`가 받아서 여기로 넘긴다 — 같은 계정이 연결을 둘
/// 열면 서로를 밀어낸다. 이쪽은 그 provider를 듣지 않는다(서로 들으면
/// Riverpod이 순환으로 막는다).
final homeNoticeProvider =
    NotifierProvider<HomeNoticeController, HomeNoticeState>(
      HomeNoticeController.new,
    );

class HomeNoticeController extends Notifier<HomeNoticeState> {
  /// 이만큼 새 값이 없으면 그 자리를 내린다.
  ///
  /// 서버가 대기는 10초, 띠는 30초마다 보낸다. 서버가 멈췄을 때 낡은 숫자를
  /// 계속 세워 두지 않으려는 것이다. **서버 시각 필드는 없다** — 폰 시계와
  /// 비교하면 틀리므로 받은 때부터 센다.
  static const expiry = Duration(seconds: 90);

  /// ⚠️ **이벤트마다 따로 센다.** 대기 값이 10초마다 와도 띠 값이 끊겼으면
  /// 띠는 내려야 한다.
  Timer? _waitingExpiry;
  Timer? _activityExpiry;

  @override
  HomeNoticeState build() {
    ref.onDispose(_cancel);
    return const HomeNoticeState();
  }

  void receiveWaiting(int count) {
    _waitingExpiry?.cancel();
    _waitingExpiry = Timer(expiry, () {
      state = HomeNoticeState(activity: state.activity);
    });
    state = HomeNoticeState(waitingCount: count, activity: state.activity);
  }

  void receiveActivity(HomeActivity activity) {
    _activityExpiry?.cancel();
    _activityExpiry = Timer(expiry, () {
      state = HomeNoticeState(waitingCount: state.waitingCount);
    });
    state = HomeNoticeState(
      waitingCount: state.waitingCount,
      activity: activity,
    );
  }

  /// 로그아웃. 연결이 끊기므로 들고 있던 값도 내린다 — 90초를 기다리지 않는다.
  void clear() {
    _cancel();
    state = const HomeNoticeState();
  }

  void _cancel() {
    _waitingExpiry?.cancel();
    _activityExpiry?.cancel();
  }
}
