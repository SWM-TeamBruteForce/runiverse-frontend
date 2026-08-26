import 'package:runiverse/features/settings/domain/profile_visibility.dart';

/// 사용자가 바꿀 수 있는 설정 전부. `GET·PATCH /api/v1/users/me/settings`
/// (명세 57·58번).
///
/// 필드가 둘뿐이라 화면을 나누지 않았다. 셋으로 쪼개면 같은 API를 세 군데서
/// 부르게 된다 — 설계 문서 2절.
class AppSettings {
  const AppSettings({required this.alertConsent, required this.visibility});

  /// 알림을 받겠다는 **의사**. 기기 알림 권한과는 별개다.
  ///
  /// ## ⚠️ 이 값이 `true`라고 알림이 오지는 않는다
  ///
  /// 앱에 알림을 띄우는 코드가 아직 없다 — FCM도 로컬 알림도 없다.
  /// 지금은 의사만 저장한다. 왜 기기 권한을 여기서 다루지 않는지는
  /// 설계 문서 3절에 적혀 있다.
  final bool alertConsent;

  /// 프로필을 누가 볼 수 있는가.
  final ProfileVisibility visibility;

  /// 한 필드만 바꾼 사본.
  ///
  /// **낙관적 반영에 쓴다** — 토글을 누른 순간 화면을 먼저 바꾸고 서버에 보낸다.
  /// 실패하면 바꾸기 전 값으로 되돌린다(설계 문서 4절).
  ///
  /// ⚠️ `null`은 "그대로 둔다"는 뜻이다. `alertConsent: false`는 값을 끄는 것이고
  /// `alertConsent: null`은 건드리지 않는 것이라, 둘을 헷갈리면 토글이 안 꺼진다.
  AppSettings copyWith({bool? alertConsent, ProfileVisibility? visibility}) =>
      AppSettings(
        alertConsent: alertConsent ?? this.alertConsent,
        visibility: visibility ?? this.visibility,
      );
}
