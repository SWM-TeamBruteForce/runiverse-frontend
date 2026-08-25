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
void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 키가 없으면 초기화하지 않는다. 빈 키로 초기화하면 SDK가 `kakao://oauth`를
  // 리다이렉트 주소로 삼고, 카카오 버튼을 눌렀을 때 원인을 알기 어려운 오류가
  // 난다 — **아예 초기화하지 않는 편이 낫다.**
  //
  // 키가 없어도 앱은 돌아간다. 카카오 로그인만 쓸 수 없다.
  if (AppConfig.hasKakaoNativeAppKey) {
    await KakaoSdk.init(nativeAppKey: AppConfig.kakaoNativeAppKey);
  }

  // 지도도 같은 규칙이다. 키가 없으면 러닝 화면이 지도 자리에 안내를 그리고,
  // 시간·거리·페이스는 그대로 돈다.
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
