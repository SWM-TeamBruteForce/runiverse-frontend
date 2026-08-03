import 'package:go_router/go_router.dart';
import 'package:runiverse/app/router/app_routes.dart';
import 'package:runiverse/app/router/app_shell.dart';
import 'package:runiverse/core/strings/app_strings.dart';
import 'package:runiverse/core/widgets/coming_soon_page.dart';
import 'package:runiverse/features/home/presentation/home_page.dart';
import 'package:runiverse/features/profile/presentation/profile_page.dart';
import 'package:runiverse/features/record/presentation/record_page.dart';

/// 라우터 조립 — 앱의 화면 목록이자 딥링크 표.
///
/// ## branch 하나 = 탭 하나
///
/// [StatefulShellRoute.indexedStack]은 branch마다 독립된 [Navigator]를 만든다.
/// 기록 탭에서 상세로 3단계 들어갔다가 홈에 갔다 돌아와도 그 3단계가 남아 있다.
/// **branch 순서는 `AppShell._tabs` 순서와 같아야 한다.** 어긋나면 엉뚱한 탭이 열린다.
///
/// 탭 안쪽 화면(예: 기록 상세)은 해당 branch의 `routes`에 자식으로 추가한다.
/// 그러면 탭 바를 유지한 채 그 위에 쌓인다.
///
/// ## 함수인 이유
///
/// 전역 `final`로 두면 테스트마다 같은 라우터를 재사용해 이전 테스트의 이동 이력이
/// 다음 테스트로 샌다. 호출할 때마다 새로 만든다.
///
/// ## 아직 안 한 것
///
/// - **로그인 리다이렉트** — 인증이 붙으면 `redirect`를 단다.
///   그때 `redirect` 안에서 `ref.watch`를 쓰면 무한 리빌드가 난다.
///   `refreshListenable`을 쓴다 (`docs/implementation-notes.md` §5-2).
/// - **탭 바를 덮는 전체 화면** — 러닝 중 화면(S11~S13)은 탭 바 위를 덮어야 한다.
///   그때 루트 `navigatorKey`를 만들고 해당 `GoRoute`에 `parentNavigatorKey`로 넘긴다.
GoRouter createAppRouter() {
  return GoRouter(
    // 플랫폼이 넘겨주는 기본 경로 `/`를 이 값으로 대체한다.
    initialLocation: AppRoutes.home,
    routes: [
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) =>
            AppShell(navigationShell: navigationShell),
        branches: [
          // 0 · 홈 (S05)
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppRoutes.home,
                builder: (context, state) => const HomePage(),
              ),
            ],
          ),

          // 1 · 기록 (S21)
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppRoutes.record,
                builder: (context, state) => const RecordPage(),
              ),
            ],
          ),

          // 2 · 피드 — 화면이 생기면 여기만 갈아끼운다.
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppRoutes.feed,
                builder: (context, state) =>
                    const ComingSoonPage(featureName: AppStrings.tabFeed),
              ),
            ],
          ),

          // 3 · 대회일정 — 화면이 생기면 여기만 갈아끼운다.
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppRoutes.competition,
                builder: (context, state) => const ComingSoonPage(
                  featureName: AppStrings.tabCompetition,
                ),
              ),
            ],
          ),

          // 4 · 프로필 (S20)
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppRoutes.profile,
                builder: (context, state) => const ProfilePage(),
              ),
            ],
          ),
        ],
      ),
    ],
  );
}
