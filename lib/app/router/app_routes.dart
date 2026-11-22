/// 경로 상수 — 화면 이동은 전부 이 상수를 거친다.
///
/// `context.go('/record')`처럼 문자열을 직접 쓰면 오타를 컴파일러가 못 잡는다.
/// `context.go(AppRoutes.record)`는 잡는다.
///
/// ## 딥링크
///
/// 여기 있는 경로가 곧 알림 딥링크의 대상이다.
/// 매핑은 **이 파일 한 곳에서만** 관리하고, 대상이 없으면 [home]으로 폴백한다.
/// 화면마다 자기 링크를 파싱하기 시작하면 규칙이 흩어진다.
///
/// ## `/`를 쓰지 않는 이유
///
/// 홈을 `/`로 두면 딥링크가 `runiverse://`처럼 끝나서 어느 화면인지 안 보인다.
/// 모든 탭을 `/이름` 형태로 맞췄다. 플랫폼이 넘겨주는 기본 경로 `/`는
/// go_router가 `initialLocation`([home])으로 대체한다.
/// 약관 동의를 마치면 무엇을 할 것인가.
///
/// 약관 화면(S03)이 두 흐름에서 쓰인다 — 이메일 가입과 카카오 로그인이다.
/// **화면이 목적지를 스스로 알지 못하게 한다.** 알게 하면 흐름이 늘 때마다
/// 그 파일을 고치게 되고, 온보딩 화면이 auth의 사정을 알게 된다.
///
/// 라우팅 상수 옆에 두는 이유는 **`extra`로 건너가는 값**이라서다. 어느 feature의
/// 것도 아니고, 화면 파일에 두면 auth가 onboarding의 화면을 import해야 한다.
enum TermsNext {
  /// 이메일 가입 — 정보 입력 화면([AppRoutes.signUp])으로 간다.
  signUp,

  /// 간편 로그인(카카오·구글) — 동의만 기록하고 **로그인 화면으로 돌아간다.**
  /// 인가는 그쪽이 시작한다.
  ///
  /// ⚠️ 예전 이름은 `kakao` 였는데, 하는 일에 제공자가 섞여 있지 않다 —
  /// 구글이 붙으면서 같은 값을 쓰게 돼 이름을 넓혔다.
  social,
}

abstract final class AppRoutes {
  // ── 온보딩 — 탭 셸 밖이다 ────────────────────────────────────
  //
  // 하단 탭이 없는 화면들이다. 셸 안에 넣으면 탭 바가 같이 뜬다.

  /// 스플래시 (S01). 앱의 첫 화면.
  static const splash = '/splash';

  /// 온보딩 소개 3장 (S02)
  static const onboardingIntro = '/onboarding';

  /// 로그인 (S02.5) — 이메일 · 카카오 · 애플이 한 화면에 있다.
  ///
  /// **정본 와이어프레임의 S02.5는 소셜 버튼 셋과 하단 링크뿐이다.**
  /// 백엔드가 이메일·비밀번호를 요구해 입력칸을 이 화면에 합쳤다
  /// (`docs/implementation-notes.md`).
  static const signIn = '/auth/sign-in';

  // ── 가입 (약관 → 정보 입력 → 프로필) ─────────────────────────
  //
  // 순서가 이렇게 된 이유는 **동의를 받기 전에 개인정보를 쥐지 않기 위해서**다.
  // 이메일·비밀번호를 먼저 받고 나중에 동의를 물으면 그사이 서버에 값이 저장된다.

  /// 가입 1 · 약관 동의 (S03)
  ///
  /// **가입 흐름의 첫 화면이다.** 이미 계정이 있는 사람은 지나가지 않는다.
  ///
  /// 카카오도 여기를 지난다. 어느 쪽에서 왔는지는 [TermsNext]를 `extra`로 넘겨 알린다.
  static const terms = '/onboarding/terms';

  /// 가입 2 · 정보 입력 — 이메일 인증 + 비밀번호
  ///
  /// 성공하면 **자동으로 로그인된 상태**가 되어 프로필로 넘어간다.
  static const signUp = '/auth/sign-up';

