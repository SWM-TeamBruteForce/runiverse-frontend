import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kakao_flutter_sdk/kakao_flutter_sdk.dart';
import 'package:runiverse/app/app.dart';
import 'package:runiverse/core/config/app_config.dart';

/// 앱 진입점. Riverpod 스코프를 열고, 앱 루트를 띄운다.
///
/// [ProviderScope]는 provider가 값을 보관하는 그릇이다.
///
/// ## 카카오 SDK는 `runApp` 전에 초기화한다
///
/// 로그인 화면이 뜨자마자 눌릴 수 있어서, 그 전에 준비돼 있어야 한다.
/// 플랫폼 채널을 부르므로 [WidgetsFlutterBinding.ensureInitialized]가 먼저다.
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

  runApp(const ProviderScope(child: RuniverseApp()));
}
