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

/// 프로필 헤더 — 아바타 · 닉네임 · 한 줄 소개.
///
/// ## ⚠️ 시안에 있는데 여기 없는 것
///
/// 2026-10-05에 **컬러 · 뱃지 · 팔로워/팔로잉을 일단 뺐다**(요청). 시안
/// `158:3905`는 닉네임 아래에 `팔로워 · 24` `팔로우 · 32` `컬러 · 1/30`
/// `뱃지 · 1/10` 네 줄을 세우고, 그 아래를 도감이 채운다.
///
/// 빼고 보면 남는 것이 아바타 · 닉네임 · 소개뿐이다. **화면이 비는 것은
/// 알고 둔 것이다** — 그 자리에 도감이 들어온다.
///
/// 그 밖에 시안과 다른 것:
///
/// - **커버 사진이 없다.** `ProfileSummary`에 필드가 없다 — 서버가 주지 않는다
/// - **알림 벨이 없다.** 알림을 보낼 채널이 아직 없어, 눌러도 가는 곳이 없다
/// - **닉네임 옆 인증 배지가 없다.** 인증이라는 개념이 앱에도 서버에도 없다
class ProfileHeader extends ConsumerWidget {
  const ProfileHeader({
    this.nickname,
    this.introduction,
    this.isOnboarded = true,
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
              // 편집과 달리 **돌아와서 다시 받아오지 않는다.** 설정은 프로필
              // 요약(닉네임·사진·소개글)을 건드리지 않는다.
              _HeaderAction(
                icon: LucideIcons.settings,
                onTap: () => context.push(AppRoutes.settings),
              ),
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
