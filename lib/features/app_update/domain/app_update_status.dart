import 'package:runiverse/core/version/app_version.dart';

/// 지금 앱으로 계속 써도 되는가.
enum AppUpdateStatus {
  /// 최신이다. 아무것도 띄우지 않는다.
  current,

  /// 쓸 수는 있는데 새 버전이 나와 있다. **닫을 수 있는 안내**다.
  recommended,

  /// 최소 버전에 못 미친다. **닫을 수 없는 화면**이고 스토어로만 보낸다.
  ///
  /// 이 상태에서는 서버가 `/app/version`을 뺀 모든 요청을
  /// `403 APP_UPDATE_REQUIRED`로 거절한다.
  required;

  bool get blocks => this == AppUpdateStatus.required;
}

/// 서버가 내려준 플랫폼별 버전 기준.
///
/// ## 판정은 앱이 한다
///
/// 서버는 두 값만 주고 "업데이트가 필요한가"는 말하지 않는다. 앱이 자기 버전과
/// 견줘 정한다 — 그래야 같은 응답으로 세 경우를 다 가를 수 있다.
class AppVersionPolicy {
  const AppVersionPolicy({required this.minimum, required this.latest});

  /// 이 버전보다 낮으면 쓸 수 없다.
  final AppVersion minimum;

  /// 스토어에 올라간 최신 버전. [minimum] 이상이다.
  final AppVersion latest;

  /// [installed]로 계속 써도 되는가.
  ///
  /// ⚠️ **설치 버전을 못 읽었으면(`null`) 막지 않는다.** 값을 못 읽은 것과
  /// 낡은 것은 다르다. 모르는 것을 "낡았다"로 판정하면, 버전을 못 읽는 기기의
  /// 사용자가 **업데이트를 해도 풀리지 않는 화면**에 갇힌다. 서버가 헤더를
  /// 못 읽었을 때 그냥 통과시키는 것과 같은 판단이다(공통 규칙).
  AppUpdateStatus statusFor(AppVersion? installed) {
    if (installed == null) return AppUpdateStatus.current;
    if (installed < minimum) return AppUpdateStatus.required;
    if (installed < latest) return AppUpdateStatus.recommended;
    return AppUpdateStatus.current;
  }

  /// 몸통에서 읽는다. **두 값이 다 있어야 한다** — 하나라도 없으면 `null`이다.
  ///
  /// 한쪽만 읽어 판정하면 기준이 반쪽이라, 막아야 할 앱을 통과시키거나
  /// 멀쩡한 앱을 막는다.
  static AppVersionPolicy? of(Map<String, dynamic>? body) {
    final minimum = AppVersion.parse(body?['minimumVersion'] as String?);
    final latest = AppVersion.parse(body?['latestVersion'] as String?);
    if (minimum == null || latest == null) return null;
    return AppVersionPolicy(minimum: minimum, latest: latest);
  }
}
