import 'package:runiverse/features/profile/domain/profile_image_failure.dart';

/// 프로필 사진이 지금 어떤 상태인가.
///
/// `AuthState`와 같은 규칙이다 — `sealed`이라 `switch`에서 세 경우를 다 다루지
/// 않으면 컴파일러가 잡아준다.
sealed class ProfileImageState {
  const ProfileImageState();
}

/// 아직 묻지 않았거나, 묻는 중이다.
final class ProfileImageLoading extends ProfileImageState {
  const ProfileImageLoading();
}

/// 답을 받았다.
///
/// ## [url]이 `null`인 것은 실패가 아니다
///
/// **사진을 올린 적이 없는 사람**이다. 대부분이 여기 해당한다. [ProfileImageFailed]와
/// 섞으면 기본 아바타 자리에 오류 표시가 뜬다.
final class ProfileImageReady extends ProfileImageState {
  const ProfileImageReady({this.url, this.busy = false});

  /// 열람 주소. **만료되는 값이다.**
  final String? url;

  /// 올리거나 지우는 중인가.
  ///
  /// 별도 상태로 쪼개지 않는 이유는 **그동안에도 [url]을 계속 그려야 하기**
  /// 때문이다. 로딩 상태로 되돌리면 바꾸는 순간 아바타가 한 번 비었다가 돌아온다.
  final bool busy;

  ProfileImageReady copyWith({
    String? url,
    bool? busy,
    bool clearUrl = false,
  }) => ProfileImageReady(
    url: clearUrl ? null : (url ?? this.url),
    busy: busy ?? this.busy,
  );
}

/// 물어봤는데 답을 받지 못했다.
///
/// **올리기 실패는 여기 오지 않는다.** 그것은 컨트롤러가 반환값으로 돌려주고
/// 화면이 스낵바로 알린다 — 실패했다고 헤더의 사진을 지우면, 잠깐 끊긴 것 때문에
/// 멀쩡한 사진이 사라진 것처럼 보인다.
final class ProfileImageFailed extends ProfileImageState {
  const ProfileImageFailed(this.failure);

  final ProfileImageFailure failure;
}
