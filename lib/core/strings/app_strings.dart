/// UI 문자열 — 화면 코드에 한국어를 직접 쓰지 않는다.
///
/// 한곳에 모아두면 문구 톤을 일괄로 맞출 수 있고, 나중에 다국어를 붙일 때
/// 화면을 뒤지지 않아도 된다.
///
/// ## 톤 규칙 (기능명세서)
///
/// 담담하게 쓴다. 사과하지 않고, 과장하지 않는다.
/// **이모지를 쓰지 않는다** — 상태는 색 + 텍스트 + 스트로크 아이콘으로 표현한다.
///
/// ## 조사 주의
///
/// 문자열을 조립할 때 `'$name은'` 같은 조사를 붙이지 않는다.
/// 받침 유무에 따라 은/는, 이/가가 갈리는데 코드는 그걸 모른다
/// ("피드**는**" / "대회일정**은**"). 조사가 필요 없게 문장을 짠다.
abstract final class AppStrings {
  // ── 하단 탭 ──────────────────────────────────────────────────
  //
  // 탭 5개는 홈 / 기록 / 피드 / 대회일정 / 프로필이다.
  // 일부 기획 문서의 '홈/러닝/기록/피드/마이'는 낡은 것이다.

  static const tabHome = '홈';
  static const tabRecord = '기록';
  static const tabFeed = '피드';
  static const tabCompetition = '대회일정';
  static const tabProfile = '프로필';

  // ── 준비 중 화면 ─────────────────────────────────────────────

  static const comingSoonTitle = '준비 중이에요';
  static const comingSoonBody = '다음 업데이트에서 만날 수 있어요.';

  // ── 브랜드 ───────────────────────────────────────────────────

  /// 워드마크. 로고 에셋이 없어 타입으로만 쓴다.
  static const brandName = 'Runiverse';

  static const brandTagline = '혼자 뛰지만, 함께 뛰는 러닝';

  // ── 스플래시 (S01) ──────────────────────────────────────────
  //
  // 서버에 닿지 못하면 앱에 들어가지 못한다. **오프라인은 허용하지 않는다** —
  // 저장된 값을 믿고 들여보내면 "연결이 끊긴 것"과 "토큰이 살아 있는 것"을
  // 같이 취급하게 된다.

  static const splashOffline = '연결할 수 없어요';

  static const splashOfflineHint = '인터넷 연결을 확인하고 다시 시도해주세요';

  static const splashRetry = '다시 시도';

  // ── 온보딩 소개 (S02) ────────────────────────────────────────
  //
  // 카드 3장의 순서는 "무엇을 하는 앱인가 → 무엇을 얻는가 → 어떻게 남는가"다.
  // 기능 나열이 아니라 동기를 쌓는 순서라 바꾸지 않는다.

  /// 우상단 이탈 경로. 최우선으로 노출한다.
  static const onboardingSkip = '건너뛰기';

  static const onboardingNext = '다음';

  /// 마지막 카드에서 [onboardingNext] 대신 쓴다.
  static const onboardingStart = '시작하기';

  static const onboardingCard1Title = '같은 시각에\n함께 달려요';
  static const onboardingCard1Body =
      '서로 다른 장소에 있어도 30분 슬롯으로 매칭돼요.\n2~4명이 같은 시각에 함께 출발해요.';

  static const onboardingCard2Title = '달린 만큼\n색이 쌓여요';
  static const onboardingCard2Body =
      '거리·페이스·꾸준함이 각자의 색이 돼요.\n함께 달린 사람들의 색과 섞이기도 해요.';

  static const onboardingCard3Title = '달린 날만\n남겨요';
  static const onboardingCard3Body = '빠진 날을 세지 않아요.\n달린 날에 얻은 색만 기록에 남아요.';

  // ── 약관 동의 (S03) ──────────────────────────────────────────
  //
  // 필수 3항목 + 선택 1항목(마케팅)이다.
  // ⚠️ 선택 항목은 **서버로 가지 않는다** — 받을 API가 아직 없다.

  static const termsTitle = '약관에\n동의해주세요';
  static const termsSubtitle = '매칭과 기록 분석에 필요한\n최소 정보만 받아요';

  /// 카드형 일괄 토글. 3번 탭할 것을 1번으로 줄인다.
  static const termsAgreeAll = '전체 동의';

  /// 배지 문구. 대괄호나 알약 같은 **모양은 위젯이 정한다.**
  /// 문자열에 `[]`를 넣으면 배지 디자인이 바뀔 때 여기까지 고쳐야 한다.
  static const termsRequired = '필수';

  /// `필수`와 나란히 서므로 **같은 두 글자**로 맞춘다.
  /// 길이가 다르면 라벨의 시작 위치가 줄마다 어긋난다.
  static const termsOptional = '선택';

  static const termsService = '서비스 이용약관';
  static const termsPrivacy = '개인정보 수집·이용';
  static const termsHealth = '생체·운동 정보';

