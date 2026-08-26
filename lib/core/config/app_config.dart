/// 앱이 어느 서버에 붙는가.
///
/// ## 값은 빌드할 때 넣는다. 소스에는 없다
///
/// `--dart-define=API_BASE_URL=...`로 넘긴다. 주소를 소스에 적으면 서버 위치가
/// 저장소에 그대로 남고, 서버가 옮겨갈 때마다 커밋이 하나씩 생긴다.
/// **기본값을 두지 않는 것도 같은 이유다** — 기본값은 결국 소스에 적힌 주소다.
///
/// [String.fromEnvironment]는 `const`라 **컴파일 시점에 값이 박힌다.**
/// 실행 중에 바꿀 수 없고, 값을 바꾸려면 앱을 다시 빌드해야 한다.
/// 핫 리로드로는 안 바뀐다 — 주소를 고쳤는데 그대로면 이걸 먼저 의심한다.
///
/// ## 안 넣고 빌드하면
///
/// [apiBaseUrl]이 빈 문자열이 된다. 이때 [hasApiBaseUrl]이 `false`이므로
/// 네트워크 계층이 그 자리에서 멈춘다. 조용히 엉뚱한 곳으로 요청이 나가는 것보다
/// **바로 실패하는 편이 낫다** — 주소를 빠뜨린 것과 서버가 죽은 것은
/// 증상이 같아 보여서, 구분되지 않으면 엉뚱한 데를 뒤지게 된다.
class AppConfig {
  const AppConfig._();

  /// 스킴과 호스트까지만. 경로(`/api/...`)는 부르는 쪽이 갖는다.
  ///
  /// 버전 접두사를 여기 붙이지 않는 이유는, 그래야 호출부에서 전체 경로가
  /// 한눈에 보이기 때문이다.
  static const apiBaseUrl = String.fromEnvironment('API_BASE_URL');

  /// 주소가 주입됐는가.
  static bool get hasApiBaseUrl => apiBaseUrl.isNotEmpty;

  /// 카카오 네이티브 앱 키.
  ///
  /// 앱 바이너리에 박히는 값이라 시크릿은 아니지만, 주소와 같은 이유로 소스에
  /// 적지 않는다 — 앱이 바뀔 때마다 커밋이 하나씩 생긴다.
  ///
  /// ⚠️ **REST API 키와 다른 값이다.** REST API 키와 Client Secret은 서버가
  /// 카카오와 토큰을 교환할 때 쓰고, **앱에는 들어가지 않는다.**
  ///
  /// ⚠️ **안드로이드 매니페스트에도 같은 값이 필요하다.** 리다이렉트 스킴이
  /// `kakao<앱키>`라서인데, 매니페스트는 `--dart-define`을 읽지 못한다.
  /// Gradle 프로퍼티(`-PKAKAO_NATIVE_APP_KEY=...`)로 따로 넘긴다.
  static const kakaoNativeAppKey = String.fromEnvironment(
    'KAKAO_NATIVE_APP_KEY',
  );

  /// 카카오 로그인을 걸어도 되는가.
  ///
  /// 키가 없으면 SDK를 초기화하지 않는다 — 빈 키로 초기화하면 버튼을 눌렀을 때
  /// 원인을 알기 어려운 오류가 난다.
  static bool get hasKakaoNativeAppKey => kakaoNativeAppKey.isNotEmpty;

  /// 네이버 지도 Client ID.
  ///
  /// 네이버 클라우드 콘솔 > Maps > Dynamic Map에서 발급한다. 앱 패키지명으로
  /// 묶여 있어 다른 앱이 훔쳐 써도 인증이 통과하지 않지만, **그래도 코드에
  /// 적지 않는다** — 저장소가 공개되면 사용량이 남의 손에 들어간다.
  static const naverMapClientId = String.fromEnvironment('NAVER_MAP_CLIENT_ID');

  /// 지도를 띄워도 되는가.
  ///
  /// ⚠️ 키가 없으면 SDK를 초기화하지 않는다. 빈 키로 초기화하면 인증 실패
  /// 콜백이 돌고, 그 뒤 지도를 그리려 하면 앱이 통째로 죽는다 —
  /// 카카오에서 겪은 것과 같은 함정이다.
  static bool get hasNaverMapClientId => naverMapClientId.isNotEmpty;

  /// WebSocket 주소. [apiBaseUrl]에서 파생한다.
  ///
  /// 주소를 따로 주입하지 않는 이유는 **둘이 어긋날 자리를 만들지 않기
  /// 위해서**다. 서버를 옮겼는데 한쪽만 고치면, REST는 새 서버로 가고 WS는
  /// 옛 서버로 가는 상태가 된다 — 증상이 "러닝만 안 된다"로 나타나서
  /// 원인을 찾기 어렵다.
  ///
  /// `http` → `ws`, `https` → `wss`로 바꾼다. 스킴만 바뀌고 호스트·포트·경로는
  /// 그대로다.
  ///
  /// ⚠️ **서버가 WS를 다른 호스트나 포트로 분리하면 이 파생은 깨진다.**
  /// 그때는 주입값을 하나 더 두어야 한다.
  static String get wsBaseUrl {
    if (apiBaseUrl.startsWith('https://')) {
      return apiBaseUrl.replaceFirst('https://', 'wss://');
    }
    if (apiBaseUrl.startsWith('http://')) {
      return apiBaseUrl.replaceFirst('http://', 'ws://');
    }
    // 스킴을 모르면 손대지 않는다. 어차피 [hasApiBaseUrl]이 먼저 막는다.
    return apiBaseUrl;
  }
}
