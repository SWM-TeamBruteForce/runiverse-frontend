import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:runiverse/app/router/app_routes.dart';
import 'package:runiverse/core/strings/app_strings.dart';
import 'package:runiverse/core/theme/extensions/app_colors.dart';
import 'package:runiverse/core/theme/tokens/app_radius.dart';
import 'package:runiverse/core/theme/tokens/app_sizes.dart';
import 'package:runiverse/core/theme/tokens/app_spacing.dart';
import 'package:runiverse/core/theme/tokens/app_typography.dart';
import 'package:runiverse/features/profile/presentation/profile_avatar.dart';
import 'package:runiverse/features/profile/presentation/profile_provider.dart';

/// 프로필 헤더 — 아바타 · 닉네임 · 시그니처 컬러 · 팔로워/팔로잉.
///
/// ## 정본에서 뺀 것 둘
///
/// **컬러 밴드와 아우라를 그리지 않는다.** 아직 색을 모으지 않은 사람이 대부분이라
/// 밴드에 깔 색이 없다. ⚠️ 밴드를 빼면 **스크림도 함께 빠진다** — 스크림은
/// *러닝 색 위에 얹은 텍스트*의 대비를 지키는 장치지(디자인 시스템 §1-4),
/// 배경에 색이 없으면 어두운 판을 한 겹 더 까는 셈이라 오히려 탁해진다.
///
/// **대표 기록 대시보드도 뺐다.** 세 값이 전부 러닝 기록에서 나오는데 기록 기능이
/// 없다. 넣으면 `0 km · 상위 --%`가 나란히 서서 화면이 고장 난 것처럼 읽힌다.
class ProfileHeader extends ConsumerWidget {
  const ProfileHeader({
    this.nickname,
    this.introduction,
    this.isOnboarded = true,
    this.blendRunners = 0,
    this.photoUrl,
    super.key,
  });

  /// `null`인 이유가 **둘**이고, 화면은 그것을 갈라야 한다.
  ///
  /// ⚠️ 둘을 같이 다루면 **이미 프로필을 채운 사람에게 "프로필을 완성해주세요"가
  /// 뜬다** — `/users/me`가 잠깐 실패하기만 해도 그렇게 된다. 실제로 겪었다.
  final String? nickname;

  /// 프로필을 채운 사람인가. `nickname`이 없는 이유를 여기서 가른다.
  ///
  /// | `isOnboarded` | `nickname` | 그리는 것 |
  /// |---|---|---|
  /// | `false` | `null` | 채우라는 문구 |
  /// | `true` | `null` | **자리표시자** — 아직 못 불러왔을 뿐이다 |
  /// | `true` | 값 | 닉네임 |
  final bool isOnboarded;

  /// 한 줄 소개. 정본의 인사말("78일째…") 자리를 대신 쓴다 —
  /// 가입일을 서버가 주지 않아 날수를 셀 수 없다.
  final String? introduction;

  /// 서로 수락해 함께 달리는 사람 수. 서버 `friendCount`다.
  ///
  /// ⚠️ **눌리지 않는다.** 서버에 목록 API가 없다. 누를 수 있게 만들면
  /// 반응이 없을 때 고장으로 읽힌다. 자리만 잡아 둔다.
  final int blendRunners;

  /// 프로필 사진 열람 주소. 아바타에 그대로 내려보낸다 — [ProfileAvatar.url] 참조.
  final String? photoUrl;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.appColors;
    // 지역 변수로 받는다 — public 필드는 `!= null` 검사로 승격되지 않는다.
    final nickname = this.nickname;
    final introduction = this.introduction;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.space5,
        AppSpacing.space2,
        AppSpacing.space5,
        AppSpacing.space5,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ⚠️ 이 화면에서 값을 고치지 않는다. **바꾸는 자리는 편집 화면
          // 하나**다(정본 S22.1) — 홈에도 두면 같은 일을 하는 문이 둘이 되고,
          // 저장되는 시점이 서로 다른 것을 화면이 설명할 길이 없다.
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              _HeaderAction(
                icon: LucideIcons.pencil,
                // ⚠️ **돌아오면 다시 받아온다.** 편집 화면에서 사진·닉네임은
                // 누르는 자리에서 이미 저장됐고, 소개글은 저장 버튼으로 갔다.
                // 다시 받지 않으면 홈이 편집 전 값을 그린다.
                onTap: () async {
                  await context.push(AppRoutes.profileEdit);
                  await ref
                      .read(profileSummaryControllerProvider.notifier)
                      .load();
                },
              ),
              const SizedBox(width: AppSpacing.space2),
              // 설정 화면은 아직 없다. 눌리지 않는다.
              const _HeaderAction(icon: LucideIcons.settings),
            ],
          ),
          const SizedBox(height: AppSpacing.space2),

          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 홈에서는 눌리지 않는다. 사진을 바꾸는 자리도 편집 화면이다.
              ProfileAvatar(url: photoUrl),
              const SizedBox(width: AppSpacing.space4),

              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (nickname != null)
                      Text(
                        nickname,
                        style: AppTypography.h3.copyWith(
                          color: colors.textPrimary,
                        ),
                      )
                    else if (!isOnboarded)
                      Text(
                        AppStrings.profileNicknameEmpty,
                        // 아직 이름이 아니라 **할 일**이므로 무게를 낮춘다.
                        style: AppTypography.h3.copyWith(
                          color: colors.textSecondary,
                        ),
                      )
                    else
                      // 채운 사람인데 값이 아직 안 왔다. 문구를 넣지 않는다 —
                      // 무슨 말을 넣든 곧 사라질 말이고, 그 사이 잘못된 안내가 된다.
                      const _NicknamePlaceholder(),
                    if (introduction != null) ...[
                      const SizedBox(height: AppSpacing.space1),
                      Text(
                        introduction,
                        style: AppTypography.caption.copyWith(
                          color: colors.textSecondary,
                        ),
                      ),
                    ],
                    const SizedBox(height: AppSpacing.space2),
                    const SignatureColorRow(),
                    const SizedBox(height: AppSpacing.space3),
                    _BlendCount(count: blendRunners),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// 닉네임이 오기 전 자리. **높이를 미리 잡아 둔다** —
