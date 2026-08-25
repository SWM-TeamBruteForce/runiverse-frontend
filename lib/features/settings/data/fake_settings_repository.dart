import 'package:runiverse/features/settings/domain/account_info.dart';
import 'package:runiverse/features/settings/domain/app_settings.dart';
import 'package:runiverse/features/settings/domain/login_type.dart';
import 'package:runiverse/features/settings/domain/password_change_failure.dart';
import 'package:runiverse/features/settings/domain/profile_visibility.dart';
import 'package:runiverse/features/settings/domain/settings_failure.dart';
import 'package:runiverse/features/settings/domain/settings_repository.dart';

/// 서버 없이 설정 화면을 돌려보기 위한 가짜.
///
/// ## 지금은 이게 대부분을 답한다
///
/// 일곱 항목 중 서버가 준비된 것은 비밀번호 변경과 로그아웃 둘뿐이다.
/// 계정 조회·설정 조회·설정 변경·탈퇴는 **아직 배포되지 않았다**(설계 문서 1절).
/// 화면을 다 그려 두고 서버가 뜰 때 `settings_provider.dart`의 한 줄만 바꾼다.
///
/// ## 값을 들고 있는다
///
/// [updateSettings]가 [settings]를 실제로 바꾼다. 안 그러면 토글을 켜고 화면을
/// 나갔다 들어왔을 때 되돌아가 있어서, **낙관적 반영이 제대로 도는지 알 수 없다.**
class FakeSettingsRepository implements SettingsRepository {
  FakeSettingsRepository({
    this.latency = const Duration(milliseconds: 300),
    this.email = 'runner@example.com',
    this.loginType = LoginType.local,
    AppSettings? settings,
    this.accountFailure,
    this.settingsFailure,
    this.updateFailure,
    this.passwordFailure,
    this.withdrawFailure,
  }) : settings =
           settings ??
           const AppSettings(
             // 명세의 기본값이다. 서버도 `true`로 시작한다.
             alertConsent: true,
             visibility: ProfileVisibility.public,
           );

  /// 서버를 흉내 내는 지연. 테스트에서는 `Duration.zero`를 준다.
  ///
  /// 0이 아니어야 하는 이유는, **낙관적 반영이 눈에 보이려면 응답이 늦어야**
  /// 해서다. 즉시 답하면 화면이 먼저 바뀌었는지 응답을 받고 바뀌었는지 구분되지 않는다.
  final Duration latency;

  final String email;
  final LoginType? loginType;

  /// 지금 값. [updateSettings]가 여기를 고친다.
  AppSettings settings;

  // ⚠️ **`final`이 아니다.** 서버가 죽었다 살아나는 상황을 만들려면 같은
  // 인스턴스가 도중에 답을 바꿀 수 있어야 한다 — 새 인스턴스로 갈아 끼우면
  // "실패가 지워졌는지"를 검사하지 못하고 처음부터 실패가 없던 것을 본다.

  SettingsFailure? accountFailure;
  SettingsFailure? settingsFailure;

  /// 주면 설정 변경이 그 이유로 실패한다. **되돌리기를 보는 데 쓴다.**
  SettingsFailure? updateFailure;

  PasswordChangeFailure? passwordFailure;
  SettingsFailure? withdrawFailure;

  /// 마지막으로 받은 변경 요청. **무엇을 보냈고 무엇을 뺐는지** 보는 데 쓴다.
  Map<String, Object?>? updated;

  /// 몇 번 불렸는가. 부르지 말아야 할 때 부르지 않는지 보는 데 쓴다.
  var updateCalls = 0;
  var withdrawCalls = 0;

  /// 마지막으로 받은 비밀번호 한 쌍.
  String? currentPassword;
  String? newPassword;

  @override
  Future<AccountInfo> fetchAccount() async {
    await Future<void>.delayed(latency);
    final reason = accountFailure;
    if (reason != null) throw SettingsException(reason);
    return AccountInfo(email: email, loginType: loginType);
  }

  @override
  Future<AppSettings> fetchSettings() async {
    await Future<void>.delayed(latency);
    final reason = settingsFailure;
    if (reason != null) throw SettingsException(reason);
    return settings;
  }

  @override
  Future<AppSettings> updateSettings({
    bool? alertConsent,
    ProfileVisibility? visibility,
  }) async {
    updateCalls++;
    updated = {'alertConsent': ?alertConsent, 'visibility': ?visibility};
    await Future<void>.delayed(latency);

    final reason = updateFailure;
    // ⚠️ 실패하면 [settings]를 **고치지 않는다.** 서버가 거절했는데 가짜가
    // 값을 바꿔 두면, 화면이 되돌린 뒤 다시 열었을 때 바뀐 값이 나온다.
    if (reason != null) throw SettingsException(reason);

    settings = settings.copyWith(
      alertConsent: alertConsent,
      visibility: visibility,
    );
    // 서버는 부분 수정이어도 **전체 설정**을 돌려준다. 가짜도 그렇게 군다 —
    // 화면이 응답을 쓰는지 보낸 값을 쓰는지가 테스트에서 갈려야 한다.
    return settings;
  }

  @override
  Future<void> changePassword({
    required String current,
    required String next,
  }) async {
    currentPassword = current;
    newPassword = next;
    await Future<void>.delayed(latency);
    final reason = passwordFailure;
    if (reason != null) throw PasswordChangeException(reason);
  }

  @override
  Future<void> withdraw() async {
    withdrawCalls++;
    await Future<void>.delayed(latency);
    final reason = withdrawFailure;
    if (reason != null) throw SettingsException(reason);
  }
}
