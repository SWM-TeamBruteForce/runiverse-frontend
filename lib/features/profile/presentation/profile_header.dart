import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:runiverse/app/router/app_routes.dart';
import 'package:runiverse/core/strings/app_strings.dart';
import 'package:runiverse/core/theme/v2/app_colors.dart';
import 'package:runiverse/core/theme/v2/app_radius.dart';
import 'package:runiverse/core/theme/v2/app_sizes.dart';
import 'package:runiverse/core/theme/v2/app_spacing.dart';
import 'package:runiverse/core/theme/v2/app_typography.dart';
import 'package:runiverse/core/widgets/v2/app_button.dart';
import 'package:runiverse/core/widgets/v2/app_icon.dart';
import 'package:runiverse/features/profile/presentation/profile_avatar.dart';
import 'package:runiverse/features/profile/presentation/profile_provider.dart';

/// 프로필 헤더 — 아바타 · 닉네임 · 한 줄 소개. 시안 `158:3905`.
///
/// ## ⚠️ 시안에 있는데 여기 없는 것
///
/// 2026-10-05에 **컬러 · 뱃지 · 팔로워/팔로잉을 일단 뺐다**(요청). 시안은
/// 닉네임 아래에 `팔로워 · 24` `팔로우 · 32` `컬러 · 1/30` `뱃지 · 1/10`
/// 네 줄을 세우고, 그 아래를 도감이 채운다.
///
/// 빼고 보면 남는 것이 아바타 · 닉네임 · 소개뿐이다. **화면이 비는 것은
/// 알고 둔 것이다** — 그 자리에 도감이 들어온다.
///
/// 데이터가 없어 못 넣은 것도 셋이다.
///
/// - **커버 사진**(`158:3910`, 412×200) — `ProfileSummary`에 필드가 없다
/// - **알림 벨**(`158:3935`) — 알림을 보낼 채널이 아직 없다. 눌러도 가는 곳이
///   없는 버튼은 고장으로 읽힌다
/// - **닉네임 옆 인증 배지**(`158:3915`) — `AppIcons.verified` 글리프는 있지만
///   인증이라는 **개념**이 앱에도 서버에도 없다
///
/// ## 시안 치수를 그대로 못 쓴 곳
///
/// | 시안 | 여기 | 왜 |
/// |---|---|---|
/// | 좌우 여백 14 | `space4`(16) | 14는 토큰이 아니다. 가장 가까운 토큰이다 |
/// | 편집 버튼 높이 41 | 56 | **41은 44 미만이라 애초에 못 쓴다.** [AppButtonV2]가 한 높이만 갖는다 |
/// | 설정 버튼 41 | 44 | 같은 이유. 글리프만 줄인다(`AppSizes` 주석) |
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
    final colors = context.appColorsV2;
    // 지역 변수로 받는다 — public 필드는 `!= null` 검사로 승격되지 않는다.
    final nickname = this.nickname;
    final introduction = this.introduction;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.space4,
        AppSpacing.space2,
        AppSpacing.space4,
        AppSpacing.space5,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 시안 `158:3938` 자리. 벨(`158:3935`)은 위 ⚠️ 참조.
          Align(
            alignment: Alignment.centerRight,
            child: _RoundAction(
              icon: AppIcons.settings,
              label: AppStrings.settingsTitle,
              // 편집과 달리 **돌아와서 다시 받아오지 않는다.** 설정은 프로필
              // 요약(닉네임·사진·소개글)을 건드리지 않는다.
              onTap: () => context.push(AppRoutes.settings),
            ),
          ),
          const SizedBox(height: AppSpacing.space2),

          Row(
            // 시안은 버튼 아래끝이 아바타보다 조금 더 내려와 있다. 한 줄로
            // 맞출 수 있는 가장 가까운 정렬이 아래 맞춤이다.
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              // 이 화면에서는 눌리지 않는다. 사진을 바꾸는 자리도 편집 화면이다.
              ProfileAvatar(url: photoUrl),
              const Spacer(),

              // ⚠️ 시안에서 **아이콘이 아니라 글자 버튼**이다(`158:3933`).
              // 연필 하나로는 무엇을 고치는지 알 수 없다.
              //
              // ⚠️ **돌아오면 다시 받아온다.** 편집 화면에서 사진·닉네임은
              // 누르는 자리에서 이미 저장됐고, 소개글은 저장 버튼으로 갔다.
              // 다시 받지 않으면 이 화면이 편집 전 값을 그린다.
              AppButtonV2(
                label: AppStrings.profileEditOpen,
                expand: false,
                onPressed: () async {
                  await context.push(AppRoutes.profileEdit);
                  await ref
                      .read(profileSummaryControllerProvider.notifier)
                      .load();
                },
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.space4),

          if (nickname != null)
            Text(
              nickname,
              style: AppTypographyV2.body01.copyWith(color: colors.textStrong),
            )
          else if (!isOnboarded)
            Text(
              AppStrings.profileNicknameEmpty,
              // 아직 이름이 아니라 **할 일**이므로 무게를 낮춘다.
              style: AppTypographyV2.body01.copyWith(
                color: colors.textSecondary,
              ),
            )
          else
            // 채운 사람인데 값이 아직 안 왔다. 문구를 넣지 않는다 —
            // 무슨 말을 넣든 곧 사라질 말이고, 그 사이 잘못된 안내가 된다.
            const _NicknamePlaceholder(),

          if (introduction != null) ...[
            const SizedBox(height: AppSpacing.space2),
            Text(
              introduction,
              // ⚠️ **시안보다 밝다.** 시안은 40% 흰색인데 `#0a0a0a` 위에서
              // 3.45:1 이라 본문 기준(4.5:1)에 못 미친다. 본인이 쓴 글이라
              // 읽히는 쪽을 골랐다 — 디자인 확인이 필요하다.
              style: AppTypographyV2.body11.copyWith(
                color: colors.textSecondary,
              ),
            ),
          ],
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
    final style = AppTypographyV2.body01;

    return SizedBox(
      height: style.height! * style.fontSize!,
      child: Align(
        alignment: Alignment.centerLeft,
        child: Container(
          width: AppSpacing.space10 * 2,
          height: AppSpacing.space3,
          decoration: BoxDecoration(
            color: context.appColorsV2.bgElevated,
            borderRadius: AppRadius.sm,
          ),
        ),
      ),
    );
  }
}

