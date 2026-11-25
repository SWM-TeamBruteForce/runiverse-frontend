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
  final String? url;

  /// 만들고 있나. **이 동안 상세를 다시 읽는다.**
  bool get isWorking => status == MusicStatus.generating;

  /// 틀 수 있나. 주소가 없으면 다 됐어도 틀 수 없다.
  bool get isPlayable => status == MusicStatus.completed && url != null;

  bool get hasFailed => status == MusicStatus.failed;
}

/// 플레이어에 물려 있는 곡이 무엇인지 가르는 값. [page]번째 장의 [music]이다.
///
/// ## ⚠️ 주소를 그대로 비교하면 안 된다
///
/// 서명 주소는 **같은 파일이어도 읽을 때마다 달라진다.** 만드는 중인 카드는
/// 상세를 1분마다 다시 읽으므로, 주소로 견주면 1분마다 플레이어를 다시 물어
/// **소리가 끊긴다**(설계 7-1).
///
/// 그래서 **`?` 앞만** 본다 — 사진이 쓰는 방법과 같다
/// (`ProfilePhotoImage.cacheKeyOf`).
///
/// ## ⚠️ 상태도 함께 본다
///
/// 서버가 다시 만들면서 **같은 오브젝트 키를 덮어쓸 수 있다.** 그때 경로만
/// 보면 새로 만든 곡을 영영 안 튼다. 다시 만들기는 `COMPLETED` → `GENERATING`
/// → `COMPLETED`를 지나가므로, 상태를 끼워 두면 그 길에 신원이 달라진다.
String trackIdOf({required int page, required CardMusic music}) {
  final url = music.url ?? '';
  final query = url.indexOf('?');
  final path = query < 0 ? url : url.substring(0, query);
  return '$page|${music.status.name}|$path';
}
