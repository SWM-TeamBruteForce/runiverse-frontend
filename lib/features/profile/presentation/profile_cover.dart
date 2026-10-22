import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:runiverse/core/theme/v2/app_colors.dart';
import 'package:runiverse/core/theme/v2/app_spacing.dart';
import 'package:runiverse/features/profile/presentation/background_image_provider.dart';
import 'package:runiverse/features/profile/presentation/profile_image_state.dart';

/// 프로필 맨 위의 커버 사진. 시안 `158:3910` (412×200).
///
/// ## ⚠️ 상태바 뒤까지 올라간다
///
/// 시안은 커버와 상태바 틀이 **같은 자리에서 시작한다.** 그래서 이 위젯은
/// `SafeArea` 밖에 놓이고, 위 여백을 받지 않는다.
///
/// ## ⚠️ 그늘막은 상태에 관계없이 깔린다
///
/// 시계·배터리 글자는 **흰색 한 가지**다. 밝은 사진을 올린 사람은 그 글자를
/// 잃는다. 사진이 있을 때만 깔도록 가르면 그 분기가 틀렸을 때 **시계가 사라지는
/// 쪽으로** 틀린다 — 어두운 바탕에 깔린 그늘막은 눈에 띄지 않으므로 늘 깐다.
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

  /// 그늘막을 찾는 열쇠. **테스트가 읽는다** — 그늘막은 색만 있어서 위젯
  /// 종류로는 다른 것과 구분되지 않는다.
  static const scrimKey = ValueKey('profile-cover-scrim');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.appColorsV2;
    final state = ref.watch(backgroundImageControllerProvider);
    final url = state is ProfileImageReady ? state.url : null;

    // 상태바 높이 + 여유. 글자가 그늘 안에 들어와야 한다.
    final scrimHeight = MediaQuery.paddingOf(context).top + AppSpacing.space4;

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
          Align(
            alignment: Alignment.topCenter,
            child: Container(
              key: scrimKey,
              height: scrimHeight,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [colors.coverScrim, colors.coverScrim.withAlpha(0)],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
