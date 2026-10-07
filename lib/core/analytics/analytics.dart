import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 사용자 행동을 남긴다 — 앱에서의 GA4(Firebase Analytics).
///
/// 보려는 것은 **가입부터 매칭·러닝까지 어디서 멈추는가**다. 광고 식별자는
/// 수집하지 않는다(매니페스트에서 권한 셋을 빼고 `adid_collection` 을 껐다).
///
/// ## ⚠️ 버튼을 누른 때가 아니라 **성공한 때** 남긴다
///
/// 탭으로 세면 실패한 시도까지 섞여 전환율이 부풀려진다. 그래서 이 인터페이스의
/// 메서드는 전부 **결과가 확정된 자리**에서 불린다.
///
/// ## 화면은 왜 따로 잡아야 하나
///
/// Flutter 앱은 안드로이드 화면(Activity)이 하나뿐이라 화면 이동이 자동으로
/// 잡히지 않는다. [newRouteObserver] 를 라우터와 각 탭 브랜치에 꽂아 대신 잡는다.
///
/// ## 실패를 밖으로 흘리지 않는다
///
/// 분석은 곁다리다. 로그를 못 남겼다고 로그인이나 러닝이 멈추면 안 된다 —
/// 구현체가 예외를 안에서 삼킨다.
abstract interface class Analytics {
  /// 화면 이동을 잡는 관찰자.
  ///
  /// ⚠️ **부를 때마다 새로 만든다.** [NavigatorObserver] 는 자기가 붙은
  /// [NavigatorState] 를 하나만 들고 있어서, 같은 인스턴스를 라우터와 탭
  /// 브랜치에 겹쳐 꽂으면 나중에 붙은 쪽만 살아남는다. 탭 넷이 각자
  /// [Navigator] 를 갖는 `StatefulShellRoute` 에서는 그대로 구멍이 된다.
  NavigatorObserver newRouteObserver();

  /// 로그인 성공. [method] 는 `email` · `kakao` · `google`.
  Future<void> login({required String method});

  /// 프로필 설정 저장 성공. **가입 완료로 센다.**
  Future<void> onboardingComplete();

  /// 매칭 신청 성공. [distanceMeters] 는 3000 · 5000 · 10000.
  Future<void> matchApply({required int distanceMeters});

  /// 매칭 취소 성공.
  Future<void> matchCancel();

  /// `RUNNING_STARTED` 를 처음 받았을 때. [runType] 은 `match` · `solo`.
  Future<void> runStart({required String runType});

  /// `RUNNING_FINISHED` 를 처음 받았을 때. [runType] 은 `match` · `solo`.
  Future<void> runFinish({required String runType});

  /// 탈퇴 성공.
  Future<void> withdraw();
}

/// 아무 데도 보내지 않는 구현. **이것이 기본값이다.**
///
/// ## 왜 진짜가 기본이 아닌가
///
/// 위젯 테스트에는 플랫폼 채널이 없어서 Firebase 를 건드리는 순간 죽는다.
/// 기본을 진짜로 두면 `RuniverseApp` 을 띄우는 테스트 열두 개가 전부
/// override 를 달아야 하고, 하나라도 빠뜨리면 그 테스트만 알 수 없는 이유로
/// 깨진다.
///
/// 그래서 **조립하는 자리(`main.dart`)에서만** 진짜를 끼운다. 분석은 곁다리라
/// 빠져도 앱이 돌아가야 한다는 성격과도 맞는다.
///
/// ⚠️ 뒤집어 말하면 `main.dart` 의 override 가 빠지면 **조용히 아무것도 남지
/// 않는다.** 그 줄을 지우지 않도록 주석을 달아 두었다.
class NoopAnalytics implements Analytics {
  const NoopAnalytics();

  @override
  NavigatorObserver newRouteObserver() => NavigatorObserver();

  @override
  Future<void> login({required String method}) async {}

  @override
  Future<void> onboardingComplete() async {}

  @override
  Future<void> matchApply({required int distanceMeters}) async {}

  @override
  Future<void> matchCancel() async {}

  @override
  Future<void> runStart({required String runType}) async {}

  @override
  Future<void> runFinish({required String runType}) async {}

  @override
  Future<void> withdraw() async {}
}

/// 화면과 provider 가 보는 것.
///
/// 기본은 [NoopAnalytics] 다. 진짜는 `main.dart` 가 끼운다 — 위 설명 참조.
final analyticsProvider = Provider<Analytics>((ref) => const NoopAnalytics());
