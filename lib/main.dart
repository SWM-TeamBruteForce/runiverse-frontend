import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:facebook_app_events/facebook_app_events.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/material.dart';
import 'package:flutter_naver_map/flutter_naver_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:kakao_flutter_sdk/kakao_flutter_sdk.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:runiverse/app/app.dart';
import 'package:runiverse/core/analytics/analytics.dart';
import 'package:runiverse/core/analytics/firebase_analytics_service.dart';
import 'package:runiverse/core/config/app_config.dart';
import 'package:runiverse/core/version/installed_app_version.dart';
import 'package:runiverse/core/storage/body_profile_provider.dart';
import 'package:runiverse/features/notification/data/firebase_push_messaging.dart';
import 'package:runiverse/features/notification/presentation/push_provider.dart';
import 'package:runiverse/features/profile/presentation/profile_provider.dart';

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

  // 설치된 앱의 버전 이름. **화면이 서기 전에 읽어 둔다** — 서버로 가는 모든
  // 요청에 헤더로 싣고(`X-App-Version`), 스플래시가 이 값으로 업데이트 여부를
  // 판정한다. 플랫폼 채널을 부르므로 위의 `ensureInitialized`가 먼저다.
  //
  // ⚠️ **실패해도 멈추지 않는다.** 버전을 못 읽는 것은 앱을 못 쓸 이유가
  // 아니다. 헤더를 안 싣고 판정도 하지 않을 뿐이고, 서버도 헤더가 없으면
  // 그냥 통과시킨다(API 명세서 공통 규칙).
  await InstalledAppVersion.load();

  // Firebase — **인자를 넘기지 않는다.** 설정은 플랫폼별 설정 파일에서 오고,
  // flavor 폴더(`dev`·`prod`)에 따로 있다(Android `android/app/src/` 아래,
  // iOS `ios/Runner/Firebase/` 아래). 그래서 `firebase_options.dart` 도 없다.
  //
  // ⚠️ 위의 세 SDK 와 달리 **키 유무를 보고 거르지 않는다.** 설정 파일이
  // 없으면 Gradle 이 빌드를 먼저 세우므로, 여기까지 왔다면 파일은 있다.
  await Firebase.initializeApp();

  // 잡히지 않은 오류를 Crashlytics로 보낸다. 디버그 빌드는 보내지 않는다 —
  // `flutter run` 중에 난 오류가 운영·dev 대시보드에 섞이면 진짜를 못 가린다.
  //
  // ⚠️ 수집은 **꺼진 채로 뜬다**(매니페스트·Info.plist). 여기서 끄기만 하면
  // 이 줄 전에 난 네이티브 오류는 이미 보내진 뒤다. 켜는 쪽만 여기서 한다.
  final crashlytics = FirebaseCrashlytics.instance;
  await crashlytics.setCrashlyticsCollectionEnabled(!kDebugMode);
  // 화면을 그리다 난 오류(위젯 빌드·레이아웃).
  FlutterError.onError = crashlytics.recordFlutterFatalError;
  // 그 밖의 비동기 오류. `true` 를 돌려줘야 처리된 것으로 본다.
  PlatformDispatcher.instance.onError = (error, stack) {
    unawaited(crashlytics.recordError(error, stack, fatal: true));
    return true;
  };

  // 키가 없으면 초기화하지 않는다. 빈 키로 초기화하면 SDK가 `kakao://oauth`를
  // 리다이렉트 주소로 삼고, 카카오 버튼을 눌렀을 때 원인을 알기 어려운 오류가
  // 난다 — **아예 초기화하지 않는 편이 낫다.**
  //
  // 키가 없어도 앱은 돌아간다. 카카오 로그인만 쓸 수 없다.
  _requireInRelease(AppConfig.hasKakaoNativeAppKey, 'KAKAO_NATIVE_APP_KEY');
  if (AppConfig.hasKakaoNativeAppKey) {
    await KakaoSdk.init(nativeAppKey: AppConfig.kakaoNativeAppKey);
  }

  // 구글도 같은 규칙이다. **웹** 클라이언트 ID로 초기화한다 — ID 토큰에 찍히는
  // 수신자가 서버가 확인하는 값과 같아야 한다(`AppConfig.googleServerClientId`).
  //
  // iOS는 iOS 클라이언트 ID도 함께 넘긴다 — 빠지면 플러그인이 웹 ID를 버린다.
  //
  // ID가 없으면 건너뛴다. 그러면 `GoogleCodeSource` 가 SDK를 부르기 전에
  // `oauthUnavailable` 로 돌아서고, 버튼은 `준비 중`이라 답한다.
  _requireInRelease(
    AppConfig.hasGoogleServerClientId,
    'GOOGLE_SERVER_CLIENT_ID',
  );
  if (Platform.isIOS) {
    _requireInRelease(AppConfig.hasGoogleIosClientId, 'GOOGLE_IOS_CLIENT_ID');
  }
  if (AppConfig.hasGoogleServerClientId) {
    await GoogleSignIn.instance.initialize(
      clientId: Platform.isIOS ? AppConfig.googleIosClientId : null,
      serverClientId: AppConfig.googleServerClientId,
    );
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

  // ⚠️ **이 override 를 지우면 분석이 조용히 멈춘다.** 기본값은
  // [NoopAnalytics] 다 — 위젯 테스트에 플랫폼 채널이 없어서 그렇게 뒀다.
  // 진짜를 끼우는 곳은 조립하는 자리인 여기뿐이다.
  runApp(
    ProviderScope(
      overrides: [
        analyticsProvider.overrideWithValue(FirebaseAnalyticsService()),
        // ⚠️ **이것을 지우면 러닝 중 칼로리가 `--`로 돌아간다.** 기본값은
        // `null`(묻지 않는다)이고, 서버에서 몸무게를 읽는 길은 이 한 줄뿐이다.
        // 포트가 `core`에 있는 이유는 `BodyProfileRemote` 주석에 있다.
        bodyProfileRemoteProvider.overrideWith(
          (ref) => ref.watch(profileRepositoryProvider),
        ),
        // ⚠️ **이것을 지우면 푸시가 조용히 멈춘다.** 기본값은 토큰이 없는
        // `NoopPushMessaging`이라 서버에 기기를 올리지 않는다. 분석과 같은
        // 이유로 진짜는 여기서만 끼운다.
        pushMessagingProvider.overrideWithValue(FirebasePushMessaging()),
      ],
      child: const RuniverseApp(),
    ),
  );

  // Meta는 **첫 화면이 그려진 뒤에** 시작한다. 기다리지 않는다 — 창이 떠 있는
  // 동안에도 스플래시는 제 할 일을 한다.
  WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(_startMeta()));
}