  /// 마케팅 수신 동의. **무엇을 보내는지** 밝힌다 —
  /// "마케팅 정보 수신"만으로는 무엇에 동의하는지 알 수 없다.
  static const termsMarketing = '매칭 소식과 이벤트 알림';

  /// 위치 권한을 지금 묻지 않는 이유를 미리 알린다.
  /// 권한 요청은 실제로 필요한 맥락(매칭 등록)에서 해야 수락률이 높다.
  static const termsLocationNotice = '위치 권한은 매칭을\n시작할 때 여쭤봐요';

  /// **필수** 3항목을 전부 동의해야 눌린다. 선택은 막지 않는다.
  static const termsCta = '동의하고 계속';

  // ── 프로필 등록 (S04) ────────────────────────────────────────
  //
  // 질문을 한 번에 하나씩 던진다. 답하면 다음이 아래에 붙고, 답한 것은 위에 쌓인다.
  // 그래서 문구가 라벨(`닉네임`)과 질문(`뭐라고 부를까요`) 두 벌로 나뉜다 —
  // 질문은 묻는 동안, 라벨은 쌓인 뒤에 쓴다.

  static const profileTitle = '프로필을 만들어요';

  /// 답한 줄을 눌러 되돌아갈 수 있다는 것을 스크린리더에 알린다.
  static const profileEditHint = '고치기';

  static const profileNext = '다음';

  /// 프로필 전송이 실패했을 때. **입력은 화면에 그대로 남는다** —
  /// 다섯 개를 다시 채우게 하지 않는다.
  static const profileSubmitFailed = '저장하지 못했어요. 다시 시도해주세요';

  /// 세션이 끊겨 다시 로그인해야 할 때. 사용자는 아무것도 틀리지 않았다.
  static const profileSubmitExpired = '로그인이 만료됐어요. 다시 로그인해주세요';

  // 닉네임
  static const profileNicknameLabel = '닉네임';
  static const profileNicknameQuestion = '뭐라고 부를까요';
  static const profileNicknameWhy = '함께 달리는 러너에게 보이는 이름이에요.';
  static const profileNicknameHint = '러너42';
  static const profileNicknameGuide = '2~16자로 지어주세요';
  static const profileNicknameTooShort = '2자 이상이어야 해요';

  /// 상한에서 막혔을 때 잠깐 떴다 사라진다.
  static const profileNicknameTooLong = '16자까지 쓸 수 있어요';

  /// 서버 정규식(`^[가-힣a-zA-Z0-9_]+$`)에 걸리는 문자를 썼을 때.
  /// **무엇이 되는지**를 말한다 — 안 되는 것을 나열하면 길고 외우기 어렵다.
  static const profileNicknameInvalidChars = '한글, 영문, 숫자, _만 쓸 수 있어요';

  /// 형식은 통과했지만 **아직 서버에 묻지 않았다.**
  ///
  /// ⚠️ 이 자리에 [profileNicknameOk]를 쓰면 안 된다. 곧 "이미 있다"로
  /// 뒤집힐 수 있는 말을 먼저 해버리는 셈이다.
  static const profileNicknameCheckPending = '쓸 수 있는지 확인할게요';

  /// **서버가 쓸 수 있다고 답했다.** 형식만 통과한 상태가 아니다.
  static const profileNicknameOk = '쓸 수 있는 이름이에요';
  static const profileNicknameConfirm = '확인';

  /// 서버에 묻는 동안. 확인 버튼이 잠기는 이유를 말해준다.
  static const profileNicknameChecking = '확인하는 중이에요';

  /// 물어보지 못했다. **[profileNicknameTaken]과 다른 말이어야 한다** —
  /// 이름을 바꿀 일이 아니라 다시 눌러볼 일이다.
  static const profileNicknameCheckFailed = '확인하지 못했어요. 다시 눌러주세요';

  /// 서버가 이미 누가 쓰고 있다고 답했다.
  ///
  /// **"중복"이라 쓰지 않는다** — 무엇을 해야 하는지 말해주는 쪽이 낫다.
  /// [profileNicknameOk]와 같은 자리에 반대 톤으로 뜬다.
  static const profileNicknameTaken = '이미 누가 쓰고 있어요. 다른 이름을 지어주세요';

  // 생년월일
  static const profileBirthLabel = '생년월일';
  static const profileBirthQuestion = '언제 태어났나요';
  static const profileBirthWhy = '기록을 계산하는 데만 써요. 다른 러너에게 보이지 않아요.';
  static const profileUnitYear = '년';
  static const profileUnitMonth = '월';
  static const profileUnitDay = '일';

  // 성별
  static const profileGenderLabel = '성별';
  static const profileGenderQuestion = '성별을 알려주세요';
  static const profileGenderWhy = '기록 계산에만 써요.';
  // 남성·여성 둘뿐이다. 칼로리·페이스 계산식이 이분법을 전제해서인데,
  // 그 계산이 필요 없는 곳(프로필 공개 정보 등)까지 이 값을 끌어다 쓰면 안 된다.
  static const profileGenderMale = '남성';
  static const profileGenderFemale = '여성';

