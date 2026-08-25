import 'package:runiverse/features/settings/domain/login_type.dart';

/// 계정 정보. `GET /api/v1/users/me/account` (명세 55번).
///
/// 설정 화면의 계정 섹션이 그대로 그리는 값이고, **비밀번호 변경 메뉴를 보일지도
/// 여기 [loginType]이 정한다.**
///
/// ## ⚠️ `GET /users/me`에는 이 값이 없다
///
/// 기능정의서 `SETTING-HOME-001`은 설정 홈의 연관 API를 `GET /users/me`로 적고
/// 거기서 계정 유형을 받는다고 했지만, **그 응답에는 `userId`·`nickname`·
/// `isOnboarded`뿐이다.** 문서가 어긋나 있다. 계정 정보는 이 엔드포인트로만 온다.
class AccountInfo {
  const AccountInfo({required this.email, this.loginType});

  /// 계정 이메일. 화면에서 **읽기 전용**이다 — 바꾸는 API가 없다.
  final String email;

  /// 어떻게 가입했는가. **서버가 모르는 값을 보내면 `null`**이 된다.
  ///
  /// `null`일 때 비밀번호 메뉴를 **숨긴다.** 보여줬다가 409를 맞는 것보다
  /// 안 보이는 편이 낫다 — 새 제공자가 늘었을 때 그쪽은 대개 소셜이다.
  final LoginType? loginType;

  /// 비밀번호 변경 메뉴를 보일 것인가.
  bool get canChangePassword => loginType?.canChangePassword ?? false;
}
