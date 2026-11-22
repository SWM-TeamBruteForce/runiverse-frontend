import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:runiverse/app/router/app_routes.dart';
import 'package:runiverse/app/router/app_shell.dart';
import 'package:runiverse/features/auth/presentation/sign_in_page.dart';
import 'package:runiverse/features/auth/presentation/sign_up_page.dart';
import 'package:runiverse/features/friend/presentation/friend_page.dart';
import 'package:runiverse/features/matching/presentation/invite_register_page.dart';
import 'package:runiverse/features/notification/presentation/notification_page.dart';
import 'package:runiverse/features/profile/presentation/user_friends_page.dart';
import 'package:runiverse/features/profile/presentation/user_profile_page.dart';
import 'package:runiverse/features/home/presentation/home_page.dart';
import 'package:runiverse/features/matching/presentation/match_countdown_page.dart';
import 'package:runiverse/features/matching/presentation/match_register_page.dart';
import 'package:runiverse/features/chat/presentation/chat_page.dart';
import 'package:runiverse/features/matching/presentation/match_room_page.dart';
import 'package:runiverse/features/onboarding/presentation/onboarding_intro_page.dart';
import 'package:runiverse/features/onboarding/presentation/profile_setup_page.dart';
import 'package:runiverse/features/onboarding/presentation/splash_page.dart';
import 'package:runiverse/features/onboarding/presentation/terms_agreement_page.dart';
import 'package:runiverse/features/profile/presentation/profile_cards_page.dart';
import 'package:runiverse/features/profile/presentation/profile_edit_page.dart';
import 'package:runiverse/features/profile/presentation/profile_page.dart';
import 'package:runiverse/features/record/presentation/record_page.dart';
import 'package:runiverse/features/record_card/domain/record_card.dart';
import 'package:runiverse/features/record_card/presentation/card_compose_page.dart';
import 'package:runiverse/features/record_card/presentation/card_detail_page.dart';
import 'package:runiverse/features/record_card/presentation/card_draft_provider.dart';
import 'package:runiverse/features/record_card/presentation/card_photo_page.dart';
import 'package:runiverse/features/record_card/presentation/card_publish_page.dart';
import 'package:runiverse/features/record_card/presentation/record_card_page.dart';
import 'package:runiverse/features/session/presentation/run_prepare_page.dart';
import 'package:runiverse/features/session/presentation/run_session_page.dart';
import 'package:runiverse/features/record/presentation/record_detail_page.dart';
import 'package:runiverse/features/session/presentation/run_summary_page.dart';
import 'package:runiverse/features/settings/presentation/password_change_page.dart';
import 'package:runiverse/features/settings/presentation/settings_page.dart';

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
GoRouter createAppRouter({String? initialLocation}) {
  return GoRouter(
    // 플랫폼이 넘겨주는 기본 경로 `/`를 이 값으로 대체한다.
    initialLocation: initialLocation ?? AppRoutes.splash,
    routes: [
      // ── 탭 셸 밖 ─────────────────────────────────────────────
      //
      // 셸 밖이라 하단 탭이 뜨지 않는다. 온보딩은 탭으로 오갈 대상이 아니다.
      GoRoute(
        path: AppRoutes.splash,
        name: 'splash',
        builder: (context, state) => const SplashPage(),
      ),
      GoRoute(
        path: AppRoutes.onboardingIntro,
        name: 'onboarding_intro',
        builder: (context, state) => const OnboardingIntroPage(),
      ),
      GoRoute(
        path: AppRoutes.signIn,
        name: 'sign_in',
        builder: (context, state) => const SignInPage(),
      ),
      GoRoute(
        path: AppRoutes.signUp,
        name: 'sign_up',
        builder: (context, state) => const SignUpPage(),
      ),
      GoRoute(
        path: AppRoutes.terms,
        name: 'terms',
        builder: (context, state) {
          // `extra`는 `Object?`라 무엇이든 올 수 있다. 타입을 확인하고 아니면
          // 기본값으로 간다 — 딥링크로 들어오면 아무것도 실려 오지 않는다.
          final extra = state.extra;
          return TermsAgreementPage(
            next: extra is TermsNext ? extra : TermsNext.signUp,
          );
        },
      ),
      GoRoute(
        path: AppRoutes.profileSetup,
        name: 'profile_setup',
        builder: (context, state) => const ProfileSetupPage(),
      ),
      // ⚠️ 셸 **밖**이다. 탭 안에 두면 편집 도중 다른 탭으로 샐 수 있고,
      // 그때 저장하지 않은 값이 말없이 사라진다.
      GoRoute(
        path: AppRoutes.profileEdit,
        name: 'profile_edit',
        builder: (context, state) => const ProfileEditPage(),
      ),
      // 친구도 셸 밖이다. 검색창이 상단 고정이라 하단 탭까지 있으면 화면이
      // 위아래로 눌린다.
      GoRoute(
        path: AppRoutes.notifications,
        name: 'notifications',
        builder: (context, state) => const NotificationPage(),
      ),
      // 기록카드 작성 1. **탭 셸 밖이다** — 작성 중에 하단 탭으로 새지
      // 않게 한다.
      //
      // ⚠️ **`date` 쿼리가 없거나 못 읽으면 오늘로 떨어진다.** 404 를 내지
      // 않는다 — 탭 머리의 쓰기 버튼은 날짜를 싣지 않고 들어온다.
      GoRoute(
        path: AppRoutes.recordCardNew,
        name: 'record_card_new',
        builder: (context, state) => CardComposePage(
          day:
              DateTime.tryParse(state.uri.queryParameters['date'] ?? '') ??
              DateTime.now(),
        ),
      ),
      // 기록카드 작성 2 — 사진. **탭 셸 밖이다.**
      //
      // ⚠️ **초안이 비어 있으면 탭으로 돌려보낸다.** 딥링크나 프로세스 복원으로
      // 여기 바로 떨어지면 고를 기록도, 쓴 회고도 없다 — 카드 상세가 `extra`
      // 없이 들어온 것과 같은 꼴이다. 빈 화면을 띄우지 않는다.
      GoRoute(
        path: AppRoutes.recordCardNewPhotos,
        name: 'record_card_new_photos',
        redirect: _needsDraft,
        builder: (context, state) => const CardPhotoPage(),
      ),
      // 기록카드 작성 3 — 공개범위 · 음악 · 저장. **탭 셸 밖이다.**
      //
      // ⚠️ **저장하면 작성 셋을 걷고 상세를 민다.** `go`로 가면 셸 밖 라우트
      // 아래에 스택이 없어 안드로이드 뒤로가 앱을 닫는다. 걷어 내면 뒤로가
      // 캘린더로 떨어진다(설계 6-4).
      GoRoute(
        path: AppRoutes.recordCardNewPublish,
        name: 'record_card_new_publish',
        redirect: _needsDraft,
        builder: (context, state) =>
            CardPublishPage(onSaved: (card) => _toDetail(context, card)),
      ),
      // 기록카드 한 장. **탭 셸 밖이다** — 프로필이나 러닝 요약에서 열어도
      // 탭이 바뀌면 안 된다(`app_routes.dart`).
      //
      // ⚠️ **카드를 `extra`로 받는다.** 달력이 이미 들고 있는 것을 넘겨 주면
      // 다시 받아 올 필요가 없다. 딥링크처럼 `extra` 없이 들어오면 보여 줄
      // 것이 없으므로 탭으로 돌려보낸다 — 빈 화면을 띄우지 않는다.
      // 기록카드 수정 1·2·3. **탭 셸 밖이고, 카드를 `extra`로 받는다.**
      //
      // ⚠️ **카드 없이 들어오면 탭으로 돌려보낸다.** 단건 조회 API가 없어
      // 보여 줄 것이 없다 — 상세가 `extra` 없이 들어온 것과 같은 꼴이다.
      GoRoute(
        path: AppRoutes.recordCardEdit,
        name: 'record_card_edit',
        redirect: _needsCard,
        builder: (context, state) {
          final card = state.extra! as RecordCard;
          return CardComposePage(day: card.day, cardId: card.id, card: card);
        },
      ),
      GoRoute(
        path: AppRoutes.recordCardEditPhotos,
        name: 'record_card_edit_photos',
        redirect: _needsCard,
        builder: (context, state) {
          final card = state.extra! as RecordCard;
          return CardPhotoPage(cardId: card.id, card: card);
        },
      ),
      GoRoute(
        path: AppRoutes.recordCardEditPublish,
        name: 'record_card_edit_publish',
        redirect: _needsCard,
        builder: (context, state) => CardPublishPage(
          cardId: (state.extra! as RecordCard).id,
          onSaved: (card) => _toDetail(context, card),
        ),
      ),
      GoRoute(
        path: AppRoutes.recordCardDetail,
        name: 'record_card_detail',
        redirect: (context, state) =>
            state.extra is RecordCard ? null : AppRoutes.recordCard,
        // ⚠️ **쿼리가 없으면 "내 것이 아니다"로 읽는다.** 딥링크나 프로세스
        // 복원으로 들어온 경우가 그렇다 — 모르면 손을 떼는 쪽이 안전하다
        // (설계 9절의 공개범위 규칙과 같은 방향이다).
        builder: (context, state) => CardDetailPage(
          card: state.extra! as RecordCard,
          mine: state.uri.queryParameters['mine'] == 'true',
        ),
      ),
      GoRoute(
        path: AppRoutes.recordCardsOfUser,
        name: 'record_cards_of_user',
        builder: (context, state) => ProfileCardsPage(
          userId: state.pathParameters['userId'] ?? '',
          // 쿼리가 없으면 내 것이 아니다 — 상세와 같은 규칙이다.
          mine: state.uri.queryParameters['mine'] == 'true',
        ),
      ),
      GoRoute(
        path: AppRoutes.friends,
        name: 'friends',
        builder: (context, state) => const FriendPage(),
      ),
      GoRoute(
        path: AppRoutes.userProfile,
        name: 'user_profile',
        builder: (context, state) =>
            UserProfilePage(userId: state.pathParameters['userId'] ?? ''),
      ),
      GoRoute(
        path: AppRoutes.userFriends,
        name: 'user_friends',
        builder: (context, state) => UserFriendsPage(
          userId: state.pathParameters['userId'] ?? '',
          // 제목에만 쓴다. 딥링크로 바로 들어오면 비어 있을 수 있다.
          nickname: state.uri.queryParameters['nickname'] ?? '',
        ),
      ),
      // 설정도 셸 밖이다. 이유는 편집과 같다.
      GoRoute(
        path: AppRoutes.settings,
        name: 'settings',
        builder: (context, state) => const SettingsPage(),
      ),
      // ⚠️ 설정의 **자식으로 두지 않았다.** 자식이면 경로가
      // `/profile/settings/password`가 아니라 상대 경로가 되고,
      // 딥링크로 바로 열 때 부모가 먼저 그려져야 한다.
      GoRoute(
        path: AppRoutes.passwordChange,
        name: 'password_change',
        builder: (context, state) => const PasswordChangePage(),
      ),

      // 매칭 등록 — 셸 밖이다. 조건을 고르는 도중에 탭으로 새면 값이 사라진다.
      GoRoute(
        path: AppRoutes.inviteRegister,
        name: 'invite_register',
        builder: (context, state) => const InviteRegisterPage(),
      ),
      GoRoute(
        path: AppRoutes.matchRegister,
        name: 'match_register',
        builder: (context, state) => const MatchRegisterPage(),
      ),
      GoRoute(
        path: AppRoutes.matchRoom,
        name: 'match_room',
        builder: (context, state) => const MatchRoomPage(),
        routes: [
          // ⚠️ **자식으로 둔다.** 대기방이 아래에 남아 있어야 뒤로가기가 방으로
          // 돌아가고, 방이 죽을 때 이 페이지를 먼저 닫을 수 있다.
          GoRoute(
            path: 'chat',
            name: 'match_room_chat',
            builder: (context, state) => const ChatPage(),
          ),
        ],
      ),
      GoRoute(
        path: AppRoutes.matchCountdown,
        name: 'match_countdown',
        builder: (context, state) => const MatchCountdownPage(),
      ),

      // 1인 러닝 — 셸 밖이라 탭 바를 덮는다.
      GoRoute(
        path: AppRoutes.runPrepare,
        name: 'run_prepare',
        builder: (context, state) => const RunPreparePage(),
      ),
      GoRoute(
        path: AppRoutes.runSession,
        name: 'run_session',
        builder: (context, state) => const RunSessionPage(),
      ),
      GoRoute(
        path: AppRoutes.runSummary,
        name: 'run_summary',
        builder: (context, state) => const RunSummaryPage(),
      ),
      GoRoute(
        path: AppRoutes.runResult,
        name: 'run_result',
        // 종료 직후에도 **서버가 확정한 값**을 그린다. S15가 방 번호만
        // 넘기고 화면이 17·18번으로 읽는다 — 기록 탭에서 여는 것과 같은
        // 경로다.
        builder: (context, state) =>
            RecordDetailPage(runningRoomId: state.extra! as int),
      ),

      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) =>
            AppShell(navigationShell: navigationShell),
        branches: [
          // 0 · 홈 (S05)
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppRoutes.home,
                name: 'home',
                builder: (context, state) => const HomePage(),
              ),
            ],
          ),

          // 1 · 기록 (S21)
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppRoutes.record,
                name: 'record',
                builder: (context, state) => const RecordPage(),
                routes: [
                  GoRoute(
                    path: AppRoutes.recordDetail,
                    name: 'record_detail',
                    builder: (context, state) => RecordDetailPage(
                      // 경로에서 온 값이라 문자열이다. 숫자가 아니면 0을
                      // 넘겨 "못 찾음"으로 흘린다 — 상세 화면이 이미 오류
                      // 상태를 그린다.
                      runningRoomId:
                          int.tryParse(
                            state.pathParameters['runningRoomId'] ?? '',
                          ) ??
                          0,
                    ),
                  ),
                ],
              ),
            ],
          ),

          // 2 · 기록카드
          //
          // ⚠️ **카드 상세는 여기 두지 않는다.** 셸 밖(`recordCardDetail`)이다 —
          // 프로필이나 러닝 요약에서 카드를 열었을 때 탭이 바뀌면 안 된다.
          if (showRecordCardTab)
            StatefulShellBranch(
              routes: [
                GoRoute(
                  path: AppRoutes.recordCard,
                  name: 'record_card',
                  builder: (context, state) => const RecordCardPage(),
                ),
              ],
            ),

          // 3 · 프로필 (S22 — 본인)
          //
          // ⚠️ **S20은 타인 프로필이다.** Figma 페이지 이름이 `S20–S21`이라
          // 헷갈리기 쉽다. 정본은 `와이어프레임_최종.md`다.
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppRoutes.profile,
                name: 'profile',
                builder: (context, state) => const ProfilePage(),
              ),
            ],
          ),
        ],
      ),
    ],
  );
}

