import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kakao_flutter_sdk/kakao_flutter_sdk.dart';
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

  /// 취소 판정 — **카카오톡으로 갈지 브라우저로 갈지가 여기서 갈린다.**
  ///
  /// 카카오톡으로 못 받으면 브라우저로 한 번 더 간다. 그런데 **취소까지
  /// 그러면** 끈 창이 다른 모습으로 또 열린다. 그 둘을 가르는 것이 이 함수다.
  ///
  /// 세 가지 예외가 각각 다른 자리에서 온다 — 네이티브가 창을 닫을 때,
  /// SDK가 Dart에서 막을 때, 동의 화면에서 거절할 때.
  group('취소 판정', () {
    test('네이티브가 창을 닫으면 취소다', () {
      expect(
        KakaoCodeSource.cancelledBy(PlatformException(code: 'CANCELED')),
        isTrue,
      );
      expect(
        KakaoCodeSource.cancelledBy(PlatformException(code: 'UNKNOWN')),
        isFalse,
      );
    });

    test('SDK가 취소라고 하면 취소다', () {
      expect(
        KakaoCodeSource.cancelledBy(
          KakaoClientException(ClientErrorCause.cancelled, '사용자가 닫았다'),
        ),
        isTrue,
      );
    });

    test('⚠️ 카카오톡으로 못 하는 것은 취소가 아니다', () {
      // 이것이 **브라우저로 물러서는** 자리다. 취소로 보면 카카오톡이 없는
      // 사람은 로그인할 길이 없어진다.
      expect(
        KakaoCodeSource.cancelledBy(
          KakaoClientException(ClientErrorCause.notSupported, '카카오톡이 없다'),
        ),
        isFalse,
      );
    });

    test('동의 화면에서 거절하면 취소다', () {
      expect(
        KakaoCodeSource.cancelledBy(
          KakaoAuthException(AuthErrorCause.accessDenied, '동의하지 않았다'),
        ),
        isTrue,
      );
      // 설정이 틀린 것은 취소가 아니다. 화면은 오류 문구를 보여야 한다.
      expect(
        KakaoCodeSource.cancelledBy(
          KakaoAuthException(AuthErrorCause.invalidClient, '앱 키가 틀렸다'),
        ),
        isFalse,
      );
    });

    test('모르는 예외는 취소가 아니다', () {
      expect(KakaoCodeSource.cancelledBy(Exception('무엇인가')), isFalse);
    });
  });
}
