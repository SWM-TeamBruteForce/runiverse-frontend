import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:runiverse/core/strings/app_strings.dart';
import 'package:runiverse/core/theme/tokens/app_spacing.dart';
import 'package:runiverse/core/theme/tokens/run_palette.dart';
import 'package:runiverse/core/widgets/empty_state_card.dart';
import 'package:runiverse/features/auth/presentation/auth_provider.dart';
import 'package:runiverse/features/auth/presentation/auth_state.dart';
import 'package:runiverse/features/profile/presentation/basic_collection.dart';
import 'package:runiverse/features/profile/presentation/profile_header.dart';

/// 프로필 탭 (S22, 본인).
///
/// ⚠️ 번호를 헷갈리기 쉽다 — **S22가 본인, S20이 타인**이다. Figma 페이지 이름이
/// `S20–S21`이라 더 헷갈린다. 타인 프로필은 레이아웃이 같고 액션만 다르므로
/// 이 위젯을 조건부로 재사용한다.
///
/// ## 값은 `GET /users/me`에서 온다
///
/// 화면이 직접 부르지 않는다. `AuthController`가 앱에 들어올 때마다 이미 부르고
/// 그 답을 [AuthSignedIn.user]에 담아 둔다(`docs/implementation-notes.md` §9-3-2).
/// **여기서 또 부르면 같은 요청이 두 번 나가고, 두 값이 어긋날 자리가 생긴다.**
///
/// ## 프로필이 없으면 여기까지 오지 못한다
///
/// `AppShell`이 관문으로 막아선다. 그래서 이 화면의 빈 상태는 **거의 보이지
/// 않는다** — 딥링크처럼 관문을 지나치는 길에 대비해 남겨 둔 것이다.
class ProfilePage extends ConsumerWidget {
  const ProfilePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authControllerProvider);
    final signedIn = auth is AuthSignedIn ? auth : null;
    final user = signedIn?.user;

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ProfileHeader(
                nickname: user?.nickname,
                introduction: user?.introduction,
                // ⚠️ 닉네임이 없는 이유를 헤더가 갈라야 한다. 이 값을 빼면
                // `/users/me`가 잠깐 실패하는 것만으로 **이미 프로필을 채운
                // 사람에게 "완성해주세요"가 뜬다.**
                isOnboarded: signedIn?.isOnboarded ?? true,
              ),

              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.space5,
                  0,
                  AppSpacing.space5,
                  AppSpacing.space8,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    ProfileSectionTitle(
                      title: AppStrings.profileBasicCollection,
                      trailing: AppStrings.profileCollected(
                        0,
                        RunHue.values.length * RunPalette.shadeCount,
                      ),
                      hint: AppStrings.profileCollectionHint,
                    ),
                    const SizedBox(height: AppSpacing.space4),
                    const ProfileSectionCard(child: BasicCollection()),
                    const SizedBox(height: AppSpacing.space7),

                    ProfileSectionTitle(
                      title: AppStrings.profileBlendCollection,
                      trailing: AppStrings.profileBlendCount(0),
                    ),
                    const SizedBox(height: AppSpacing.space3),
                    const EmptyStateCard(
                      icon: LucideIcons.blend,
                      message: AppStrings.profileBlendEmpty,
                      hint: AppStrings.profileBlendEmptyHint,
                    ),
                    const SizedBox(height: AppSpacing.space7),

                    const ProfileSectionTitle(title: AppStrings.profileFeed),
                    const SizedBox(height: AppSpacing.space3),
                    const EmptyStateCard(
                      icon: LucideIcons.image,
                      message: AppStrings.profileFeedEmpty,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
