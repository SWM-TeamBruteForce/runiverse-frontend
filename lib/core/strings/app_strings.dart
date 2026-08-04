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
  // 마케팅 정보 수신은 뺐다. 그래서 남은 3항목이 전부 필수다.
  // `[선택]` 항목이 다시 생기면 [termsOptional]을 여기 추가한다.

  static const termsTitle = '약관에\n동의해주세요';
  static const termsSubtitle = '매칭과 기록 분석에 필요한\n최소 정보만 받아요';

  /// 카드형 일괄 토글. 3번 탭할 것을 1번으로 줄인다.
  static const termsAgreeAll = '전체 동의';

  /// 배지 문구. 대괄호나 알약 같은 **모양은 위젯이 정한다.**
  /// 문자열에 `[]`를 넣으면 배지 디자인이 바뀔 때 여기까지 고쳐야 한다.
  static const termsRequired = '필수';

  static const termsService = '서비스 이용약관';
  static const termsPrivacy = '개인정보 수집·이용';
  static const termsHealth = '생체·운동 정보';

  /// 위치 권한을 지금 묻지 않는 이유를 미리 알린다.
  /// 권한 요청은 실제로 필요한 맥락(매칭 등록)에서 해야 수락률이 높다.
  static const termsLocationNotice = '위치 권한은 매칭을\n시작할 때 여쭤봐요';

  /// 3항목 전부 동의해야 눌린다.
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

  // 닉네임
  static const profileNicknameLabel = '닉네임';
  static const profileNicknameQuestion = '뭐라고 부를까요';
  static const profileNicknameWhy = '함께 달리는 러너에게 보이는 이름이에요.';
  static const profileNicknameHint = '러너42';
  static const profileNicknameGuide = '2~12자로 지어주세요';
  static const profileNicknameTooShort = '2자 이상이어야 해요';

  /// 상한에서 막혔을 때 잠깐 떴다 사라진다.
  static const profileNicknameTooLong = '12자까지 쓸 수 있어요';

  static const profileNicknameOk = '쓸 수 있는 이름이에요';
  static const profileNicknameConfirm = '확인';

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

  static const authFailedEmailTaken = '이미 가입한 이메일이에요';

  // ── 이메일 인증 ──────────────────────────────────────────────
  //
  // 이메일 → 인증번호 → 비밀번호 순으로 한 화면에서 열린다.
  // 앞 단계를 마쳐야 다음 칸이 나타난다 — 세 칸을 한꺼번에 보여주면
  // 무엇부터 해야 하는지가 흐려진다.

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
  static const authFailedNotVerified = '이메일 인증을 먼저 해주세요';
}
