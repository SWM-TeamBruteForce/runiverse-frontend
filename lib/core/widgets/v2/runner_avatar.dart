import 'package:flutter/material.dart';
import 'package:runiverse/core/theme/v2/app_colors.dart';
import 'package:runiverse/core/theme/v2/app_typography.dart';

/// 러너 한 명의 동그란 사진 — 시안 `158:3110`.
///
/// 매칭 완료 카드의 참여자 줄과, 대기 중 카드의 궤도가 같은 것을 쓴다.
///
/// ## ⚠️ 도메인 타입을 받지 않는다
///
/// `RoomPlayer`를 받으면 `core/widgets/`가 matching 의 도메인에 묶인다.
/// 이름과 사진 주소만 받으면 어느 feature 에서든 쓸 수 있다.
///
/// ## 사진이 없거나 못 받을 수 있다
///
/// 프로필 사진은 선택이고, 주소가 있어도 만료되거나 네트워크가 끊길 수 있다.
/// **둘 다 첫 글자로 떨어진다** — 빈 동그라미를 두면 자리는 차지하는데
/// 누구인지 알 수 없다.
class RunnerAvatarV2 extends StatelessWidget {
  const RunnerAvatarV2({
    required this.nickname,
    this.imageUrl,
    this.size = 60,
    super.key,
  });

  /// 사진이 없을 때 첫 글자를 뽑는 데 쓴다. 읽히는 이름이기도 하다.
  final String nickname;

  final String? imageUrl;

  /// 시안은 참여자 줄에서 60이다.
  final double size;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColorsV2;
    final url = imageUrl;

    return Semantics(
      label: nickname,
      image: true,
      container: true,
      // ⚠️ **안쪽 글자를 가린다.** 사진이 없을 때 첫 글자를 그리는데, 안 가리면
      // 스크린리더가 이름 대신 `러`만 읽는다(테스트가 잡았다).
      //
      // ⚠️ `AppTabBarV2`에서는 이걸 쓰면 **안 된다** — 거기엔 `InkWell`의 탭
      // 액션이 있어서 같이 지워진다. 여기는 누를 것이 없어 괜찮다.
      excludeSemantics: true,
      child: Container(
        width: size,
        height: size,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: colors.primaryMuted,
          shape: BoxShape.circle,
        ),
        child: url == null || url.isEmpty
            ? _Initial(nickname: nickname, size: size)
            : Image.network(
                url,
                fit: BoxFit.cover,
                // ⚠️ 못 받으면 **첫 글자로 떨어진다.** 기본 오류 아이콘이
                // 뜨면 동그라미 안에 깨진 그림이 들어앉는다.
                errorBuilder: (context, error, stack) =>
                    _Initial(nickname: nickname, size: size),
              ),
      ),
    );
  }
}

/// 사진을 못 쓸 때의 첫 글자.
class _Initial extends StatelessWidget {
  const _Initial({required this.nickname, required this.size});

  final String nickname;
  final double size;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColorsV2;

    return Center(
      child: Text(
        // 탈퇴한 사람은 이름이 익명 처리돼 오므로 그대로 쓴다.
        nickname.isEmpty ? '?' : nickname.characters.first,
        style: AppTypographyV2.body02.copyWith(color: colors.primary),
      ),
    );
  }
}