  // 키·몸무게
  static const profileBodyLabel = '키 · 몸무게';
  static const profileBodyQuestion = '키와 몸무게는요';
  static const profileBodyWhy = '칼로리를 셈하는 데만 써요.';
  static const profileUnitHeight = 'cm';
  static const profileUnitWeight = 'kg';

  // 페이스 — 5km 기준 1km당 분·초
  //
  // 등급을 고르게 하지 않고 숫자를 받는다. '중급'이 무엇인지는 사람마다 다르지만
  // "1km를 6분에 뛴다"는 누구에게나 같은 값이다.
  static const profilePaceLabel = '페이스';
  static const profilePaceQuestion = '5km를 뛰면 어느 정도인가요';
  static const profilePaceWhy = '1km를 몇 분에 뛰는지 알려주세요. 시그니처 컬러를 정하는 데 써요.';
  static const profilePaceSheetTitle = '1km당 페이스';
  static const profileUnitMinute = '분';
  static const profileUnitSecond = '초';

  /// 답한 줄에 붙는 단위. `5'42" /km`
  static const profilePacePerKm = '/km';

  /// 건너뛰기 버튼 위 눈썹 문구. **누구를 위한 출구인지** 먼저 밝힌다.
  /// 이게 없으면 페이스를 아는 사람도 건너뛰기를 편한 길로 여긴다.
  static const profilePaceSkipEyebrow = '러닝이 처음이라면';

  /// 아직 재본 적 없는 사람의 출구. 이걸 막으면 입문자가 아무 값이나 찍고 넘어간다.
  static const profilePaceSkip = '건너뛰기';

  /// 버튼 아래 안내. 측정이 어디서 이뤄지는지 미리 알린다.
  static const profilePaceSkipWhy = '홈에서 혼자 연습하며 재보면 그때 채워져요.';

  /// 미측정 상태로 쌓인 줄에 보이는 값.
  static const profilePaceUnmeasured = '측정 전';

  /// 시트를 열기 전 자리 표시.
  static const profileTapToPick = '탭해서 고르기';

  // ── 로그인 (S02.5) ───────────────────────────────────────────
  //
  // 정본 와이어프레임의 S02.5는 소셜 버튼 셋과 하단 링크뿐이다.
  // 이메일·비밀번호 입력은 정본에 없고, 백엔드가 그 방식을 요구해 한 화면에 합쳤다.
  // (`docs/implementation-notes.md` 참조)

  /// 아이디를 기기에 남길지. **끄면 저장해 둔 값도 지운다** —
  /// 공유 기기에서 남의 이메일이 남지 않아야 한다.
  static const authRememberEmail = '아이디 저장';

  /// 마지막으로 성공한 로그인 방법에 붙는 표시.
  ///
  /// ⚠️ **이 기기에서 로그인한 적이 있어야 뜬다.** 앱을 지웠다 깔거나 기기를
  /// 바꾸면 없다 — "내가 뭘로 가입했더라"가 떠오르는 순간이 대개 그때다.
  static const authLastUsed = '최근 사용';

  static const authKakao = '카카오로 계속하기';
  static const authApple = 'Apple로 계속하기';

  /// 이메일 로그인과 소셜 버튼 사이의 구분선.
  static const authOr = '또는';

  /// 카카오·애플을 눌렀을 때. 버튼을 회색으로 잠그지 않는 이유는
  /// 피드·대회일정 탭과 같다 — 눌리고, 준비 중임을 알린다.
  static const authSocialComingSoon = '아직 준비 중이에요';

  static const authSignInTitle = '로그인';

  static const authBack = '뒤로';

  static const authEmailLabel = '이메일';
  static const authEmailHint = 'runner@example.com';
  static const authEmailInvalid = '이메일 형식이 아니에요';

  static const authPasswordLabel = '비밀번호';
  static const authPasswordShow = '비밀번호 보기';
  static const authPasswordHide = '비밀번호 가리기';

  /// 제목([authSignInTitle])과 **글자가 달라야 한다.** 같으면 `find.text('로그인')`이
  /// 화면에서 둘을 찾아 위젯 테스트가 "여러 개를 찾았다"로 죽는다.
  static const authSignInCta = '로그인하기';

  // 실패 문구 — **서버가 준 message를 쓰지 않는다.**
  // 서버는 습니다체고 앱은 해요체다. 서버가 주는 code로 여기서 문구를 고른다.

  static const authFailedCredentials = '이메일이나 비밀번호가 맞지 않아요';
  static const authFailedNetwork = '인터넷 연결을 확인해주세요';
  static const authFailedServer = '잠시 후 다시 시도해주세요';
  static const authFailedUnknown = '로그인하지 못했어요. 다시 시도해주세요';