/// 작성 2·3에 들어갈 초안이 있나. 없으면 탭으로 돌려보낸다.
///
/// ## ⚠️ 빈 화면을 띄우지 않는다
///
/// 딥링크나 프로세스 복원으로 작성 2·3에 바로 떨어지면 고를 기록도, 쓴 회고도
/// 없다. 카드 상세가 `extra` 없이 들어왔을 때와 같은 꼴로 다룬다.
///
/// `canProceed`가 아니라 `isDirty`를 보지 않는다 — **저장할 수 있는 상태**인지
/// 묻는 것이고, 사진은 선택이라 그 판단에 안 들어간다.
String? _needsDraft(BuildContext context, GoRouterState state) {
  final draft = ProviderScope.containerOf(
    context,
    listen: false,
  ).read(cardDraftProvider(null));
  return draft.canProceed ? null : AppRoutes.recordCard;
}

/// 고칠 카드가 왔나. 없으면 탭으로 돌려보낸다.
///
/// ⚠️ 카드 **단건 조회 API가 없다** — `extra`로 받은 것이 전부다. 딥링크나
/// 프로세스 복원으로 들어오면 보여 줄 것이 없으므로 빈 화면을 띄우지 않는다.
String? _needsCard(BuildContext context, GoRouterState state) =>
    state.extra is RecordCard ? null : AppRoutes.recordCard;

/// 만든(또는 고친) 카드의 상세로 보낸다. **작성 세 화면을 걷는다**(설계 6-4).
///
/// ## ⚠️ `go`를 쓰지 않는다
///
/// 셸 밖 라우트에 `go`로 가면 그 아래에 스택이 없어 **안드로이드 뒤로가 앱을
/// 닫는다.** 작성 셋을 걷고 상세를 밀면 뒤로가 캘린더로 떨어진다.
///
/// ⚠️ **수정이면 옛 상세까지 걷힌다. 그래야 맞다** — 새 상세를 그냥 밀면
/// 상세가 둘 쌓여 뒤로가 두 번이 되고, 밑에 깔린 것은 **고치기 전 값**을
/// 들고 있다.
///
/// ⚠️ **러닝 요약에서 들어온 경우까지 걷는다**(묶음 6). 그때 이 줄을 다시 본다.
void _toDetail(BuildContext context, RecordCard card) {
  final router = GoRouter.of(context);
  while (router.canPop()) {
    router.pop();
  }
  router.push(
    // 고치거나 만든 카드다 — 남의 것을 저장할 길은 없다.
    AppRoutes.recordCardDetailOf(card.id, mine: true),
    extra: card,
  );
}
