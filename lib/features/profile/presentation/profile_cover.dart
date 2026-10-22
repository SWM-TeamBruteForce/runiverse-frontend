import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:runiverse/core/theme/v2/app_colors.dart';
import 'package:runiverse/features/profile/presentation/background_image_provider.dart';
import 'package:runiverse/features/profile/presentation/profile_image_state.dart';

/// 프로필 맨 위의 커버 사진. 시안 `158:3910` (412×200).
///
/// ## ⚠️ 상태바 아래에서 시작하고, 그늘막을 깔지 않는다
///
/// 2026-10-23에 되돌렸다. 상태바 뒤까지 올리면 시계·배터리 **흰 글자**를 사진이
/// 지우므로 그늘막이 필요했고, 그 그늘막은 기기에서 **사진 상단을 가리는 회색
/// 막대**로 보인다. 화면(`ProfilePage`)이 위 여백을 받으면 둘 다 사라진다.
///
/// 이 위젯은 여전히 **위 여백을 스스로 받지 않는다** — 화면이 이미 주므로
/// 여기서 또 받으면 두 번 밀린다.
///
/// ## ⚠️ 세 상태가 모두 기본 단색이다
///
/// 조회 중 · 안 올린 사람 · 조회 실패. 회전 표시를 넣지 않는다 — 커버는 화면 폭
/// 전체라 프로필을 열 때마다 큰 사각형이 번쩍인다. 아바타가 이미 같은 규칙이다.
class ProfileCover extends ConsumerWidget {
  const ProfileCover({super.key});

  /// 시안 치수. 폭에 맞춰 높이를 계산한다.
  static const _designWidth = 412.0;
  static const _designHeight = 200.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.appColorsV2;
    final state = ref.watch(backgroundImageControllerProvider);
    final url = state is ProfileImageReady ? state.url : null;

    return AspectRatio(
      aspectRatio: _designWidth / _designHeight,
      child: Stack(
        fit: StackFit.expand,
        children: [
          ColoredBox(color: colors.bgElevated),
          if (url != null)
            Image.network(
              url,
              fit: BoxFit.cover,
              // ⚠️ **깨지면 한 번 더 받는다.** 조회 주소는 1시간이면 만료되고,
              // 커버가 비면 "배경을 안 올린 사람"과 구분되지 않는다.
              // 다시 받는 횟수는 컨트롤러가 센다.
              //
              // ⚠️ **프레임이 끝난 뒤에 부른다.** `errorBuilder`는 빌드 중에
              // 도는데, 그 자리에서 상태를 바꾸면 Riverpod이 "빌드 중 수정"으로
              // 막거나 **다시 그리기가 스스로를 부르며 멈추지 않는다.**
              errorBuilder: (context, error, stack) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  // ⚠️ 그 사이에 화면을 떠났을 수 있다. `ref.read`는 트리에서
                  // 빠진 뒤에 부르면 **던진다.**
                  if (!context.mounted) return;
                  ref
                      .read(backgroundImageControllerProvider.notifier)
                      .retryOnce();
                });
                return const SizedBox.shrink();
              },
              // ⚠️ **그려졌으면 다음 만료를 메울 기회를 돌려준다.**
              //
              // 다시 받기를 한 번으로 묶는 것은 *연달아 실패하는* 주소를 끝없이
              // 두드리지 않으려는 것이다. 그런데 성공까지 예산으로 세면, 오래
              // 켜 둔 앱에서 **두 번째 만료부터는 영영 안 돌아온다** — 배경을
              // 올린 사람에게 기본 단색이 뜬다.
              //
              // ⚠️ **조회 성공으로 돌려주면 안 된다.** 서버가 매번 새 주소를
              // 주므로 그리기에 실패하는 한 조회 → 성공 → 다시 받기가
              // 무한히 돈다. **그림이 실제로 나온 것**만 신호로 쓴다.
              frameBuilder: (context, child, frame, wasSynchronous) {
                if (frame != null) {
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (!context.mounted) return;
                    ref
                        .read(backgroundImageControllerProvider.notifier)
                        .markRendered();
                  });
                }
                return child;
              },
            ),
        ],
      ),
    );
  }
}