  /// 서버가 형식을 거절했다 (400 `VALIDATION_FAILED`).
  ///
  /// 사유는 서버 `message`에만 있는데 그것을 화면에 옮기지 않는다 — 문구가 바뀌면
  /// 앱이 따라 바뀐다. **여기까지 왔다는 것은 앱 검증에 구멍이 있다는 뜻**이라
  /// 정확한 사유는 `kDebugMode` 로그에서 찾는다.
  static const authFailedValidation = '입력한 내용을 다시 확인해주세요';

  // ── 회원가입 ─────────────────────────────────────────────────

  static const authSignUpTitle = '가입하기';
  static const authSignUpCta = '가입하고 시작하기';

  /// 규칙을 미리 보여준다. 서버가 막기 전에 화면이 먼저 알려준다.
  /// ⚠️ 이 문구는 `PasswordRule`의 값과 같아야 한다. 규칙을 바꾸면 함께 고친다.
  static const authPasswordGuide = '6~16자, 영문·숫자·특수문자를 각각 하나씩';
  static const authPasswordTooShort = '6자 이상이어야 해요';
  static const authPasswordTooLong = '16자까지 쓸 수 있어요';
  static const authPasswordMissingKind = '영문·숫자·특수문자를 각각 하나씩 넣어주세요';

  /// 한글이 섞였을 때. **한/영을 깜빡한 사람에게 길이부터 말하지 않는다** —
  /// 그러면 한글을 더 치게 된다.
  static const authPasswordDisallowedChar = '영문·숫자·특수문자만 쓸 수 있어요';
  static const authPasswordOk = '쓸 수 있는 비밀번호예요';

  /// 두 화면을 오가는 링크. 물음표로 끝내 조사 문제를 피한다.
  static const authToSignUp = '계정이 없나요? 가입하기';
  static const authToSignIn = '이미 계정이 있나요? 로그인';

  /// **인증번호를 받기 전에** 나온다. 서버가 발송 단계에서 중복을 막기 때문이다.
  /// 바로 아래의 [authToSignIn]이 갈 곳을 알려준다.
  /// 이미 그 이메일로 계정이 있다. 서버 `EMAIL_ALREADY_EXISTS` (409).
  ///
  /// ⚠️ **어느 방법으로 가입했는지 말하지 않는다.** 로컬 가입과 소셜 로그인이
  /// 같은 코드를 주고, 응답에 `provider`가 없어 앱이 구분할 수 없다.
  /// "이메일로 로그인해주세요"처럼 단정하면 구글로 가입한 사람에게 틀린 안내가
  /// 된다 — 서버가 `provider`를 실어 주면 그때 갈라 말한다.
  static const authFailedEmailTaken = '이미 가입된 계정이에요';

  // ── 이메일 인증 ──────────────────────────────────────────────
  //
  // 이메일 → 인증번호 → 비밀번호 순으로 한 화면에서 열린다.
  // 앞 단계를 마쳐야 다음 칸이 나타난다.

  static const authVerifySend = '인증번호 받기';
  static const authVerifyResend = '다시 받기';

  static const authVerifyLabel = '인증번호';
  static const authVerifyHint = '메일로 보낸 6자리 숫자';
  static const authVerifyConfirm = '확인';

  /// 전송 직후 안내. 메일함을 열어보라고 말해주지 않으면 화면에서 기다린다.
  static const authVerifySent = '메일을 보냈어요. 받은 편지함을 확인해주세요';

  static const authVerifyIncomplete = '숫자 6자리를 입력해주세요';

  /// 인증을 마친 뒤. 이 줄이 없으면 됐는지 안 됐는지 알 수 없다.
  static const authVerifyDone = '인증됐어요';

  /// 이메일을 고쳐서 인증이 풀렸을 때. **왜 풀렸는지**를 밝힌다.
  static const authVerifyReset = '이메일이 바뀌어서 인증을 다시 받아야 해요';

  static const authFailedInvalidCode = '인증번호가 맞지 않아요';
  static const authFailedCodeExpired = '인증번호가 만료됐어요. 다시 받아주세요';
  static const authFailedTooManyAttempts = '인증 시도가 많아요. 인증번호를 다시 받아주세요';
  static const authFailedSendFailed = '메일을 보내지 못했어요. 잠시 후 다시 시도해주세요';

  /// 티켓이 만료돼 처음부터 다시 해야 한다. **"다시 받아주세요"로는 부족하다** —
  /// 티켓은 1회용이라 인증 단계로 돌아가야 한다.
  static const authFailedNotVerified = '인증이 만료됐어요. 인증번호를 다시 받아주세요';

  /// ⚠️ 아래 둘은 **서버 문구를 그대로 쓴다**(요청받은 값).
  /// 다른 문구가 해요체인 것과 달리 습니다체다 — 톤을 맞출지는 리뷰에서 정한다.
  static const authFailedSendCooldown = '인증 메일을 방금 보냈습니다. 잠시 후 다시 시도해 주세요.';
  static const authFailedSendDailyLimit = '하루 인증 메일 발송 횟수를 초과했습니다.';

