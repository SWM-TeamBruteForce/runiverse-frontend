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

  /// 그늘막이 **옅어지기 시작하는 지점**(띠 전체에 대한 비율).
  ///
  /// 띠는 `상태바 + [fadeLength]`라, 상태바가 끝나는 자리가 곧 여기다.
  /// 상태바가 없는 기기(또는 테스트)면 0이 되어 예전처럼 꼭대기부터 옅어진다 —
  /// 가릴 글자가 없으니 그래도 된다.
  static double _holdUntil(double scrimHeight) =>
      (scrimHeight - fadeLength) / scrimHeight;

  /// 버티던 그늘막이 **사라지는 데 쓰는 길이.**
  ///
  /// ⚠️ 짧으면 띠가 사진 위에 얹힌 **회색 막대로 보인다.** 16으로 뒀을 때
  /// 기기에서 경계가 그대로 보였다. 대비는 버티는 구간이 책임지므로, 이 값은
  /// 길게 줘도 시계가 읽히는 데는 영향이 없다.
  static const fadeLength = AppSpacing.space7;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.appColorsV2;
    final state = ref.watch(backgroundImageControllerProvider);
    final url = state is ProfileImageReady ? state.url : null;

    // 상태바 높이 + 여유. 글자가 그늘 안에 들어와야 한다.
    final scrimHeight = MediaQuery.paddingOf(context).top + fadeLength;

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
                  // ⚠️ **상태바 띠 안에서는 버티고, 그 아래 여유에서만 옅어진다.**
                  // 꼭대기에서 바로 옅어지게 두면 시계가 서 있는 높이에서 이미
                  // 절반 넘게 사라져, 밝은 사진 위 흰 글자가 2.3:1까지 떨어진다.
                  // 진하기를 올려도 구조가 같으면 같은 자리를 맴돈다 —
                  // 기기에서 재 보고 고친 값이다(설계 10절).
                  stops: [0, _holdUntil(scrimHeight), 1],
                  colors: [
                    colors.coverScrim,
                    colors.coverScrim,
                    colors.coverScrim.withAlpha(0),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
