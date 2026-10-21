import 'dart:io' show Platform;

/// 스토어 주소. 업데이트 화면의 버튼이 여기로 보낸다.
///
/// ## 서버가 주지 않는다
///
/// 버전 확인 API(`/app/version`)는 최소·최신 **버전만** 내려준다. 주소는
/// 바뀌지 않는 값이라 앱이 들고 있기로 한 것이다(명세가 못 박았다).
///
/// ## ⚠️ dev 빌드에서도 **운영 스토어**로 보낸다
///
/// dev flavor의 패키지는 `com.runiverse.app.dev`지만 **스토어에는 그것이
/// 없다.** dev 패키지로 링크를 만들면 "앱을 찾을 수 없음"이 뜬다. 업데이트를
/// 받을 곳은 어느 빌드에서나 운영 스토어 하나뿐이다.
///
/// [LegalLinks]와 같은 이유로 `AppConfig`에 두지 않는다 — 시크릿이 아니고
/// 빌드마다 달라지지도 않는다.
abstract final class StoreLinks {
  const StoreLinks._();

  static const ios = 'https://apps.apple.com/app/id6823043744';

  static const android =
      'https://play.google.com/store/apps/details?id=com.runiverse.app';

  /// 지금 기기에 맞는 주소.
  ///
  /// ⚠️ 데스크톱·웹 빌드는 범위에 없다. 테스트는 호스트(Windows)에서 돌아
  /// `Platform.isIOS`가 늘 `false`이므로 기본은 플레이 스토어다.
  static String get current => Platform.isIOS ? ios : android;
}
