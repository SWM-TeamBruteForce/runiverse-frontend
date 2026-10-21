import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:runiverse/core/version/app_version.dart';

/// 설치된 앱의 버전 이름을 읽는다.
///
/// ## 왜 `core`에 있나
///
/// `X-App-Version` 헤더를 다는 곳이 셋인데(REST·SSE·WebSocket) 전부 `core`다.
/// feature 쪽에 두면 `core → features` 방향이 생겨 의존이 뒤집힌다
/// (`TokenStore`와 같은 판단).
///
/// ## ⚠️ `pubspec`의 값을 상수로 박지 않는다
///
/// 서버가 이 값으로 구버전을 막는다. 상수로 박아 두면 **릴리스 때 올리는 것을
/// 잊은 순간** 실제 설치본과 어긋나고, 그러면 업데이트를 한 사람에게도
/// 업데이트하라는 화면이 뜬다. 설치본에서 직접 읽으면 어긋날 자리가 없다.
abstract final class InstalledAppVersion {
  /// 한 번 읽어 들고 있는다. 앱이 도는 동안 바뀌지 않는 값이다.
  static AppVersion? _cached;

  /// 읽어 본 적이 있는가. 실패한 것과 아직 안 읽은 것을 가른다.
  static var _loaded = false;

  /// 지금 설치된 버전. **못 읽으면 `null`이다.**
  ///
  /// ⚠️ **`null`을 `0.0.0`으로 눌러선 안 된다.** 그 값은 어떤 최소 버전에도
  /// 못 미쳐서, 못 읽었을 뿐인 사용자를 영영 업데이트 화면에 가둔다.
  static AppVersion? get current => _cached;

  /// 플랫폼 채널에서 읽어 온다. 앱이 서기 전에 한 번 부른다.
  ///
  /// ⚠️ **실패해도 던지지 않는다.** 버전을 못 읽는 것은 앱을 못 쓸 이유가
  /// 아니다. 헤더를 안 싣고 판정도 하지 않을 뿐이다 — 서버도 헤더가 없으면
  /// 그냥 통과시킨다(공통 규칙).
  static Future<AppVersion?> load() async {
    if (_loaded) return _cached;
    _loaded = true;

    try {
      final info = await PackageInfo.fromPlatform();
      _cached = AppVersion.parse(info.version);
      if (_cached == null) {
        debugPrint('[version] 버전 이름을 읽지 못했다 · "${info.version}"');
      }
    } on Object catch (error) {
      // 테스트 환경에는 플랫폼 채널이 없다. 거기서 죽으면 앱 전체가 안 선다.
      debugPrint('[version] 설치 버전을 못 읽었다 · ${error.runtimeType}');
    }
    return _cached;
  }

  /// 테스트가 값을 세운다. **프로덕션에서는 부르지 않는다.**
  @visibleForTesting
  static void setForTest(AppVersion? version) {
    _cached = version;
    _loaded = true;
  }

  /// 테스트가 되돌린다. 남기면 뒤따르는 테스트가 엉뚱한 버전에서 돈다.
  @visibleForTesting
  static void resetForTest() {
    _cached = null;
    _loaded = false;
  }
}