  // ── 소셜 로그인 ──────────────────────────────────────────────
  //
  // 취소에는 문구가 없다. 스스로 그만둔 사람에게 오류를 띄우지 않는다.

  static const authFailedOauth = '카카오 로그인을 마치지 못했어요. 다시 시도해주세요';

  /// 이메일 동의를 못 받았다. **무엇을 해야 하는지** 말한다 —
  /// "실패했어요"만으로는 다시 눌러도 같은 결과가 나온다.
  static const authFailedOauthEmail = '이메일 제공에 동의해야 로그인할 수 있어요';

  // ── 홈 (S05) ─────────────────────────────────────────────────

  /// 시간대 인사. 이름을 부르지 않는다 — 닉네임을 저장하는 곳이 아직 없다.
  ///
  /// 정본 S05는 `좋은 저녁이에요, 러너42 님`이다. 프로필이 서버에 붙으면
  /// 이름을 붙인 형태로 바꾼다.
  static const homeGreetingMorning = '좋은 아침이에요';
  static const homeGreetingAfternoon = '좋은 오후예요';
  static const homeGreetingEvening = '좋은 저녁이에요';
  static const homeGreetingNight = '늦은 밤이네요';

  /// 히어로 문구. 줄바꿈 위치를 고정해 두 줄로 읽히게 한다.
  static const homeHeroPrompt = '오늘도 누군가와\n같은 시간에 뛰어볼까요?';

  static const homeMatchCta = '지금 매칭하기';
  static const homeSoloCta = '혼자 달리기';

  /// 매칭은 아직 서버가 없다. 카카오·애플 버튼과 같은 처리다.
  static const homeMatchComingSoon = '매칭은 아직 준비 중이에요';

  static const homeSectionCompetition = '다가오는 대회';
  static const homeSectionRecentRun = '최근 러닝';

  static const homeEmptyCompetition = '등록된 대회가 없어요';
  static const homeEmptyRecentRun = '아직 달린 기록이 없어요';

  /// 빈 상태에 붙는 한 줄. 무엇을 하면 채워지는지 알려준다.
  static const homeEmptyRecentRunHint = '혼자 달리기로 첫 기록을 남겨보세요';

  // ── 프로필 탭 (S22, 본인) ────────────────────────────────────
  //
  // ⚠️ **S22가 본인, S20이 타인**이다. Figma 페이지 이름이 `S20–S21`이라
  // 헷갈리기 쉽다 — 정본은 `와이어프레임_최종.md`다.

  /// 닉네임 자리. 아직 프로필을 안 채운 사람에게 보인다.
  ///
  /// ⚠️ 실제로는 거의 보이지 않는다 — 프로필이 없으면 홈에서 [profileSheetTitle]이
  /// 막아서기 때문이다. 딥링크처럼 그 관문을 지나치는 길에 대비해 남긴다.
  static const profileNicknameEmpty = '프로필을 완성해주세요';

  static const profileSignatureLabel = '시그니처 컬러';

  /// 시그니처 컬러가 아직 없을 때. **"없어요"라고 하지 않는다** —
  /// 결핍이 아니라 무엇을 하면 생기는지를 말한다.
  static const profileSignatureEmpty = '함께 달리면 색이 생겨요';

  /// 서로 수락해 함께 달리는 사람 수.
  ///
  /// ⚠️ **"친구"라고 쓰지 않는다.** 요청→수락 모델이고, 서비스가 쓰는 말은
  /// 블렌드다(함께 달리면 색이 섞인다). 서버 응답 필드는 `friendCount`지만
  /// 화면에 나가는 말은 이쪽이다.
  static const profileBlendRunners = '블렌드 러너';

  static const profileBasicCollection = '기본 컬렉션';
  static const profileBlendCollection = '블렌드 컬렉션';
  static const profileFeed = '피드';

  /// 컬렉션 진행. `17/30` 꼴로 채운다.
  static String profileCollected(int owned, int total) => '$owned/$total';

  /// 블렌드 개수. `2개` 꼴.
  static String profileBlendCount(int count) => '$count개';

  static const profileBlendEmpty = '아직 블렌드가 없어요';
  static const profileBlendEmptyHint = '다른 러너와 함께 달리면 섞여요';
  static const profileFeedEmpty = '아직 올린 기록이 없어요';

  /// 잠긴 컬렉션 격자 위 안내. **무엇을 모으는지** 알려준다.
  static const profileCollectionHint = '함께 달리며 30색을 모아요';

  // ── 프로필 사진 ─────────────────────────────────────────────

  /// 아바타를 눌렀을 때 뜨는 시트의 제목.
  static const profilePhotoSheetTitle = '프로필 사진';
  static const profilePhotoPick = '앨범에서 선택';

  /// 지우기. **"삭제"라 쓰지 않는다** — 돌아가는 자리가 있다는 것을 말해준다.
  static const profilePhotoReset = '기본 이미지로';

