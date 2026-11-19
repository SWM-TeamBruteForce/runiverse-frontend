/// AI 음악이 어디까지 갔나. **카드 하나에 하나다.**
///
/// ## ⚠️ 곡별 상태가 없다
///
/// 서버의 `music_generations.status` 하나가 **묶음 전체**를 가리킨다
/// (설계 3절). 사진 5장이면 6곡이 만들어지는데, **1곡만 실패해도 카드 전체가
/// [failed]**이고 다시 만들기는 **전곡**이다. 그래서 "3번 사진 음악만 다시"
/// 같은 길이 없다.
enum MusicStatus {
  /// 한 번도 만들어 달라고 하지 않았다. **서버 값이 아니라 행이 없는 것**이다 —
  /// 음악을 끄고 저장했거나, 켜는 길을 아직 누르지 않았다.
  none,

  /// `QUEUED` — 큐에 들어갔다. ⚠️ **대기가 6시간까지 간다**(설계 3절).
  queued,

  /// `PROCESSING` — SageMaker가 돌고 있다. 처리에 900초까지 쓴다.
  processing,

  /// `SUCCEEDED` — **전곡이 다 됐다.** 하나라도 모자라면 이 값이 아니다.
  succeeded,

  /// `FAILED` — 묶음이 실패했다. 다시 만들면 **전곡**을 다시 만든다.
  failed,
}

/// 카드 한 장의 음악.
///
/// ## ⚠️ 곡을 목록으로 담지 않는다
///
/// 설계의 파일 목록이 "곡 목록"이라 적었지만, 지금 한 곡이 가진 것은
/// **길이**뿐이다 — 곡별 상태가 없고(3절) 재생 주소도 없다(9절: 오디오
/// 패키지를 안 넣는다). 길이는 **자리**로 정해진다(경로 장
/// [baseDuration], 사진 장 [photoDuration])므로 곡마다 들고 있을 것이 없다.
///
/// 곡마다 주소나 상태가 생기는 날 [trackCount]를 목록으로 늘린다.
class MusicGeneration {
  const MusicGeneration({
    required this.cardId,
    required this.status,
    required this.trackCount,
  });

  /// 아직 만든 적이 없는 카드.
  const MusicGeneration.none(this.cardId)
    : status = MusicStatus.none,
      trackCount = 0;

  /// 기본 음악 길이. **회고와 러닝 지표로 만든다.**
  ///
  /// 백엔드 AI 계약이 정한 값이다(설계 3절). 음악이 붙으면 넘기는 조건의
  /// **출처만** 실제 재생 끝 신호로 바뀐다 — 이 값은 그때 쓰이지 않는다.
  static const baseDuration = Duration(seconds: 30);

  /// 사진 한 장의 음악 길이. **그 사진과 캡션으로 만든다.**
  static const photoDuration = Duration(seconds: 10);

  final int cardId;

  final MusicStatus status;

  /// 만들어진(또는 만들어질) 곡 수. 만든 적이 없으면 0이다.
  final int trackCount;

  /// 사진 [photoCount]장인 카드의 곡 수.
  ///
  /// ⚠️ **사진 수가 아니다.** 사진이 없어도 기본 음악 한 곡이 있다 —
  /// `photos.length`로 적으면 사진 없는 카드가 0곡이 된다.
  static int trackCountFor(int photoCount) => photoCount + 1;

  /// 포토북 [page]번째 장이 서 있는 길이.
  ///
  /// 0번이 경로 선 아트고 그 뒤가 사진이다(`CardMediaPager`).
  static Duration durationOfPage(int page) =>
      page == 0 ? baseDuration : photoDuration;

  /// 지금 만들고 있나. **이 동안에는 다시 물어야 한다** — 완료를 알리는 방법이
  /// 아직 정해지지 않았다(설계 10절 10번).
  bool get isWorking =>
      status == MusicStatus.queued || status == MusicStatus.processing;

  /// 틀 수 있나. **전곡이 다 돼야 한다**(설계 3절).
  bool get isPlayable => status == MusicStatus.succeeded;
}
