import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runiverse/app/app.dart';
import 'package:runiverse/app/router/app_routes.dart';
import 'package:runiverse/core/strings/app_strings.dart';
import 'package:runiverse/core/widgets/v2/action_tile.dart';
import 'package:runiverse/features/auth/presentation/auth_provider.dart';
import 'package:runiverse/features/auth/presentation/auth_state.dart';
import 'package:runiverse/features/home/presentation/home_hero.dart';
import 'package:runiverse/features/matching/data/fake_match_repository.dart';
import 'package:runiverse/features/matching/presentation/match_register_page.dart';
import 'package:runiverse/features/matching/presentation/match_register_provider.dart';
import 'package:runiverse/features/onboarding/presentation/profile_setup_page.dart';
import 'package:runiverse/features/session/data/fake_user_status_repository.dart';
import 'package:runiverse/features/session/presentation/user_status_provider.dart';

/// 홈 (S05 상태 1) — 무엇이 보이고, 히어로의 두 버튼이 어디로 가는가.
void main() {
  Future<void> pumpHome(WidgetTester tester, {AuthState? auth}) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          // 매칭 버튼이 등록 화면으로 간다. 그 화면이 들어서면서 시간대를
          // 받아오는데, 진짜를 두면 dio가 서버 주소를 찾다 죽는다.
          matchRepositoryProvider.overrideWithValue(FakeMatchRepository()),
          // 로그인한 상태로 들어오면 셸이 세워지면서 유저 상태를 한 번 묻는다.
          // 진짜를 두면 여기서도 dio가 서버 주소를 찾다 죽는다.
          userStatusRepositoryProvider.overrideWithValue(
            FakeUserStatusRepository(),
          ),
          if (auth != null)
            authControllerProvider.overrideWith(
              () => _StubAuthController(auth),
            ),
        ],
        child: const RuniverseApp(initialLocation: AppRoutes.home),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('히어로', () {
    testWidgets('매칭 버튼이 있다', (tester) async {
      await pumpHome(tester);

      expect(find.byType(HomeHero), findsOneWidget);
      expect(find.text(AppStrings.homeMatchCta), findsOneWidget);
    });

    // ⚠️ **`시간대 인사`가 빠졌다.** 시안 `158:2848`이 인사 대신 이름을
    // 부른다(`김지원님`). `GreetingRule`은 도메인에 그대로 남아 있다.
  });

  group('아래 두 칸', () {
    // 시안이 솔로·동행을 히어로 밖 칸 둘로 옮겼다(`158:2875` `158:2881`).

    testWidgets('두 칸이 다 있다', (tester) async {
      await pumpHome(tester);

      expect(find.byType(ActionTileV2), findsNWidgets(2));
      expect(find.text(AppStrings.homeSoloCta), findsOneWidget);
      expect(find.text(AppStrings.homeWithFriendCta), findsOneWidget);
    });

    testWidgets('매칭을 누르면 등록 화면으로 간다', (tester) async {
      // 홈에서 바로 신청하면 시간대도 거리도 정할 수 없다. S08을 거친다.
      await pumpHome(tester);

      await tester.tap(find.text(AppStrings.homeMatchCta));
      await tester.pumpAndSettle();

      expect(find.byType(MatchRegisterPage), findsOneWidget);
    });

    testWidgets('1인 러닝을 누르면 출발 준비로 간다', (tester) async {
      // 준비 화면을 거치는 것이 이 버튼의 계약이다. 바로 러닝으로 보내면
      // GPS 첫 신호를 기다릴 자리가 없어 초반 거리가 통째로 빠진다.
      await pumpHome(tester);

      await tester.tap(find.text(AppStrings.homeSoloCta));
      await tester.pumpAndSettle();

      expect(find.text(AppStrings.runWaitingFix), findsOneWidget);
    });
  });

  group('⚠️ 시안에서 빠진 것', () {
    testWidgets('대회와 최근 러닝 섹션이 없다', (tester) async {
      // 시안 홈(`158:2848`)에 두 섹션이 없다. 대회일정 탭을 뺀 결정(#106)과
      // 같은 방향이고, **기능을 지운 것**이라 여기서 못 박는다 — 누가
      // 되살리면 시안과 어긋난 채로 조용히 굴러간다.
      await pumpHome(tester);

      // `EmptyStateCard` 를 찾던 줄이 있었는데, 그 위젯을 지우면서 뺐다.
      // ⚠️ **없어진 타입을 찾는 `findsNothing` 은 늘 통과한다** — 지키는 것이
      // 없었다. 아래 두 줄이 의도를 지킨다.
      expect(find.text('다가오는 대회'), findsNothing);
      expect(find.text('최근 러닝'), findsNothing);
    });
  });

  group('프로필 관문', () {
    testWidgets('⚠️ 온보딩을 안 마쳤으면 관문이 막아선다', (tester) async {
      await pumpHome(
        tester,
        auth: const AuthSignedIn('u-1', isOnboarded: false),
      );

      // 유도 카드를 대신한 것이다. 카드는 지나칠 수 있었지만 이것은 아니다 —
      // 프로필 없이는 매칭도 기록도 돌아가지 않는다.
      expect(find.text(AppStrings.profileSheetCta), findsOneWidget);
    });

    testWidgets('온보딩을 마쳤으면 막아서지 않는다', (tester) async {
      await pumpHome(
        tester,
        auth: const AuthSignedIn('u-1', isOnboarded: true),
      );

      expect(find.text(AppStrings.profileSheetCta), findsNothing);
    });

    testWidgets('로그인 상태를 모를 때도 막아서지 않는다', (tester) async {
      // 스플래시를 거치지 않고 홈에 바로 온 경우다. 모르는 상태에서 막아서면
      // 이미 프로필을 채운 사람도 잠깐 갇힌다.
      await pumpHome(tester, auth: const AuthUnknown());

      expect(find.text(AppStrings.profileSheetCta), findsNothing);
    });

    testWidgets('관문의 CTA는 프로필 등록으로 간다', (tester) async {
      await pumpHome(
        tester,
        auth: const AuthSignedIn('u-1', isOnboarded: false),
      );

      await tester.tap(find.text(AppStrings.profileSheetCta));
      await tester.pumpAndSettle();

      expect(find.byType(ProfileSetupPage), findsOneWidget);
    });

    testWidgets('⚠️ 스크림을 눌러도 닫히지 않는다', (tester) async {
      await pumpHome(
        tester,
        auth: const AuthSignedIn('u-1', isOnboarded: false),
      );

      // 화면 맨 위(시트 밖)를 누른다. 보통 바텀시트는 여기서 닫힌다.
      await tester.tapAt(const Offset(200, 40));
      await tester.pumpAndSettle();

      // 닫히면 프로필 없는 사람이 앱을 그냥 쓰게 된다.
      expect(find.text(AppStrings.profileSheetCta), findsOneWidget);
    });
  });
}

/// 상태를 고정한 컨트롤러.
///
/// `signIn()`으로 상태를 만들면 안 된다 — `testWidgets`는 가짜 시간 위에서 도는데
/// `pumpWidget` 전에 Future를 기다리면 시간을 진행시킬 `pump`가 없어 **테스트가 멈춘다.**
/// 여기서 보는 것은 화면이 주어진 상태를 어떻게 그리는가뿐이다.
class _StubAuthController extends AuthController {
  _StubAuthController(this.initial);

  final AuthState initial;

  @override
  AuthState build() => initial;
}