/// Meta 광고로 들어온 설치를 Meta가 셀 수 있게 설치·실행 신호를 보낸다.
///
/// ## ⚠️ iOS는 추적 허용 창이 먼저다
///
/// 설치 신호는 **설치당 한 번**, 처음 [FacebookAppEvents.activateApp]을 부를
/// 때 그 순간의 허용 상태를 싣고 나간다(Meta iOS SDK `publishInstall`). 창을
/// 나중에 띄우면 사용자가 허용해도 설치 신호는 이미 "허용 안 함"으로 나간
/// 뒤다. 두 번째 실행부터는 iOS가 창을 다시 띄우지 않고 저장된 답을 돌려준다.
///
/// 거절해도 Meta 시작과 실행 기록은 그대로 한다.
///
/// ## 키가 없으면 아무것도 하지 않는다
///
/// 창도 띄우지 않고 앱은 그대로 돈다([AppConfig.hasMetaAppId]).
///
/// ## 실패해도 앱은 멈추지 않는다
///
/// 광고 측정이 안 되는 것은 앱을 못 쓸 이유가 아니다. 오류는 버리지 않고
/// Crashlytics에 남긴다.
///
/// ⚠️ 안드로이드에서 `config/*.json`에만 키를 넣고 `-P META_APP_ID`를
/// 빼먹으면 여기서 실패한다. 매니페스트는 json을 읽지 못한다(build.gradle.kts).
Future<void> _startMeta() async {
  if (!AppConfig.hasMetaAppId) return;
  try {
    if (Platform.isIOS) {
      await _askTracking();
    }
    final meta = FacebookAppEvents();
    await meta.initializeSdk();
    await meta.activateApp();
  } catch (error, stack) {
    debugPrint('[meta] 시작 실패: $error');
    await FirebaseCrashlytics.instance.recordError(error, stack);
  }
}

/// iOS 추적 허용 창을 띄운다.
///
/// ⚠️ 이 창은 앱이 활성일 때만 뜬다. 첫 화면이 그려진 직후는 활성이 보장되지
/// 않아서, 실기기에서 창이 뜰 때도 있고 안 뜰 때도 있었다. 활성
/// ([AppLifecycleState.resumed])이 될 때까지 기다렸다가 묻는다.
Future<void> _askTracking() async {
  if (WidgetsBinding.instance.lifecycleState != AppLifecycleState.resumed) {
    final resumed = Completer<void>();
    final listener = AppLifecycleListener(onResume: resumed.complete);
    await resumed.future;
    listener.dispose();
  }
  await Permission.appTrackingTransparency.request();
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