  /// 가입 3 · 프로필 등록 (S04). 온보딩의 마지막 화면이다.
  ///
  /// ⚠️ 서버가 "이 사람이 온보딩을 마쳤는가"를 알려주지 않는다. 그래서 가입한 사람만
  /// 여기를 지나가게 해두었다. **앱을 지웠다 깔면 기존 사용자도 이 화면을 다시 본다.**
  static const profileSetup = '/onboarding/profile';

  // ── 탭 셸 안 ────────────────────────────────────────────────

  /// 홈 (S05)
  static const home = '/home';

  /// 기록 (S21)
  static const record = '/record';

  /// 기록 상세. **S16과 같은 화면**을 지난 기록으로 연다.
  ///
  /// 기록 탭 안쪽이라 탭 branch의 자식으로 둔다 — 상세를 열어 둔 채 다른
  /// 탭에 갔다 와도 그 자리가 남는다.
  static const recordDetail = 'detail/:runningRoomId';

  /// `/record/detail/12` — [recordDetail]은 상대 경로라 직접 못 쓴다.
  ///
  /// ⚠️ **기록 번호가 아니라 방 번호다.** 결과 조회(17·18번)가 방 번호로
  /// 찾고, 러닝을 막 끝냈을 때 앱이 아는 것도 방 번호뿐이다.
  static String recordDetailOf(int runningRoomId) =>
      '$record/detail/$runningRoomId';

  /// 기록카드 탭.
  ///
  /// 그때 뛴 경험을 사진·회고로 남기는 탭이다. 온보딩 3장이 이걸 소개한다.
  static const recordCard = '/record-card';

  /// 기록카드 작성 1 — 기록 고르기 · 유형 · 회고.
  ///
  /// ⚠️ **탭 셸 밖이다.** 작성 화면에 하단 탭 바가 보이면 저장하지 않고 다른
  /// 탭으로 샐 수 있다(`app_routes.dart`의 프로필 편집과 같은 이유).
  ///
  /// ⚠️ **`card/:id`보다 먼저 선언하지 않아도 안전하다** — 상세가
  /// `/record-card/card/:id`라 `new`와 자리가 겹치지 않는다.
  static const recordCardNew = '/record-card/new';

  /// 어느 날의 기록을 고를 것인가.
  ///
  /// ⚠️ **날짜를 쿼리로 싣는다.** `extra`로 넘기면 딥링크나 프로세스 복구에서
  /// 사라지고, 그때 작성 화면이 어느 날인지 모른다.
  /// [roomId]를 주면 **그 방에서 뛴 기록이 미리 골라진다**(설계 6-2 "러닝
  /// 요약에서 왔으면 날짜와 기록이 골라져 있다").
  ///
  /// ⚠️ **기록 번호가 아니라 방 번호다.** 러닝 요약이 가진 것은 방 번호뿐이고
  /// (`RunDetail`에 기록 번호가 없다) `RunRecord.runningRoomId`가 그 둘을
  /// 잇는다. 방이 없으면(솔로·방 열기 실패) 날짜만 간다.
  static String recordCardNewOn(DateTime day, {int? roomId}) {
    final month = day.month.toString().padLeft(2, '0');
    final date = day.day.toString().padLeft(2, '0');
    final room = roomId == null ? '' : '&room=$roomId';
    return '$recordCardNew?date=${day.year}-$month-$date$room';
  }

  /// 기록카드 작성 2 — 사진.
  ///
  /// ⚠️ **날짜를 싣지 않는다.** 어느 날인지는 작성 1이 이미 초안에 꽂았다
  /// (`cardDraftProvider`의 `record`). 여기서 다시 받으면 두 곳이 갈라져,
  /// 날짜를 고쳐 놓고 넘어온 사람이 옛 날짜를 보게 된다.
  ///
  /// ⚠️ **초안이 비어 있으면 탭으로 돌려보낸다.** 작성 1을 거치지 않고
  /// 떨어지면 고를 기록도 쓴 회고도 없다 — 카드 상세가 `extra` 없이 들어온
  /// 것과 같은 꼴이다.
  static const recordCardNewPhotos = '/record-card/new/photos';

  /// 기록카드 작성 3 — 공개범위 · 음악 · 저장.
  ///
  /// [recordCardNewPhotos]와 같은 규칙이다 — 날짜를 싣지 않고, 초안이 비면
  /// 탭으로 돌려보낸다.
  static const recordCardNewPublish = '/record-card/new/publish';

