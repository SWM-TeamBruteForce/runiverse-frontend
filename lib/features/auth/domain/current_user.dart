import 'package:runiverse/features/auth/domain/login_type.dart';

/// 지금 로그인한 사람. `GET /api/v1/users/me`의 답이다.
///
/// ## 왜 auth에 있는가
///
/// "나는 누구인가"는 인증이 답하는 질문이다. 닉네임·소개글이 함께 오지만 그것은
/// **같은 답의 일부**고, 프로필 화면(S22)도 이 값을 읽는다.
///
/// ## ⚠️ [isOnboarded]의 유일한 출처다
///
/// 저장소에도 같은 이름의 값이 있지만 그것은 **로그인하던 순간의 사진**이다.
/// 다른 기기에서 프로필을 채우면 어긋난다. 앱에 들어올 때마다 서버에 다시 묻고,
/// 홈의 유도 카드는 여기서 온 값만 본다.
///
/// 단, **서버가 그 필드를 안 주면 `null`이다.** 그때는 이것이 출처가 아니고,
/// 부르는 쪽이 직전 값을 지킨다.
/// ## 계정 정보도 여기 있다
///
/// [email]과 [loginType]은 **설정 화면에서만 쓰지만** 이 응답이 함께 싣는다
/// (명세 10-1). 앱에 들어올 때마다 어차피 타는 경로라, 설정에 들어갈 때
/// 왕복을 한 번 더 하지 않는다.
///
/// ⚠️ 예전에는 `GET /users/me/account`라는 전용 경로가 있었다. **그 경로는
/// 없어졌다.** 계정 섹션이 안 뜨던 원인이기도 하다.
class CurrentUser {
  const CurrentUser({
    required this.userId,
    required this.isOnboarded,
    this.email,
    this.loginType,
    this.nickname,
    this.profileImageUrl,
    this.introduction,
  });

  final String userId;

  /// 계정 이메일. 화면에서 **읽기 전용**이다 — 바꾸는 API가 없다.
  final String? email;

  /// 어떻게 가입했는가. **서버가 모르는 값을 보내면 `null`**이 된다.
  ///
  /// `null`일 때 비밀번호 메뉴를 **숨긴다.** 보여줬다가 409를 맞는 것보다
  /// 안 보이는 편이 낫다 — 새 제공자가 늘었을 때 그쪽은 대개 소셜이다.
  final LoginType? loginType;

  /// 비밀번호 변경 메뉴를 보일 것인가.
  bool get canChangePassword => loginType?.canChangePassword ?? false;

  /// 프로필을 채웠는가. 홈의 유도 카드를 켜고 끄는 값이다.
  ///
  /// ⚠️ **`null`은 "서버가 답하지 않았다"이지 `false`가 아니다.** 둘을 섞으면
  /// 저장된 `true`를 덮어쓸 근거가 생기고, 프로필을 막 채운 사람이 폼으로 돌아간다.
  final bool? isOnboarded;

  /// 온보딩 전에는 없다. **`isOnboarded`가 `false`면 셋 다 `null`일 수 있다.**
  final String? nickname;
  final String? profileImageUrl;
  final String? introduction;
}
