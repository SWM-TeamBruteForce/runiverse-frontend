import 'package:runiverse/core/analytics/analytics.dart';

/// 무엇이 몇 번 남았는지 적어 두는 [Analytics]. 테스트가 쓴다.
///
/// 이벤트는 **성공한 자리에서만** 남아야 한다. 그 규칙은 눈으로 볼 수 없어서
/// — 화면도 서버 요청도 달라지지 않는다 — 적어 두고 세는 수밖에 없다.
class FakeAnalytics implements Analytics {
  /// 남은 이벤트를 **순서대로** 담는다. `('login', {'method': 'kakao'})` 꼴이다.
  ///
  /// 순서까지 보는 이유는 "두 번 남는다"를 잡기 위해서다 — 개수만 보면
  /// 재연결마다 `run_start` 가 쌓이는 것을 놓친다.
  final List<(String, Map<String, Object>?)> events = [];

  /// [name] 이 남은 횟수.
  int countOf(String name) => events.where((e) => e.$1 == name).length;

  /// [name] 이 마지막으로 남을 때 실린 파라미터.
  Map<String, Object>? paramsOf(String name) =>
      events.lastWhere((e) => e.$1 == name, orElse: () => (name, null)).$2;

  @override
  Future<void> screenView({required String name}) async =>
      events.add(('screen_view', {'name': name}));

  @override
  Future<void> login({required String method}) async =>
      events.add(('login', {'method': method}));

  @override
  Future<void> onboardingComplete() async =>
      events.add(('onboarding_complete', null));

  @override
  Future<void> matchApply({required int distanceMeters}) async =>
      events.add(('match_apply', {'distance_m': distanceMeters}));

  @override
  Future<void> matchConfirmed({int? distanceMeters}) async => events.add((
    'match_confirmed',
    distanceMeters == null ? null : {'distance_m': distanceMeters},
  ));

  @override
  Future<void> matchCancel() async => events.add(('match_cancel', null));

  @override
  Future<void> runStart({required String runType}) async =>
      events.add(('run_start', {'run_type': runType}));

  @override
  Future<void> runFinish({
    required String runType,
    required bool early,
  }) async => events.add((
    'run_finish',
    // 진짜와 같은 모양으로 적는다. GA 에는 문자열로 나간다.
    {'run_type': runType, 'early': early.toString()},
  ));

  @override
  Future<void> withdraw() async => events.add(('withdraw', null));

  @override
  Future<void> permissionResult({
    required String permission,
    required String result,
  }) async => events.add((
    'permission_result',
    {'permission': permission, 'result': result},
  ));

  /// 회원 ID 를 건 순서. [events] 와 따로 둔다 — 이벤트가 아니라서 섞으면
  /// "아무것도 안 남았다"를 보는 테스트가 깨진다.
  final List<String?> userIds = [];

  @override
  Future<void> setUserId(String? userId) async => userIds.add(userId);
}