  /// 기록카드 한 장 (읽기 전용).
  ///
  /// ⚠️ **탭 셸 밖에 둔다.** 셸 안에 두면 ① 프로필 그리드나 러닝 요약에서 카드를
  /// 열었을 때 **기록카드 탭으로 전환**되어 뒤로 가기가 엉뚱한 데로 떨어지고
  /// ② 하단 탭 바가 함께 보인다.
  static const recordCardDetail = '/record-card/card/:id';

  /// ⚠️ **카드 번호다.** 러닝 기록 번호도 방 번호도 아니다.
  ///
  /// ## ⚠️ [mine]을 반드시 적는다
  ///
  /// 남의 카드면 `⋮`(수정·삭제)와 `AI 음악 만들기`를 세우지 않는다(설계 6-5).
  /// 그런데 **카드 응답에 소유자가 없다** — 스키마가 비어 있어
  /// (`docs/notes/2026-11-16-record-card-backend-questions.md` 1-1번) 지어
  /// 넣으면 응답이 오는 날 도메인을 다시 짓는다. 그래서 **들어온 길이
  /// 말한다.**
  ///
  /// 선택 인자로 두지 않는 이유: 기본값을 주면 새 진입점이 조용히 "내 것"으로
  /// 들어오고, 그 결과는 **남의 카드에 뜬 수정 버튼**이다. 컴파일러가 묻게
  /// 한다.
  static String recordCardDetailOf(int cardId, {required bool mine}) =>
      '$recordCard/card/$cardId?mine=$mine';

  /// 기록카드 수정 1·2·3 (설계 6-6).
  ///
  /// 수정은 **작성 세 화면을 그대로 다시 쓴다.** 라우트만 따로 두는 이유는
  /// 초안을 카드 번호로 가르기 위해서다 — 새 카드를 쓰던 중에 남의 카드
  /// 수정으로 들어가도 섞이지 않는다(설계 7절).
  ///
  /// ⚠️ **카드를 `extra`로 받는다.** 카드 단건 조회 API가 없어 상세와 같은
  /// 방식이다. 없이 들어오면 탭으로 돌려보낸다.
  static const recordCardEdit = '/record-card/card/:id/edit';
  static const recordCardEditPhotos = '/record-card/card/:id/edit/photos';
  static const recordCardEditPublish = '/record-card/card/:id/edit/publish';

  static String recordCardEditOf(int cardId) => '$recordCard/card/$cardId/edit';
  static String recordCardEditPhotosOf(int cardId) =>
      '${recordCardEditOf(cardId)}/photos';
  static String recordCardEditPublishOf(int cardId) =>
      '${recordCardEditOf(cardId)}/publish';

  /// 그 사람의 기록카드 **전체 보기** — 프로필 그리드의 `더 보기`가 가는 곳
  /// (설계 6-7).
  ///
  /// ⚠️ **`/record-card/` 아래 둔다.** ① 셸 **밖**이라 남의 프로필에서 들어와도
  /// 탭이 바뀌지 않고(설계 7절) ② 저장·삭제 뒤 되돌아가기가 경로 앞머리로
  /// "작성·수정 흐름"을 가리는데(`app_router.dart`의 `_toDetail`) `card/`도
  /// `new`도 아니어서 **걷히지 않는다.**
  static const recordCardsOfUser = '/record-card/user/:userId';

  /// [mine]은 상세로 그대로 흘러간다 — 남의 카드에는 `⋮`를 세우지 않는다.
  static String recordCardsOf(String userId, {required bool mine}) =>
      '$recordCard/user/${Uri.encodeComponent(userId)}?mine=$mine';

  /// 본인 프로필 (S20)
  static const profile = '/profile';

  /// 프로필 편집 (S22.1)
  ///
  /// **탭 셸 밖에 둔다.** 정본이 `‹ 프로필 편집  저장` 헤더의 전체 화면이라
  /// 하단 탭이 함께 보이면 저장하지 않고 다른 탭으로 샐 수 있다.
  static const profileEdit = '/profile/edit';

  /// 친구 — 목록 · 추천 · 검색이 한 화면이다.
  ///
  /// **탭 셸 밖에 둔다.** 검색창이 상단에 고정이라 하단 탭까지 함께 있으면
  /// 화면이 위아래로 눌린다. 인앱 알림이 생기면 이 경로가 딥링크가 된다.
  static const friends = '/profile/friends';

