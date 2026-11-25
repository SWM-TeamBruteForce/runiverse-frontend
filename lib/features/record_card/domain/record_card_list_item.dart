/// 프로필 그리드·전체 보기의 **한 칸** (10-3).
///
/// ## ⚠️ 경로가 없다
///
/// 연동 가이드 5절: "경로 선은 달력·상세 응답에서 제공됩니다." 그래서 썸네일이
/// 없는 카드(사진을 다 지운 카드)는 **선을 그릴 수 없고 기본 이미지**를 쓴다 —
/// 달력 칸과 다른 점이고, 달력은 요약에 경로를 함께 받는다.
class RecordCardListItem {
  const RecordCardListItem({
    required this.id,
    required this.startedAt,
    required this.distanceMeters,
    required this.imageCount,
    this.thumbnailUrl,
  });

  /// `recordCardId`. 누르면 이 번호로 상세(8-1)를 연다.
  final String id;

  /// 그 러닝의 시작 시각. **오프셋 없는 KST다.**
  final DateTime startedAt;

  /// 그 러닝의 총 이동 거리(m).
  final int distanceMeters;

  /// 붙인 사진 수. 0장일 수 있다.
  final int imageCount;

  /// 칸에 깔 그림. **없으면 `null`이다** — 기본 이미지를 쓴다.
  ///
  /// ⚠️ **1시간 뒤 만료된다**(가이드 7절). `403`을 받으면 10-3을 다시 불러
  /// 새 주소를 받는다.
  final String? thumbnailUrl;
}

/// 한 번에 받은 한 페이지.
///
/// ## ⚠️ `nextCursor`가 "더 있다"의 유일한 근거다
///
/// 묶음 6까지는 **한 장 더 받아** 보고 가늠했다(6장 + "더 있나" 한 장).
/// 서버가 커서를 주므로 그 꾀가 필요 없다 — 딱 여섯 장인 사람에게 `더 보기`가
/// 서지 않는다.
class RecordCardListPage {
  const RecordCardListPage({required this.items, this.nextCursor});

  /// 빈 페이지는 **오류가 아니다**(가이드 5절 4번).
  static const empty = RecordCardListPage(items: []);

  final List<RecordCardListItem> items;

  /// 다음 페이지를 받을 커서. `null`이면 **여기가 끝이다.**
  final String? nextCursor;

  bool get hasMore => nextCursor != null;
}