/// 값이 도착할 때 아래 줄들이 밀려 내려가면 화면이 한 번 튄다.
class _NicknamePlaceholder extends StatelessWidget {
  const _NicknamePlaceholder();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: AppTypography.h3.height! * AppTypography.h3.fontSize!,
      child: Align(
        alignment: Alignment.centerLeft,
        child: Container(
          width: AppSpacing.space10 * 2,
          height: AppSpacing.space3,
          decoration: BoxDecoration(
            color: context.appColors.bgElevated,
            borderRadius: AppRadius.sm,
          ),
        ),
      ),
    );
  }
}

/// 시그니처 컬러 한 줄 — `시그니처 컬러 │ 코발트 블루 ●`
///
/// [color]가 `null`이면 색을 아직 모으지 않은 사람이다. 구분선과 색 원을 그리지 않고
/// **초대 문구 하나만** 남긴다 — 빈 원을 그리면 "색이 있는데 못 불러왔다"로 읽힌다.
class SignatureColorRow extends StatelessWidget {
  const SignatureColorRow({this.color, this.name, super.key});

  final Color? color;
  final String? name;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final color = this.color;
    final name = this.name;

    if (color == null || name == null) {
      return Text(
        AppStrings.profileSignatureEmpty,
        style: AppTypography.micro.copyWith(color: colors.textTertiary),
      );
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          AppStrings.profileSignatureLabel,
          style: AppTypography.micro.copyWith(color: colors.textSecondary),
        ),
        Container(
          width: 1,
          height: AppSpacing.space3,
          margin: const EdgeInsets.symmetric(horizontal: AppSpacing.space2),
          color: colors.borderStrong,
        ),
        Text(
          name,
          style: AppTypography.micro.copyWith(color: colors.textPrimary),
        ),
        const SizedBox(width: AppSpacing.space1),
        Container(
          width: AppSpacing.space2,
          height: AppSpacing.space2,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
      ],
    );
  }
}

/// 블렌드 러너 수. **`InkWell`을 두지 않는다** — 위 ⚠️ 참조.
class _BlendCount extends StatelessWidget {
  const _BlendCount({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '$count',
          // 숫자가 늘어도 라벨이 흔들리지 않게 tabular를 쓴다.
          style: AppTypography.body.copyWith(
            color: colors.textPrimary,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(width: AppSpacing.space1),
        Text(
          AppStrings.profileBlendRunners,
          style: AppTypography.caption.copyWith(color: colors.textSecondary),
        ),
      ],
    );
  }
}

/// 헤더 우상단 원형 버튼. 화면이 아직 없어 **눌리지 않는다.**
class _HeaderAction extends StatelessWidget {
  const _HeaderAction({required this.icon, this.onTap});

  final IconData icon;

  /// `null`이면 눌리지 않는다. 화면이 아직 없는 버튼이 그렇다.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    final button = Container(
      width: AppSizes.touchDefault,
      height: AppSizes.touchDefault,
      decoration: BoxDecoration(
        color: colors.bgSurface,
        borderRadius: AppRadius.full,
        border: Border.all(color: colors.borderDefault),
      ),
      child: Icon(icon, size: AppSpacing.space5, color: colors.textSecondary),
    );

    final onTap = this.onTap;
    if (onTap == null) return button;

    return GestureDetector(onTap: onTap, child: button);
  }
}