  /// 아바타의 접근성 라벨. 눌러서 무엇을 하는지 화면 낭독기에 알린다.
  static const profilePhotoChangeLabel = '프로필 사진 바꾸기';

  static const profilePhotoUnsupported = 'jpg, png, webp만 올릴 수 있어요';
  static const profilePhotoTooLarge = '10MB보다 작은 사진을 골라주세요';

  /// 사진을 다루다 실패했다. **어디서 막혔는지는 말하지 않는다** —
  /// 사용자가 할 수 있는 일이 "다시 해보기" 하나라서 갈라 말할 이유가 없다.
  static const profilePhotoFailed = '사진을 바꾸지 못했어요. 다시 시도해주세요';

  // ── 닉네임 변경 ─────────────────────────────────────────────
  //
  // 규칙 문구(`2~16자`, `이미 누가 쓰고 있어요` 등)는 **온보딩과 같은 것을
  // 쓴다.** 같은 규칙을 두 벌로 적으면 한쪽만 고쳐지고, 사용자는 화면마다
  // 다른 말을 듣는다.

  /// 시트 제목이자 연필 배지의 접근성 라벨. **버튼과 같은 말을 쓴다** —
  /// 여는 곳과 끝내는 곳의 이름이 다르면 같은 일인지 알기 어렵다.
  static const profileNicknameChangeTitle = '닉네임 변경';
  static const profileNicknameChangeSubmit = '변경';

  /// 지금 쓰는 이름 그대로다.
  ///
  /// ⚠️ **중복확인을 보내지 않는다.** 보내면 서버가 "이미 사용 중"이라고
  /// 답하는데, 그 이름을 쓰고 있는 사람이 본인이라 경고가 될 수 없다.
  static const profileNicknameUnchanged = '지금 쓰고 있는 이름이에요';

  /// 바꾸다 실패했다. [profilePhotoFailed]와 같은 이유로 갈라 말하지 않는다.
  static const profileNicknameChangeFailed = '닉네임을 바꾸지 못했어요. 다시 시도해주세요';

  // ── 프로필 편집 (S22.1) ─────────────────────────────────────
  //
  // 라벨(`닉네임` `생년월일` `키 · 몸무게`)과 실패 문구는 **온보딩 것을 그대로
  // 쓴다.** 같은 값을 묻는 자리라 다른 말을 쓰면 사용자가 다른 것으로 읽는다.

  static const profileEditTitle = '프로필 편집';
  static const profileEditSave = '저장';

  /// 아바타 아래 문구. 정본 S22.1의 `프로필 사진 변경`을 줄였다.
  static const profileEditPhoto = '사진 바꾸기';

  static const profileIntroductionLabel = '한 줄 소개';
  static const profileIntroductionHint = '오늘도 달립니다';

  static const profileBodySection = '신체 정보';

  /// 온보딩을 마쳐야 바꿀 수 있다(서버 409 `ONBOARDING_NOT_COMPLETED`).
  /// 프로필 탭까지 온 사람에게는 나오지 않아야 하는 말이다.
  static const profileNicknameNotOnboarded = '프로필을 먼저 완성해주세요';

  /// 아직 값을 모른다.
  ///
  /// ⚠️ **`설정하기` 같은 말을 쓰지 않는다.** 서버에 값이 없는 것이 아니라
  /// **불러올 API가 없는 것**이라, 안 채운 사람에게 채우라고 말하는 셈이 된다.
  /// 온보딩에서 이미 넣은 값이다.
  static const profileEditUnknown = '—';

  /// 저장하지 않고 나가려 할 때.
  static const profileEditDiscardTitle = '바꾼 내용을 버릴까요';
  static const profileEditDiscardBody = '저장하지 않으면 방금 고친 값이 사라져요.';
  static const profileEditDiscardLeave = '나가기';
  static const profileEditDiscardStay = '계속 편집';

  /// 소개글 상한. 서버는 100자까지 받는다.
  static const profileIntroductionTooLong = '100자까지 쓸 수 있어요';
  // ── 1인 러닝 (S11 파생 · S13 · S15) ──────────────────────────
  //
  // 파티원이 없는 세션이다. 정본 S13의 3페이지 중 **지도와 실시간 기록 둘만**
  // 쓴다 — 파티원 비교 페이지는 매칭이 붙을 때 셋째 장으로 들어간다.

  /// GPS 첫 신호를 기다리는 동안. **잠긴 이유를 글로 말한다** —
  /// 색만으로 알리지 않는다(정본 C9).
  static const runWaitingFix = '위치를 찾고 있어요';
  static const runWaitingFixWhy = '신호를 잡기 전에 출발하면 초반 거리가 빠져요';
  static const runFixReady = '준비됐어요';
  static const runStartCta = '시작';

  // ── 카운트다운 (S11) ─────────────────────────────────────────
  //
  // 정본은 숫자 하나만 크게 띄운다(160px). 지도도 파티원도 숨긴다.
  // **이 3초 동안 서버에 붙는다** — 사용자는 기다리는 줄 모른다.

