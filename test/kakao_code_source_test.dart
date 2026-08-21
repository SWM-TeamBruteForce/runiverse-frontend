import 'package:flutter_test/flutter_test.dart';
import 'package:runiverse/core/config/app_config.dart';
import 'package:runiverse/features/auth/data/kakao_code_source.dart';
import 'package:runiverse/features/auth/domain/auth_failure.dart';
import 'package:runiverse/features/auth/domain/oauth_provider.dart';

/// 카카오 앱 키가 없는 빌드에서 카카오 버튼을 누르면 무슨 일이 일어나는가.
///
/// `main.dart`는 키가 없으면 `KakaoSdk.init`을 건너뛴다. 그런데 버튼은 그대로
/// 눌리므로 **초기화되지 않은 SDK를 부르게 된다.** 그러면
/// `LateInitializationError`가 나오는데, 그것은 `Exception`이 아니라 `Error`라
/// 이 클래스의 `on Exception`에도 걸리지 않고 화면까지 그대로 올라간다.
///
/// 여기서 보는 것은 **그 상황을 이 클래스가 스스로 막는가**다.
void main() {
  test('카카오 키가 없으면 SDK를 부르지 않고 준비 중으로 돌려준다', () async {
    // `--dart-define`은 테스트에 넘어오지 않는다. 이 전제가 깨지면 아래
    // 단언이 엉뚱한 것을 보게 되므로 먼저 못 박는다.
    expect(
      AppConfig.hasKakaoNativeAppKey,
      isFalse,
      reason: 'flutter test에는 앱 키가 주입되지 않는다',
    );

    await expectLater(
      const KakaoCodeSource().authorize(OauthProvider.kakao),
      throwsA(
        isA<AuthException>().having(
          (error) => error.failure,
          'failure',
          AuthFailure.oauthUnavailable,
        ),
      ),
    );
  });
}
