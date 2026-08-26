import 'package:runiverse/features/settings/domain/account_info.dart';
import 'package:runiverse/features/settings/domain/app_settings.dart';
import 'package:runiverse/features/settings/domain/profile_visibility.dart';
import 'package:runiverse/features/settings/domain/settings_repository.dart';

/// **배포된 API만 서버로 보내고, 나머지는 가짜가 답한다.**
///
/// ## ⚠️ 이것은 임시다
///
/// 설정 일곱 항목 중 서버가 준비된 것은 비밀번호 변경뿐이다.
/// 나머지(계정 조회 55번 · 설정 조회 57번 · 설정 변경 58번 · 탈퇴)는 **개발전**이라,
/// 진짜로 부르면 500이 돌아오고 화면이 통째로 오류가 된다.
///
/// 그렇다고 비밀번호까지 가짜로 두면 **되는 기능을 안 쓰는 것**이라,
/// 둘을 갈라 끼운다.
///
/// ## 서버가 다 뜨면 이 파일을 지운다
///
/// `settings_provider.dart`가 [live]를 그대로 쓰게 바꾸고 이 클래스를 삭제한다.
/// 지울 때를 알아보게 하려고 따로 두었다 — `HttpSettingsRepository`에 `if`를
/// 심으면 나중에 무엇이 임시였는지 찾지 못한다.
class StagedSettingsRepository implements SettingsRepository {
  const StagedSettingsRepository({required this.live, required this.fake});

  /// 진짜 서버. 지금은 비밀번호 변경만 간다.
  final SettingsRepository live;

  /// 배포되지 않은 것을 대신 답한다.
  final SettingsRepository fake;

  /// ✅ 명세 56번 — 개발완료.
  @override
  Future<void> changePassword({
    required String current,
    required String next,
  }) => live.changePassword(current: current, next: next);

  /// ❌ 명세 55번 — 개발전.
  @override
  Future<AccountInfo> fetchAccount() => fake.fetchAccount();

  /// ❌ 명세 57번 — 개발전.
  @override
  Future<AppSettings> fetchSettings() => fake.fetchSettings();

  /// ❌ 명세 58번 — 개발전.
  @override
  Future<AppSettings> updateSettings({
    bool? alertConsent,
    ProfileVisibility? visibility,
  }) => fake.updateSettings(alertConsent: alertConsent, visibility: visibility);

  /// ❌ 4차 명세서에 경로가 아예 없다.
  @override
  Future<void> withdraw() => fake.withdraw();
}
