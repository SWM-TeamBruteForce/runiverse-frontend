import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:runiverse/core/theme/v2/app_colors.dart';
import 'package:runiverse/core/theme/v2/app_spacing.dart';
import 'package:runiverse/features/auth/presentation/auth_provider.dart';
import 'package:runiverse/features/auth/presentation/auth_state.dart';
import 'package:runiverse/features/profile/presentation/profile_header.dart';
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
      if (mounted) ref.read(profileSummaryControllerProvider.notifier).load();
    });
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authControllerProvider);
    final signedIn = auth is AuthSignedIn ? auth : null;
    final summary = ref.watch(profileSummaryControllerProvider).summary;

    return Scaffold(
      // ⚠️ 위와 같은 이유로 바탕을 직접 깐다. **이 파일은 v2 색을 쓰지 않아
      // `v2_screen_background_test`가 검사 대상으로 보지도 않았다** —
      // 에뮬레이터에서 화소를 재고서야 `#0b0e14`인 것을 찾았다.
      backgroundColor: context.appColorsV2.bgBase,
      body: SafeArea(
        bottom: false,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
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
              // 여기 있던 `기본 컬러 도감` · `블렌드 컬렉션` · `피드` 셋을
              // 2026-10-05에 걷어냈다(요청). 시안 `158:3905`도 이 자리를 도감이
              // 채우므로, 컬러 · 뱃지가 들어오면 그대로 되살아난다
              // (`basic_collection.dart`를 지우지 않고 세워 둔 이유다).
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
    );
  }
}
