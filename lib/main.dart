import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_naver_map/flutter_naver_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kakao_flutter_sdk/kakao_flutter_sdk.dart';
import 'package:runiverse/app/app.dart';
import 'package:runiverse/core/config/app_config.dart';

/// 앱 진입점. Riverpod 스코프를 열고, 앱 루트를 띄운다.
///
/// [ProviderScope]는 provider가 값을 보관하는 그릇이다.
///
/// ## SDK 둘은 `runApp` 전에 초기화한다
///
/// 로그인 화면이 뜨자마자 눌릴 수 있어서, 그 전에 준비돼 있어야 한다.
/// 플랫폼 채널을 부르므로 [WidgetsFlutterBinding.ensureInitialized]가 먼저다.
///
/// **둘 다 키가 없으면 건너뛴다.** 없는 키로 초기화하면 그 기능만 못 쓰는 게
/// 아니라 앱이 통째로 죽는다.
///
/// ## ⚠️ 릴리스에서는 건너뛰지 않고 멈춘다
///
/// 개발 중에 키가 없는 것은 흔한 일이고, 그때는 그 기능만 빠진 채 나머지를
/// 돌리는 편이 낫다. **배포본에 키가 빠진 것은 사고다** — 조용히 넘어가면
/// 지도가 안 뜨는 앱이 스토어에 올라가고, 원인은 사용자 리뷰로 알게 된다.
/// 기동하자마자 멈춰서 빌드 파이프라인이 잡게 한다.
void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 키가 없으면 초기화하지 않는다. 빈 키로 초기화하면 SDK가 `kakao://oauth`를
  // 리다이렉트 주소로 삼고, 카카오 버튼을 눌렀을 때 원인을 알기 어려운 오류가
  // 난다 — **아예 초기화하지 않는 편이 낫다.**
  //
  // 키가 없어도 앱은 돌아간다. 카카오 로그인만 쓸 수 없다.
  _requireInRelease(AppConfig.hasKakaoNativeAppKey, 'KAKAO_NATIVE_APP_KEY');
  if (AppConfig.hasKakaoNativeAppKey) {
    await KakaoSdk.init(nativeAppKey: AppConfig.kakaoNativeAppKey);
  }

  // 지도도 같은 규칙이다. 키가 없으면 러닝 화면이 지도 자리에 안내를 그리고,
  // 시간·거리·페이스는 그대로 돈다.
  _requireInRelease(AppConfig.hasNaverMapClientId, 'NAVER_MAP_CLIENT_ID');
  if (AppConfig.hasNaverMapClientId) {
    await FlutterNaverMap().init(
      clientId: AppConfig.naverMapClientId,
      // ⚠️ 삼키지 않는다. 인증이 실패하면 지도만 빈 화면이 되는데, 로그가
      // 없으면 "왜 회색이지"에서 멈춘다.
      onAuthFailed: (error) => debugPrint('[naver-map] 인증 실패: $error'),
    );
  }

  runApp(const ProviderScope(child: RuniverseApp()));
}

/// 릴리스 빌드에 [name]이 빠졌으면 멈춘다. 개발 빌드는 그냥 지나간다.
///
/// `--dart-define-from-file=config/prod.json`처럼 파일로 넘기므로, 이 오류는
/// "그 파일에 값이 비었다"는 뜻이다.
void _requireInRelease(bool present, String name) {
  if (kReleaseMode && !present) {
    throw StateError('$name이 없습니다. 빌드 설정(config/*.json)을 확인하세요.');
  }
}