  /// 이전 러닝이 안 끝나 새로 시작할 수 없다. 서버 409.
  ///
  /// ⚠️ **"다시 시도"를 권하지 않는다.** 몇 번을 눌러도 같은 답이 온다 —
  /// 사용자가 이전 러닝을 정리해야 풀린다.
  static const runAlreadyInProgress = '이전 러닝이 아직 끝나지 않았어요';

  static const runAlreadyInProgressWhy = '앱이 갑자기 꺼졌다면 그때 러닝이 남아 있을 수 있어요.';

  static const runBackToHome = '홈으로';

  /// 연결이 없는 채로 달리는 중. **막지 않고 알리기만 한다.**
  static const runOffline = '서버에 연결하는 중이에요';

  static const runOfflineWhy = '기록은 계속 재고 있어요. 연결되면 자동으로 올라가요.';

  /// 위치 권한이 없을 때. 설정 앱으로 보낸다.
  static const runPermissionTitle = '위치 권한이 필요해요';
  static const runPermissionBody = '달린 거리와 경로를 재려면 위치를 알아야 해요.';
  static const runPermissionOpenSettings = '설정 열기';
  static const runServiceDisabled = '기기의 위치 기능이 꺼져 있어요';

  /// 러닝 중 지표 라벨.
  static const runPaceLabel = '페이스';
  static const runTimeLabel = '시간';
  static const runDistanceLabel = '거리';
  static const runCadenceLabel = '케이던스';
  static const runCaloriesLabel = '칼로리';

  /// 아직 잴 수 없는 값. **지어낸 숫자를 넣지 않는다** —
  /// 러닝 기록은 사용자가 믿고 보는 숫자다.
  static const runUnavailable = '--';

  static const runStopCta = '중지';
  static const runPausedTitle = '일시정지됨';
  static const runResumeCta = '계속 달리기';

  /// 종료는 **길게 눌러야** 한다. 실수로 끝내면 되돌릴 방법이 없다.
  static const runFinishHold = '길게 눌러 종료';

  /// 지도 페이지에 키가 없을 때. 나머지 기능은 그대로 돈다.
  static const runMapUnavailable = '지도를 불러올 수 없어요';

  static const runSummaryTitle = '러닝 완료';

  /// 요약에서는 **평균**을 본다. 그 순간의 페이스가 아니라 오늘 어떻게
  /// 달렸는지가 궁금한 자리다.
  static const runSummaryAveragePace = '평균 페이스';

  static const runSummaryHome = '홈으로';

  // ── 러닝 색 10범주 ───────────────────────────────────────────
  //
  // `RunHue`의 이름을 화면에 쓰는 말로 옮긴다. enum에 붙이지 않는 이유는
  // **`domain`이 순수 Dart여야 하고 UI 문구는 여기 모여야** 하기 때문이다.

  static const hueDistance = '거리';
  static const hueSpeed = '속도';
  static const hueEndurance = '지구력';
  static const hueConsistency = '꾸준함';
  static const hueCadence = '케이던스';
  static const hueInterval = '인터벌';
  static const hueHills = '언덕';
  static const hueRecovery = '회복';
  static const hueCompany = '동행';
  static const hueAdversity = '악조건';

  // ── 프로필 유도 바텀시트 ─────────────────────────────────────
  //
  // ⚠️ **닫히지 않는다.** 프로필 없이는 매칭도 기록도 돌아가지 않아서
  // 앱을 쓸 수 없다. 그래서 안내가 아니라 **관문**이다.
  //
  // 닫히지 않는 것을 화면이 스스로 밝혀야 한다 — 닫으려다 안 되는 것과
  // 처음부터 닫히지 않는다고 아는 것은 다르다.

  /// **막아선 이유를 먼저 말한다.** "완성해주세요"는 미룰 이유밖에 안 준다.
  static const profileSheetTitle = '프로필이 있어야\n달릴 수 있어요';

  /// 무엇이 열리는지와 **왜 필수인지**를 함께 든다.
  static const profileSheetBody =
      '닉네임과 페이스로 상대를 찾고 기록을 계산해요.\n비워두면 매칭을 시작할 수 없어요';

  static const profileSheetCta = '프로필 입력하기';

  // ── 설정 (S22.2) ────────────────────────────────────────────
  //
  // 정본과 세 곳이 다르다. 서버가 그렇게 되어 있다.
  //
  // - 알림이 3종(매칭·러닝·소셜)이 아니라 **하나**다 (`alertConsent`)
  // - 공개 범위가 3단이 아니라 **둘**이다 (`PUBLIC` / `FRIENDS`)
  // - `FRIENDS`를 **"친구"라고 부르지 않는다** — 이 파일 맨 위의 톤 규칙과
  //   `CLAUDE.md`가 정한 것이다. 요청→수락 모델이라 "팔로워"로 쓴다

  static const settingsTitle = '설정';

  static const settingsNotificationSection = '알림';

  static const settingsAlertConsent = '알림 허용';

