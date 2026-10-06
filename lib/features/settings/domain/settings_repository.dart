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
  /// `DELETE /api/v1/users/me` — 명세 57번. 요청 본문도 응답 본문도 없다(204).
  ///
  /// ⚠️ 예전 주석은 *"4차 명세서에 경로가 없어 가정한다"*고 적고 있었다.
  /// 1차 명세서에 **그 경로 그대로 개발완료**로 올라와 있다.
  ///
  /// 성공하면 **서버 세션이 이미 죽어 있다.** 이어서 `signOut()`을 부르면
  /// 실패할 호출을 한 번 더 보내는 셈이라, 로컬만 비우는 경로를 쓴다.
  ///
  /// ## ⚠️ 진행 중인 것이 있어도 탈퇴된다
  ///
  /// 서버가 정리한다 — 대기 중인 신청은 취소되고, 확정된 방은 나가기가
  /// 적용되며, 러닝 중이면 **마지막으로 받은 좌표로 종료**된다. 앱이 먼저
  /// 정리할 필요가 없다.
  ///
  /// 일시적 오류로 못 지우면 503 `ACCOUNT_DELETION_UNAVAILABLE`이다.
  /// **그때 탈퇴는 처리되지 않았으므로** 다시 시도하면 된다.
  Future<void> withdraw();
}
