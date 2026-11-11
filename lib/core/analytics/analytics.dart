import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 사용자 행동을 남긴다 — 앱에서의 GA4(Firebase Analytics).
///
/// 보려는 것은 **가입부터 매칭·러닝까지 어디서 멈추는가**다. Firebase 는
/// 안드로이드에서 광고 식별자를 읽지 않는다(`adid_collection` 을 껐다). iOS 는
/// 추적을 허용하면 읽는다. 광고 식별자는 Meta SDK 가 따로 모은다
/// (`AndroidManifest.xml` 주석).
///
/// ## ⚠️ 버튼을 누른 때가 아니라 **성공한 때** 남긴다
///
/// 탭으로 세면 실패한 시도까지 섞여 전환율이 부풀려진다. 그래서 이 인터페이스의
/// 성공 기록은 전부 **결과가 확정된 자리**에서 불린다.
///
/// ## 누름·단계 기록은 이름을 따로 둔다
///
/// 어디서 멈추는지 보려면 누른 순간도 있어야 한다. 그 기록은 성공 기록과
/// 이름을 따로 둔다(`login_attempt`와 `login`). 섞이지 않으니 성공 수는 부풀지
/// 않는다.
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

  /// 로그인 성공. [method] 는 `email` · `kakao` · `google` · `apple`.
  ///
  /// `SignInMethod.name`을 그대로 쓴다. 제공자가 늘면 값도 따라 늘어난다 —
  /// 대시보드의 분류를 손봐야 한다는 뜻이다.
  Future<void> login({required String method});

  /// 로그인을 **시작했다.** [method] 는 [login] 과 같은 값이다.
  ///
  /// 성공이 아니라 시도다 — 제공자 창에서 취소하거나 비밀번호가 틀려도 남는다.
  /// [login] 과 견주면 버튼을 누르고도 못 들어간 사람이 보인다. 이메일 가입도
  /// [login] 을 남기므로 가입 버튼도 여기서 센다 — 빼면 이메일만 성공이 시도보다
  /// 많아진다.
  Future<void> loginAttempt({required String method});

  /// 프로필 설정 저장 성공. **가입 완료로 센다.**
  Future<void> onboardingComplete();

  /// 매칭 등록 화면에서 거리 칩을 눌렀다. [distanceMeters] 는 [matchApply] 와
  /// 같은 이름으로 나간다.
  Future<void> matchDistanceSelect({required int distanceMeters});

  /// 시간 칸을 눌러 시간 시트를 열었다. 시트는 주소를 바꾸지 않아
  /// [screenView] 가 남지 않는다.
  Future<void> matchSlotSheetOpen();

  /// 시간 시트에서 시각을 골랐다.
  Future<void> matchSlotSelect();

  /// 매칭 신청 성공. [distanceMeters] 는 3000 · 5000 · 10000.
  ///
  /// [otherDistanceWaiting] 은 신청한 순간 **다른 거리**의 아직 열린 칸에
  /// 신청해 둔 사람의 합, [otherDistanceWaitingSameTime] 은 그중 신청한 시각의
  /// 수다. 거리를 합쳤다면 만났을 사람이 얼마나 되는지 — 거리 슬롯을 줄일지
  /// 가린다. 누른 순간 화면이 들고 있던 판의 값이다. 시트는 고른 거리만
  /// 그려서, 다른 거리의 숫자는 그 사람이 못 봤을 수 있다.
  Future<void> matchApply({
    required int distanceMeters,
    required int otherDistanceWaiting,
    required int otherDistanceWaitingSameTime,
  });

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
  ///
  /// [early] 는 **본인이 목표 전에 끝내기로 했는가**(`forced=true`)다. 서버가
  /// 그 시점 거리로 완주 처리할 수도 있어서 "완주 못 함"과 같은 뜻은 아니다.
  /// 서버가 끝낸 경우는 `false` 다.
  Future<void> runFinish({required String runType, required bool early});

  /// 탈퇴 성공.
  Future<void> withdraw();

  /// 권한을 확인한 결과.
  ///
  /// [permission] 은 `location` · `activity` · `notification` · `tracking`(iOS
  /// 추적 허용), [result] 는 `granted` · `denied` · `denied_forever` ·
  /// `service_disabled`(위치만). [askedFrom] 은 물은 자리다 — 러닝 준비는
  /// `run`, 홈은 `home`, 앱을 켤 때는 `launch`(추적 허용).
  ///
  /// 러닝 준비·홈 알림·추적 허용은 이미 허용돼 창이 안 떴어도 남긴다 — 홈 알림과
  /// 추적 허용은 앱을 켤 때마다다. 홈의 위치·신체 활동은 그 기기에 처음 물을
  /// 때만 남고, 위치는 묻기 전이 `denied`(물을 수 있음)일 때만 남는다.
  ///
  /// `tracking` 의 `denied` 는 사용자가 거절한 것이 아니다 — 창이 안 떴거나
  /// 기기가 막아 둔 경우(보호자 통제 등)다. 거절하면 `denied_forever` 로 온다.
  ///
  /// ⚠️ `notification` 은 `granted` 인지만 믿는다. 안드로이드는 홈(FCM)과 러닝
  /// 준비(permission_handler)가 거절 이력을 따로 기억해, 같은 기기가 자리마다
  /// `denied` · `denied_forever` 로 갈릴 수 있다. 안드로이드 12 이하는 묻는
  /// 창이 없어, 설정에서 알림을 끈 기기도 두 자리 다 `denied` 다.
  ///
  /// ⚠️ 이 값을 더하기 전 앱은 빼고 보냈다. 비어 있으면 러닝 준비다.
  Future<void> permissionResult({
    required String permission,
    required String result,
    required String askedFrom,
  });

  /// 이후 기록에 회원 ID 를 붙인다. 로그아웃·탈퇴하면 `null` 로 뗀다.
  ///
  /// 이벤트가 아니라 **이벤트에 붙는 표식**이다. GA 와 Crashlytics 에 같은
  /// 값을 건다 — 오류를 겪은 회원의 이용 흐름을 이어 보려고.
  Future<void> setUserId(String? userId);
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
  Future<void> loginAttempt({required String method}) async {}

  @override
  Future<void> onboardingComplete() async {}

  @override
  Future<void> matchDistanceSelect({required int distanceMeters}) async {}

  @override
  Future<void> matchSlotSheetOpen() async {}

  @override
  Future<void> matchSlotSelect() async {}

  @override
  Future<void> matchApply({
    required int distanceMeters,
    required int otherDistanceWaiting,
    required int otherDistanceWaitingSameTime,
  }) async {}

  @override
  Future<void> matchConfirmed({int? distanceMeters}) async {}

  @override
  Future<void> matchCancel() async {}

  @override
  Future<void> runStart({required String runType}) async {}

  @override
  Future<void> runFinish({
    required String runType,
    required bool early,
  }) async {}

  @override
  Future<void> withdraw() async {}

  @override
  Future<void> permissionResult({
    required String permission,
    required String result,
    required String askedFrom,
  }) async {}

  @override
  Future<void> setUserId(String? userId) async {}
}

/// 화면과 provider 가 보는 것.
///
/// 기본은 [NoopAnalytics] 다. 진짜는 `main.dart` 가 끼운다 — 위 설명 참조.
final analyticsProvider = Provider<Analytics>((ref) => const NoopAnalytics());
