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
/// 잡히지 않는다. [screenView] 를 **라우터가 바뀔 때마다** 부른다.
///
/// ## ⚠️ `FirebaseAnalyticsObserver` 를 쓰지 않는다
///
/// 기기에서 확인하고 버린 길이다. 관찰자를 라우터와 탭 브랜치 넷에 꽂았더니
/// 이 화면 구성에서 두 가지가 어긋났다.
///
/// | | 무슨 일이 났나 |
/// |---|---|
/// | 탭 **재방문** | 아무것도 안 찍힌다 |
/// | 탭 **첫 방문** | 두 번 찍힌다 |
///
/// `StatefulShellRoute.indexedStack` 은 탭을 바꿔도 라우트를 밀어 넣지 않는다 —
/// 네 [Navigator] 를 쌓아 두고 보여줄 것만 바꾸므로 관찰자가 불리지 않는다.
/// 첫 방문이 두 번인 것은 루트와 브랜치 관찰자가 **같은 화면을 각자 적어서**다.
///
/// 라우터 변화를 직접 들으면 둘 다 없어진다. 시트·다이얼로그가 주소를 바꾸지
/// 않는 것도 이쪽에 유리하다 — 열고 닫아도 군더더기 이벤트가 생기지 않는다.
///
/// ## 실패를 밖으로 흘리지 않는다
///
/// 분석은 곁다리다. 로그를 못 남겼다고 로그인이나 러닝이 멈추면 안 된다 —
/// 구현체가 예외를 안에서 삼킨다.
abstract interface class Analytics {
  /// 화면 하나를 봤다. [name] 은 `GoRoute` 에 붙인 이름이다.
  Future<void> screenView({required String name});

  /// 로그인 성공. [method] 는 `email` · `kakao` · `google`.
  Future<void> login({required String method});

  /// 프로필 설정 저장 성공. **가입 완료로 센다.**
  Future<void> onboardingComplete();

  /// 매칭 신청 성공. [distanceMeters] 는 3000 · 5000 · 10000.
  Future<void> matchApply({required int distanceMeters});

  /// 방이 **확정됐다** — 사람이 모여 같이 뛸 수 있게 된 순간.
  ///
  /// ## ⚠️ 이 한 칸이 없으면 못 가르는 것
  ///
  /// [matchApply] 다음이 바로 [runStart] 면, 신청하고 못 뛴 사람이
  /// **사람이 안 모여 성사가 안 된 것**인지 **성사됐는데 안 나타난 것**인지
  /// 알 수 없다. 앞은 매칭 풀·시간대 설계 문제고 뒤는 이탈 문제다 —
  /// 고칠 곳이 완전히 다르다.
  ///
  /// [distanceMeters] 는 모르면 `null` 이다. [matchApply] 와 같은 이름의
  /// 파라미터로 나가므로 거리별 성사율을 바로 견줄 수 있다.
  Future<void> matchConfirmed({int? distanceMeters});

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
  Future<void> screenView({required String name}) async {}

  @override
  Future<void> login({required String method}) async {}

  @override
  Future<void> onboardingComplete() async {}

  @override
  Future<void> matchApply({required int distanceMeters}) async {}

  @override
  Future<void> matchConfirmed({int? distanceMeters}) async {}

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
