import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:runiverse/app/router/app_routes.dart';
import 'package:runiverse/core/strings/app_strings.dart';
import 'package:runiverse/core/theme/v2/app_colors.dart';
import 'package:runiverse/core/theme/v2/app_spacing.dart';
import 'package:runiverse/features/auth/presentation/auth_provider.dart';
import 'package:runiverse/features/auth/presentation/auth_state.dart';
import 'package:runiverse/core/widgets/v2/app_icon.dart';
import 'package:runiverse/features/profile/presentation/profile_cover.dart';
import 'package:runiverse/features/profile/presentation/profile_cover_action.dart';
import 'package:runiverse/features/profile/presentation/profile_header.dart';
import 'package:runiverse/features/profile/presentation/background_image_provider.dart';
import 'package:runiverse/features/profile/presentation/profile_provider.dart';

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
class ProfilePage extends ConsumerStatefulWidget {
  const ProfilePage({super.key});

  @override
  ConsumerState<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends ConsumerState<ProfilePage> {
  @override
  void initState() {
    super.initState();
    // 화면이 열릴 때 묻는다. `initState`에서 provider를 바로 고치면 빌드 중
    // 상태를 바꾸게 되어 죽는다(`docs/implementation-notes.md` §10-1).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(profileSummaryControllerProvider.notifier).load();
      // ⚠️ **배경은 요약에 없다.** 프로필 사진 주소는 `GET /users/me`에 얹혀
      // 오지만 배경 조회는 API가 따로다(1.1.1 가이드 4절) — 여기서 안 부르면
      // 커버가 영영 기본 배경으로 남는다.
      ref.read(backgroundImageControllerProvider.notifier).load();
    });
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authControllerProvider);
    final signedIn = auth is AuthSignedIn ? auth : null;
    final summary = ref.watch(profileSummaryControllerProvider).summary;

    // ⚠️ **이 화면에서만 상태바 글자를 밝게 고정한다.**
    //
    // 상태바 자리에는 어두운 바탕(`bgBase`)이 선다. 기기가 아이콘을 어둡게
    // 잡아 둔 상태라면 어두운 아이콘 + 어두운 바탕이 되어 시계·배터리가
    // 그대로 사라진다.
    //
    // ⚠️ **앱 전체에 걸지 않는다.** 다른 화면은 지금 바탕에 맞춰 알아서 간다.
    // `AnnotatedRegion`이라 이 화면을 떠나면 저절로 돌아온다.
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        // ⚠️ 위와 같은 이유로 바탕을 직접 깐다. **이 파일은 v2 색을 쓰지 않아
        // `v2_screen_background_test`가 검사 대상으로 보지도 않았다** —
        // 에뮬레이터에서 화소를 재고서야 `#0b0e14`인 것을 찾았다.
        backgroundColor: context.appColorsV2.bgBase,
        // ⚠️ **위 여백을 받는다 — 커버를 상태바 뒤로 올리지 않는다.**
        //
        // 시안(`158:3905`)은 커버와 상태바 틀을 같은 자리에서 시작하고, 그렇게
        // 두려면 흰 시계·배터리를 지킬 **그늘막**이 사진 위에 필요했다. 그
        // 그늘막이 기기에서 **사진 윗부분을 가리는 회색 막대**로 보였다
        // (2026-10-23). 커버를 상태바 아래로 내리면 둘 다 없어도 된다.
        body: SafeArea(
          bottom: false,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // ⚠️ **설정 버튼이 커버 위에 선다**(시안 `158:3938`, y=54).
                // 2026-10-22에는 "밝은 사진에서 흰 아이콘이 안 보인다"며 커버
                // 아래로 내렸는데, 시안이 쓰던 **어두운 원**을 함께 가져오면서
                // 그 이유가 사라졌다(`ProfileCoverAction`).
                //
                // 커버와 겹쳐야 하므로 `Stack`이다. 커버는 그대로 두고 화면이
                // 얹는다 — 커버가 라우팅을 알 이유가 없다.
                Stack(
                  children: [
                    const ProfileCover(),
                    Positioned(
                      // 상태바를 피할 여백은 위의 `SafeArea`가 이미 받았다.
                      // 여기 값은 **커버 안쪽 간격**이다.
                      top: AppSpacing.space2,
                      right: AppSpacing.space4,
                      child: ProfileCoverAction(
                        icon: AppIcons.settings,
                        label: AppStrings.settingsTitle,
                        // 편집과 달리 **돌아와서 다시 받아오지 않는다.** 설정은
                        // 프로필 요약(닉네임·사진·소개글)을 건드리지 않는다.
                        onTap: () => context.push(AppRoutes.settings),
                      ),
                    ),
                  ],
                ),
                ProfileHeader(
                  nickname: summary?.nickname,
                  introduction: summary?.introduction,
                  photoUrl: summary?.profileImageUrl,
                  // ⚠️ 닉네임이 없는 이유를 헤더가 갈라야 한다. 이 값을 빼면
                  // `/users/me`가 잠깐 실패하는 것만으로 **이미 프로필을 채운
                  // 사람에게 "완성해주세요"가 뜬다.**
                  isOnboarded: signedIn?.isOnboarded ?? true,
                ),

                // ⚠️ **본문이 비어 있다. 빠뜨린 것이 아니다.**
                //
                // 여기 있던 `기본 컬러 도감` · `블렌드` · `피드` 셋을
                // 걷어냈다. 색 수집 기능은 범위에서 빠졌고(2026-10-15), 대표 기록
                // 대시보드와 피드는 받을 API가 없다. 시안 `158:3905`가 이 자리를
                // 도감으로 채우므로 **시안을 보고 작업하다 되살리기 쉽다.**
                //
                // ⚠️ **바닥 여백에 탭 바 높이를 더한다.** 위의
                // `SafeArea(bottom: false)`가 시스템 여백을 일부러 안 받기 때문에,
                // 그냥 두면 맨 아래가 떠 있는 탭 바 뒤로 들어간다.
                SizedBox(
                  height:
                      AppSpacing.space8 + MediaQuery.paddingOf(context).bottom,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