  /// ⚠️ **지금은 이걸 켜도 알림이 오지 않는다.** 앱에 알림을 띄우는 코드가
  /// 아직 없다. 그래서 "받고 있어요"가 아니라 **받겠다는 의사**로 적는다.
  static const settingsAlertConsentWhy = '매칭과 러닝 소식을 받아요';

  static const settingsVisibilitySection = '공개 범위';

  static const settingsVisibilityPublic = '전체 공개';

  /// 서버 `FRIENDS`. 정본의 "팔로워공개"와 같은 것이다.
  static const settingsVisibilityFollowers = '팔로워에게만';

  static const settingsVisibilityPublicWhy = '누구나 프로필을 볼 수 있어요';

  static const settingsVisibilityFollowersWhy = '팔로워만 프로필을 볼 수 있어요';

  static const settingsAccountSection = '계정';

  static const settingsEmail = '이메일';

  static const settingsLoginMethod = '로그인';

  static const settingsLoginLocal = '이메일';
  static const settingsLoginKakao = '카카오';
  static const settingsLoginGoogle = '구글';

  /// 서버가 모르는 제공자를 보냈다. **비밀번호 메뉴는 숨는다.**
  static const settingsLoginUnknown = '확인 불가';

  static const settingsPassword = '비밀번호 변경';

  static const settingsTerms = '약관 및 개인정보처리방침';

  static const settingsSignOut = '로그아웃';

  static const settingsWithdraw = '회원 탈퇴';

  // ── 설정 · 실패와 확인 ───────────────────────────────────────

  static const settingsLoadFailed = '설정을 불러오지 못했어요';

  static const settingsRetry = '다시 시도';

  /// 낙관적 반영이 되돌아갔을 때. **무엇이 되돌아갔는지** 알 수 있어야 한다.
  static const settingsUpdateFailed = '바꾸지 못했어요. 다시 시도해주세요';

  static const settingsSessionExpired = '로그인이 만료됐어요. 다시 로그인해주세요';

  static const settingsSignOutTitle = '로그아웃할까요';

  static const settingsSignOutBody = '기록은 그대로 남아 있어요.';

  static const settingsCancel = '취소';

  /// 약관 문서 주소가 아직 정해지지 않았다. `LegalLinks`를 함께 본다.
  static const settingsTermsPending = '약관 문서를 준비하고 있어요';

  // ── 비밀번호 변경 ────────────────────────────────────────────
  //
  // ⚠️ **"재설정"이 아니라 "변경"이다.** 서버가 `currentPassword`를 요구한다 —
  // 지금 비밀번호를 알아야 바꿀 수 있다. 비밀번호를 **잊은** 사람을 위한
  // 흐름(이메일 인증 후 재설정)은 명세에 없다.
  //
  // 규칙 문구는 가입 화면과 같은 것을 쓴다 (`authPasswordGuide` 등) —
  // 같은 `PasswordRule`을 쓰므로 문구가 갈리면 그것이 곧 버그다.

  static const passwordChangeTitle = '비밀번호 변경';

  static const passwordCurrentLabel = '현재 비밀번호';

  static const passwordNewLabel = '새 비밀번호';

  static const passwordConfirmLabel = '새 비밀번호 확인';

  static const passwordChangeCta = '변경하기';

  static const passwordChanged = '비밀번호를 바꿨어요';

  static const passwordMismatch = '새 비밀번호가 서로 달라요';

  /// 서버 401 `INVALID_CURRENT_PASSWORD`.
  ///
  /// ⚠️ 같은 401인 세션 만료와 **다른 문구여야 한다.** 묶으면 비밀번호를 틀린
  /// 사람에게 "다시 로그인하세요"라고 말하게 된다.
  static const passwordWrongCurrent = '현재 비밀번호가 올바르지 않아요';

  /// 서버 409 `PASSWORD_NOT_SET`. 메뉴를 숨기므로 정상적으로는 오지 않는다.
  static const passwordNotLocal = '소셜 계정은 비밀번호를 바꿀 수 없어요';

  static const passwordChangeFailed = '바꾸지 못했어요. 다시 시도해주세요';

  // ── 회원 탈퇴 ────────────────────────────────────────────────
  //
  // **되돌릴 수 없다.** 무엇이 사라지고 무엇이 남는지 정확히 적는다 —
  // "정말요?"만 묻는 확인은 아무 정보도 주지 않는다.

  static const withdrawTitle = '정말 탈퇴할까요';

  /// 서버의 데이터 정책을 그대로 옮겼다. 기록·색은 지워지고, 이미 올린 글은
  /// 작성자만 가려진 채 남는다.
  static const withdrawBody =
      '기록과 색이 모두 사라져요. 되돌릴 수 없어요.\n'
      '이미 올린 피드는 작성자가 가려진 채 남아요.';

  static const withdrawConfirm = '탈퇴하기';

  static const withdrawFailed = '탈퇴하지 못했어요. 다시 시도해주세요';
}