  /// 알림함 — 친구 요청·수락과 러닝 초대가 한 목록에 모인다.
  ///
  /// **홈 위 줄의 종**(`HomeTopBar`)과 **프로필 커버의 벨**(`ProfilePage`)로
  /// 들어온다. 하단 탭이 넷으로 고정이라 탭을 더할 자리가 없다.
  ///
  /// 주소가 `/profile/`로 시작하는 것은 입구가 프로필에만 있던 때의 이름이다.
  /// 푸시를 누르면 이 주소로 들어와서(`AppShell`) 바꾸지 않았다.
  ///
  /// [friends]와 같은 이유로 **탭 셸 밖**이다 — 목록을 보다 다른 탭으로 새면
  /// 읽음 처리와 배지가 어긋난다.
  static const notifications = '/profile/notifications';

  /// 남의 프로필. `userId`가 누구를 보는지 정한다.
  ///
  /// 인앱 알림의 "누가 친구 요청을 보냈어요"가 이 경로로 떨어진다.
  static const userProfile = '/profile/user/:userId';

  /// [userProfile]의 자리를 채운다.
  static String userProfileOf(String userId) => '/profile/user/$userId';

  /// 남의 친구 목록. 그 사람의 프로필에서 `친구 · N`을 눌러 들어온다.
  static const userFriends = '/profile/user/:userId/friends';

  static String userFriendsOf(String userId) => '/profile/user/$userId/friends';

  /// 설정 (S22.2)
  ///
  /// **탭 셸 밖에 둔다.** [profileEdit]과 같은 이유다 — 하단 탭이 함께 보이면
  /// 설정을 하다 말고 다른 탭으로 샌다.
  static const settings = '/profile/settings';

  /// 비밀번호 변경 — 설정 하위 (명세 56번)
  ///
  /// ⚠️ **로컬 계정만 들어온다.** 설정 화면이 `loginType`으로 메뉴를 숨기지만,
  /// 딥링크는 그 문을 지나치지 않는다 — 그때는 서버가 409로 막는다.
  static const passwordChange = '/profile/settings/password';

  // ── 매칭 ─────────────────────────────────────────────────────

  /// 매칭 등록 (S08). 홈 히어로의 매칭 버튼에서 들어온다.
  ///
  /// **탭 셸 밖이다.** 조건을 고르는 도중에 다른 탭으로 새면 고른 값이 사라진다.
  static const matchRegister = '/match/register';

  /// 초대 등록 — 시각과 거리를 자유롭게 정해 방을 연다.
  ///
  /// **매칭 등록([matchRegister])과 다른 화면이다.** 입력이 겹치지 않는다 —
  /// 저쪽은 서버가 준 슬롯과 거리 셋, 이쪽은 자유 입력이다.
  static const inviteRegister = '/match/invite';

  /// 대기방 (S10). 모집 중과 확정 뒤를 한 화면이 맡는다.
  ///
  /// **셸 밖이다.** 매칭 상태는 탭이 아니라 그 자체로 하나의 흐름이다.
  static const matchRoom = '/match/room';

  /// 대기방 채팅. **[matchRoom]의 자식이다** — 열어 둔 동안 대기방이 그대로
  /// 살아 있고, 그 화면의 자동 이동 두 개가 이 라우트를 먼저 닫고 움직인다.
  static const matchRoomChat = '/match/room/chat';

  /// 출발 대기실 (S11). **취소 불가 구간이다** — 뒤로가기가 막힌다.
  static const matchCountdown = '/match/countdown';

  // ── 1인 러닝 — 탭 셸 밖이다 ──────────────────────────────────
  //
  // **탭 바를 덮는다.** 달리는 도중에 다른 탭으로 샐 수 있으면 안 된다.

  /// 출발 준비 (S11 파생). GPS 첫 신호를 기다린다.
  static const runPrepare = '/run/prepare';

  /// 러닝 진행 (S13). 지도 · 실시간 기록 2페이지.
  static const runSession = '/run';

  /// 러닝 요약 (S15).
  static const runSummary = '/run/summary';

  /// 러닝 결과 (S16). 정본의 S16.5(구간별 상세 비교)를 아래로 이어 붙인 한 화면이다.
  static const runResult = '/run/result';
}
