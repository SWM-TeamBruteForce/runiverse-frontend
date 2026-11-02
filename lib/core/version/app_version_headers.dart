import 'dart:io' show Platform;

import 'package:runiverse/core/version/installed_app_version.dart';

/// 서버로 가는 모든 요청에 싣는 앱 버전 헤더.
///
/// ## 세 곳이 같은 값을 써야 한다
///
/// REST(`createDio`)·SSE(`SseMatchStream`)·WebSocket(`WsClient`) 셋 다 싣는다
/// (공통 규칙). 한 곳이라도 빠지면 그 경로는 **모든 앱에서 403으로 막힌다.**
/// 값을 만드는 자리를 하나로 둔다.
///
/// ⚠️ **S3 직접 업로드에는 싣지 않는다.** 우리 서버가 아니다 — 서명된 URL에
/// 모르는 헤더를 더하면 서명이 어긋난다(작업 가이드도 빼라고 적었다).
///
/// ## 못 읽으면 아예 안 싣는다
///
/// 서버는 **헤더가 없거나 형식이 틀리면 403 `APP_UPDATE_REQUIRED`로 거절한다**
/// (버전 확인 API는 뺀다). `0.0.0` 같은 것을 지어내도 최소 버전 미만이라
/// 똑같이 막히니, 모르는 값은 지어내지 않고 비운다. 릴리스 빌드는 `pubspec`의
/// `x.y.z`를 그대로 읽어 못 읽는 경로가 없다.
abstract final class AppVersionHeaders {
  const AppVersionHeaders._();

  static const versionKey = 'X-App-Version';
  static const platformKey = 'X-App-Platform';

  /// 서버가 받는 값은 `IOS` / `ANDROID` 둘뿐이다.
  static String get platform => Platform.isIOS ? 'IOS' : 'ANDROID';

  /// 지금 실어야 할 헤더. **버전을 못 읽었으면 빈 맵이다.**
  ///
  /// 두 헤더는 **함께** 나가거나 함께 빠진다. 서버는 하나만 있어도 없는 것과
  /// 같이 403으로 거절한다.
  static Map<String, String> get current {
    final version = InstalledAppVersion.current;
    if (version == null) return const {};
    return {versionKey: version.toString(), platformKey: platform};
  }
}
