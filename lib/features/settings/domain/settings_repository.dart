import 'package:runiverse/features/settings/domain/account_info.dart';
import 'package:runiverse/features/settings/domain/app_settings.dart';
import 'package:runiverse/features/settings/domain/profile_visibility.dart';

/// 설정 저장소 — **인터페이스만 있다.**
///
/// 화면은 이 타입에만 기대고 누가 답하는지 모른다. 지금은 대부분
/// `FakeSettingsRepository`가 답한다. 일곱 항목 중 서버가 준비된 것은
/// 비밀번호 변경과 로그아웃 둘뿐이다(설계 문서 1절).
///
/// 서버가 뜨면 **`settings_provider.dart`의 한 줄**을 바꾼다.
///
/// 실패는 전부 `SettingsException`(비밀번호만 `PasswordChangeException`)으로
/// 던진다. 구현체가 dio 사정을 밖으로 흘리지 않는다 — 흘리면 화면이 HTTP를 알게 된다.
///
/// ## 로그아웃이 여기 없는 이유
///
/// 이미 `AuthController.signOut()`이 서버 호출·토큰 삭제·상태 전환을 다 한다.
/// 여기에 또 두면 토큰을 지우는 곳이 둘이 된다.
abstract interface class SettingsRepository {
  /// 이메일과 계정 유형. 명세 55번.
  Future<AccountInfo> fetchAccount();

  /// 알림 의사와 공개 범위. 명세 57번.
  Future<AppSettings> fetchSettings();

  /// **준 것만 보낸다.** 생략한 필드는 서버가 지금 값을 그대로 둔다.
  ///
  /// 돌려받은 값을 그대로 쓴다. 보낸 값을 화면에 쓰면 안 된다 —
  /// 서버는 **부분 수정이어도 갱신 후 전체 설정을 돌려주므로**, 연타해서
  /// 응답 순서가 뒤바뀌어도 마지막 응답이 화면을 정리해 준다.
  Future<AppSettings> updateSettings({
    bool? alertConsent,
    ProfileVisibility? visibility,
  });

  /// 로컬 계정만 가능하다. 소셜이면 `notLocalAccount`.
  ///
  /// **성공해도 토큰은 그대로다.** 서버가 세션을 끊지 않는다 —
  /// 다시 로그인시키지 않아도 된다.
  Future<void> changePassword({required String current, required String next});

  /// 계정을 지운다. **되돌릴 수 없다.**
  ///
  /// ## ⚠️ 경로가 확정되지 않았다
  ///
  /// 4차 API 명세서 엔드포인트 목록에 **없다.** 2.5차(과거 명세서)에
  /// `DELETE /api/v1/users/me`가 있고, 기능정의서 `USR-ACCOUNT-001`은
  /// 그 경로를 *"권장, 실제 경로 협의 필요"*라고만 적었다. 그 경로를 가정한다.
  ///
  /// 성공하면 **서버 세션이 이미 죽어 있다.** 이어서 `signOut()`을 부르면
  /// 실패할 호출을 한 번 더 보내는 셈이라, 로컬만 비우는 경로를 쓴다.
  Future<void> withdraw();
}
