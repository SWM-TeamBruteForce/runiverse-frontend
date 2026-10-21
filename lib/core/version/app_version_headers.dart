import 'dart:io' show Platform;

import 'package:runiverse/core/version/installed_app_version.dart';

/// 서버로 가는 모든 요청에 싣는 앱 버전 헤더.
///
/// ## 세 곳이 같은 값을 써야 한다
///
/// REST(`createDio`)·SSE(`SseMatchStream`)·WebSocket(`WsClient`) 셋 다 싣는다
/// (공통 규칙). 한 곳이라도 빠지면 그 경로만 검사를 안 받아, **구버전 앱이
/// 반쯤 도는** 상태가 된다. 값을 만드는 자리를 하나로 둔다.
///
/// ⚠️ **S3 직접 업로드에는 싣지 않는다.** 우리 서버가 아니다 — 서명된 URL에
/// 모르는 헤더를 더하면 서명이 어긋난다(작업 가이드도 빼라고 적었다).
///
/// ## 못 읽으면 아예 안 싣는다
///
/// 서버는 **헤더가 없거나 형식이 틀리면 거절하지 않고 그대로 처리한다**
/// (공통 규칙). 그래서 값을 못 읽었을 때 `0.0.0` 같은 것을 지어내면 안 된다 —
/// 통과했을 요청이 403으로 막힌다. 모르면 비우는 쪽이 안전하다.
abstract final class AppVersionHeaders {
  const AppVersionHeaders._();

  static const versionKey = 'X-App-Version';
  static const platformKey = 'X-App-Platform';

  /// 서버가 받는 값은 `IOS` / `ANDROID` 둘뿐이다.
  static String get platform => Platform.isIOS ? 'IOS' : 'ANDROID';

  /// 지금 실어야 할 헤더. **버전을 못 읽었으면 빈 맵이다.**
  ///
  /// 두 헤더는 **함께** 나가거나 함께 빠진다. 서버는 하나만 있어도 검사하지
  /// 않지만, 반쪽만 보내면 로그에서 "왜 검사가 안 되나"를 쫓게 된다.
  static Map<String, String> get current {
    final version = InstalledAppVersion.current;
    if (version == null) return const {};
    return {versionKey: version.toString(), platformKey: platform};
  }
}
