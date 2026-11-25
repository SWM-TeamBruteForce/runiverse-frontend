/// 곡 하나가 어디까지 갔나. **카드가 아니라 곡마다 하나다.**
///
/// ## ⚠️ 상태가 셋뿐이다
///
/// 서버가 주는 값이 `GENERATING`·`COMPLETED`·`FAILED` 셋이다(연동 가이드 2절).
/// 묶음 5까지 있었던 `none`·`queued`·`processing`·`succeeded`는 **사라졌다** —
/// 음악을 끄는 길이 없어졌고(저장하면 늘 만든다), 큐와 처리를 가르는 값도
/// 응답에 없다.
enum MusicStatus {
  /// 만들고 있다. **이 동안에는 상세를 다시 읽어야 한다** — 완료를 알리는
  /// 푸시도 SSE도 없다(가이드 7절).
  generating,

  /// 다 됐다. [CardMusic.url]로 틀 수 있다.
  completed,

  /// 못 만들었다. **그 장만** 음악 없이 선다 — 카드 전체가 죽지 않는다.
  failed,
}

/// 곡 하나.
///
/// ## ⚠️ 카드 하나에 여러 곡이다
///
/// 기본곡 하나와 **사진마다 한 곡**이다(가이드 2절). 사진 5장이면 6곡이고,
/// 곡마다 상태가 따로 온다 — 묶음 5까지는 묶음 전체에 상태가 하나여서 "1곡만
/// 실패해도 카드 전체가 실패"였다. 지금은 **그 장만** 음악 없이 선다.
class CardMusic {
  const CardMusic({required this.status, this.url});

  final MusicStatus status;

  /// 재생 주소. `COMPLETED`가 아니면 `null`이다.
  ///
  /// ⚠️ **1시간 뒤 만료된다**(가이드 7절). `403`을 받으면 상세(8-1)를 다시
  /// 불러 새 주소를 받는다.
  ///
  /// ⚠️ **아직 쓰지 않는다.** 오디오 패키지를 안 넣는다(설계 9절) — `재생`은
  /// 포토북이 장을 넘기는 것이고, 소리가 붙는 날 이 값이 쓰인다.
  final String? url;

  /// 만들고 있나. **이 동안 상세를 다시 읽는다.**
  bool get isWorking => status == MusicStatus.generating;

  /// 틀 수 있나. 주소가 없으면 다 됐어도 틀 수 없다.
  bool get isPlayable => status == MusicStatus.completed && url != null;

  bool get hasFailed => status == MusicStatus.failed;
}

/// 포토북이 한 장을 세워 두는 시간.
///
/// 백엔드 AI 계약이 정한 값이다(설계 3절). 소리가 붙으면 넘기는 조건의
/// **출처만** 실제 재생 끝 신호로 바뀐다 — 이 값은 그때 쓰이지 않는다.
abstract final class CardMusicTiming {
  const CardMusicTiming._();

  /// 경로 장(기본곡). **회고와 러닝 지표로 만든다.**
  static const baseDuration = Duration(seconds: 30);

  /// 사진 한 장. **그 사진과 캡션으로 만든다.**
  static const photoDuration = Duration(seconds: 10);

  /// 포토북 [page]번째 장이 서 있는 길이.
  ///
  /// 0번이 경로 선 아트고 그 뒤가 사진이다(`CardMediaPager`).
  static Duration durationOfPage(int page) =>
      page == 0 ? baseDuration : photoDuration;
}