/// 헤더 우상단 원형 버튼 — 시안 `158:3938`.
///
/// ⚠️ **시안은 41이지만 44로 그린다.** 44 미만은 손가락이 빗나간다
/// (`AppSizes` 주석). 글리프만 시안 크기에 맞춰 줄인다.
///
/// ⚠️ **글자가 없으므로 [Semantics]를 반드시 붙인다.** 안 붙이면 스크린리더가
/// 읽을 것이 없다 — 탭 바에서 같은 실수를 한 적이 있다.
class _RoundAction extends StatelessWidget {
  const _RoundAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final String icon;
  final String label;
  final VoidCallback onTap;

  /// 시안은 21. 24는 이 원 안에서 꽉 차 보인다.
  static const _glyph = AppSpacing.space5;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColorsV2;

    return MergeSemantics(
      child: Semantics(
        label: label,
        button: true,
        child: Material(
          // 시안은 흰색 20%에 블러를 먹인 유리다(`backdrop-blur-[10px]`).
          // **커버 사진이 없으니 블러할 것이 없다** — 같은 결을 내는 토큰을 쓴다.
          color: colors.bgGlass,
          shape: const CircleBorder(),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: SizedBox(
              width: AppSizes.touchDefault,
              height: AppSizes.touchDefault,
              child: Center(
                child: AppIcon(icon, size: _glyph, color: colors.textPrimary),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
