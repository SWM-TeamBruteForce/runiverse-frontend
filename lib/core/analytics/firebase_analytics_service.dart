import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:runiverse/core/analytics/analytics.dart';

/// 진짜로 GA4 에 보내는 [Analytics].
///
/// ## ⚠️ 여기서 실패해도 화면은 모른다
///
/// 네트워크가 끊겼거나 Firebase 초기화가 어긋났을 때 예외가 올라가면, 로그인
/// 성공 직후나 러닝이 끝난 자리에서 앱이 멈춘다. 분석 한 줄 때문에 그럴 수는
/// 없어서 **여기서 삼키고 디버그 로그만 남긴다.**
///
/// ⚠️ 삼키는 대신 **디버그에서는 반드시 찍는다.** 안 찍으면 "DebugView 에 아무것도
/// 안 뜬다"의 원인이 보내지 않은 것인지 보냈는데 실패한 것인지 알 수 없다.
class FirebaseAnalyticsService implements Analytics {
  FirebaseAnalyticsService([FirebaseAnalytics? analytics])
    : _analytics = analytics ?? FirebaseAnalytics.instance;

  final FirebaseAnalytics _analytics;

  @override
  NavigatorObserver newRouteObserver() =>
      FirebaseAnalyticsObserver(analytics: _analytics);

  @override
  Future<void> login({required String method}) =>
      _send('login', {'method': method});

  @override
  Future<void> onboardingComplete() => _send('onboarding_complete', null);

  @override
  Future<void> matchApply({required int distanceMeters}) =>
      _send('match_apply', {'distance_m': distanceMeters});

  @override
  Future<void> matchCancel() => _send('match_cancel', null);

  @override
  Future<void> runStart({required String runType}) =>
      _send('run_start', {'run_type': runType});

  @override
  Future<void> runFinish({required String runType}) =>
      _send('run_finish', {'run_type': runType});

  @override
  Future<void> withdraw() => _send('withdraw', null);

  Future<void> _send(String name, Map<String, Object>? parameters) async {
    try {
      await _analytics.logEvent(name: name, parameters: parameters);
      if (kDebugMode) debugPrint('[ga] $name ${parameters ?? ''}');
    } on Object catch (error) {
      // `on Exception` 으로 좁히지 않는다. 플랫폼 채널은 `Error` 도 던진다 —
      // 초기화 전에 부르면 `LateInitializationError` 가 나는데, 그것은
      // `Exception` 이 아니라 어떤 catch 에도 안 걸리고 화면까지 올라간다.
      if (kDebugMode) debugPrint('[ga] $name 실패: $error');
    }
  }
}
