import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:runiverse/app/router/app_routes.dart';
import 'package:runiverse/core/strings/app_strings.dart';
import 'package:runiverse/core/theme/tokens/app_spacing.dart';
import 'package:runiverse/core/theme/tokens/run_palette.dart';
import 'package:runiverse/core/widgets/empty_state_card.dart';
import 'package:runiverse/features/auth/presentation/auth_provider.dart';
import 'package:runiverse/features/auth/presentation/auth_state.dart';
import 'package:runiverse/features/profile/presentation/basic_collection.dart';
import 'package:runiverse/features/profile/presentation/profile_header.dart';
import 'package:runiverse/features/profile/presentation/profile_prompt_sheet.dart';

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
/// ## 프로필이 없으면 시트가 뜬다
///
/// [AuthSignedIn.isOnboarded]가 `false`면 유도 시트를 한 번 띄운다.
/// 닫으면 다시 띄우지 않는다 — 같은 화면에서 두 번 막아서면 안내가 아니라 벽이다.
class ProfilePage extends ConsumerStatefulWidget {
  const ProfilePage({super.key});

  @override
  ConsumerState<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends ConsumerState<ProfilePage> {
  /// 이번 방문에 시트를 이미 띄웠는가.
  ///
  /// 없으면 화면이 다시 그려질 때마다 시트가 쌓인다 — `build`는 한 번만 불리는
  /// 자리가 아니다.
  bool _promptShown = false;

  /// 아직 프로필이 없으면 유도 시트를 띄운다.
  ///
  /// `build` 중에 `showModalBottomSheet`를 부를 수 없다(그리는 도중에 트리를
  /// 바꾸는 셈이다). 첫 프레임이 끝난 뒤로 미룬다.
  void _promptIfNeeded(bool isOnboarded) {
    if (isOnboarded || _promptShown) return;
    _promptShown = true;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      showProfilePromptSheet(
        context,
        // **첫 로그인 때와 같은 화면**을 연다. 프로필을 받는 곳이 둘이면
        // 규칙도 둘이 되고, 한쪽만 고치는 사고가 난다.
        //
        // `push`라 뒤로가기로 프로필 탭에 돌아온다. 인증 직후에는 `go`로
        // 열리지만 그때는 돌아갈 곳이 없다 — 같은 화면, 다른 진입이다.
        onStart: () => context.push(AppRoutes.profileSetup),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authControllerProvider);
    final signedIn = auth is AuthSignedIn ? auth : null;
    final user = signedIn?.user;

    // ⚠️ `AuthUnknown`이면 띄우지 않는다. 모르는 상태에서 띄우면 이미 프로필을
    // 채운 사람에게도 잠깐 뜬다 — 홈의 유도 카드와 같은 규칙이다.
    if (signedIn != null) _promptIfNeeded(signedIn.isOnboarded);

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
