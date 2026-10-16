import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runiverse/features/auth/data/apple_code_source.dart';
import 'package:runiverse/features/auth/domain/apple_nonce.dart';
import 'package:runiverse/features/auth/domain/auth_failure.dart';
import 'package:runiverse/features/auth/domain/oauth_authorization.dart';
import 'package:runiverse/features/auth/domain/oauth_provider.dart';

/// 애플 코드 소스 — **어느 값을 어디로 보내는가.**
///
/// ## ⚠️ 이 경로에는 그물이 없었다
///
/// `apple_login_test`는 `FakeOauthCodeSource`로 결과를 **주입**한다 — SDK 호출을
/// 지나지 않는다. 그래서 nonce 를 바꿔 보내도(원본을 애플에, 해시를 서버에)
/// 그 테스트는 통과한다. 그런데 그것이 연동 가이드 5절이 꼽는 **첫 번째
/// 증상**이다 — "토큰은 받았는데 서버가 401을 준다".
///
/// 앱에서는 아무 증상이 없다. 애플은 받은 문자열을 그대로 ID 토큰에 박아 주므로
/// 로그인 창은 정상적으로 닫히고, 어긋남은 **서버에서만** 드러난다.
///
/// ## 플랫폼 채널을 가로챈다
///
/// `sign_in_with_apple`은 네이티브를 메서드 채널로 부른다. 패키지가
/// `FLUTTER_TEST` 환경에서는 플랫폼 검사를 건너뛰도록 열어 두어서, 채널만
/// 갈아끼우면 실제 호출 경로를 그대로 지날 수 있다.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel(
    'com.aboutyou.dart_packages.sign_in_with_apple',
  );

  /// 애플에 넘어간 요청. 마지막 호출 하나만 남긴다.
  Map<Object?, Object?>? request;

  /// 채널이 돌려줄 것. [error]를 주면 그것을 던진다.
  void respond({String? identityToken = 'id-token', PlatformException? error}) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          // 인자는 요청 하나가 담긴 리스트다(`MethodChannelSignInWithApple`).
          request = (call.arguments as List).first as Map<Object?, Object?>;

          if (error != null) throw error;
          return <Object?, Object?>{
            'type': 'appleid',
            'authorizationCode': 'auth-code',
            'identityToken': identityToken,
            'email': 'runner@privaterelay.appleid.com',
            'userIdentifier': 'apple-user',
          };
        });
  }

  setUp(() {
    request = null;
    // 소스가 iOS 가 아니면 SDK 를 부르기 전에 돌아선다. 그 분기는 아래에서
    // 따로 보고, 여기서는 iOS 인 척한다.
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
  });

  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  Future<OauthAuthorization> authorize() =>
      const AppleCodeSource().authorize(OauthProvider.apple);

  Future<AuthFailure> failureOf() async {
    try {
      await authorize();
    } on AuthException catch (error) {
      return error.failure;
    }
    fail('실패를 던져야 한다');
  }

  test('⚠️ 애플에는 해시를, 서버에는 원본을 보낸다', () async {
    respond();

    final result = await authorize() as OauthIdTokenWithNonce;
    final sentToApple = request!['nonce'] as String;

    // 서버가 원본을 해시해 토큰 안의 값과 대조한다. 이 등식이 깨지면 401이다.
    expect(AppleNonce.hash(result.nonce), sentToApple);
    // 바꿔 보낸 것이 아님을 못 박는다 — 위 한 줄만으로는 둘이 같아도 통과한다.
    expect(result.nonce, isNot(sentToApple));
    expect(result.idToken, 'id-token');
  });

  test('⚠️ 로그인마다 다른 nonce 를 쓴다', () async {
    // 값을 캐시하면 nonce 가 막으려던 재전송을 막지 못한다.
    respond();

    final first = await authorize() as OauthIdTokenWithNonce;
    final second = await authorize() as OauthIdTokenWithNonce;

    expect(first.nonce, isNot(second.nonce));
  });

  test('이메일만 요구한다', () async {
    // 서버가 **이메일로 계정을 만든다.** 이름은 쓰는 곳이 없다 —
    // 닉네임은 온보딩에서 따로 받는다.
    respond();

    await authorize();

    expect(request!['scopes'], ['email']);
  });

  test('⚠️ 취소는 오류와 다른 이유로 돌아온다', () async {
    // 창을 닫았을 뿐인데 빨간 문구가 뜨면 고장으로 읽힌다. 화면이 이 값만
    // 걸러낸다.
    respond(error: PlatformException(code: 'authorization-error/canceled'));

    expect(await failureOf(), AuthFailure.oauthCancelled);
  });

  test('그 밖의 인가 실패는 다시 눌러 볼 수 있다', () async {
    respond(error: PlatformException(code: 'authorization-error/failed'));

    expect(await failureOf(), AuthFailure.oauthFailed);
  });

  test('⚠️ 지원하지 않는 기기는 다시 눌러도 되지 않는다', () async {
    // "다시 시도해주세요"는 거짓말이다. iOS 13 미만에서 온다.
    respond(error: PlatformException(code: 'not-supported'));

    expect(await failureOf(), AuthFailure.oauthUnavailable);
  });

  test('⚠️ ID 토큰이 비어 오면 서버에 보내지 않는다', () async {
    // 빈 문자열을 보내면 서버가 400 `INVALID_REQUEST`를 주는데, 그 화면
    // 문구는 원인을 가린다.
    respond(identityToken: null);

    expect(await failureOf(), AuthFailure.oauthFailed);
  });

  test('⚠️ ID 토큰과 nonce 를 로그에 남기지 않는다', () async {
    // 연동 가이드 6절. 로그는 기기에 남고 크래시 수집으로 빠져나가므로 **한 번
    // 찍히면 회수할 수 없다.** "무엇이 왔는지" 찍어 보려다 흘리는 자리가
    // 성공 경로(토큰과 nonce 가 둘 다 손에 있다)와 실패 경로 둘 다에 있다.
    final logs = <String>[];
    final original = debugPrint;
    debugPrint = (message, {wrapWidth}) => logs.add(message ?? '');

    try {
      respond(identityToken: 'secret-id-token');
      final ok = await authorize() as OauthIdTokenWithNonce;

      respond(error: PlatformException(code: 'authorization-error/failed'));
      await failureOf();

      final printed = logs.join('\n');
      expect(printed, isNot(contains('secret-id-token')));
      expect(printed, isNot(contains(ok.nonce)));
      expect(printed, isNot(contains(AppleNonce.hash(ok.nonce))));
    } finally {
      debugPrint = original;
    }
  });

  test('⚠️ iOS가 아니면 SDK 를 아예 부르지 않는다', () async {
    // 안드로이드에서 부르면 패키지가 애플 **웹** 흐름을 열고, 그렇게 받은
    // 토큰은 발급 대상이 번들 ID 가 아니라서 서버가 401을 돌려준다
    // (연동 가이드 3절).
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    respond();

    expect(await failureOf(), AuthFailure.oauthUnavailable);
    expect(request, isNull, reason: 'SDK 까지 가면 안 된다');
  });
}
