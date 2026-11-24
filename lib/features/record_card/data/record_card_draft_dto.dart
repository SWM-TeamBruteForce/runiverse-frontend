/// 초안 발급(9-1)과 수정(9-3)이 주는 **올릴 자리**를 읽는다.
///
/// 이 값 하나로 S3 업로드와 확정(9-2)이 돌아간다 — [CardDraftIssued.draftId]가
/// 확정에 쓰이고, [CardDraftIssued.uploads]가 어디에 무엇을 올릴지 말한다.
abstract final class RecordCardDraftDto {
  const RecordCardDraftDto._();

  /// 9-1의 200 응답.
  static CardDraftIssued from(Map<String, dynamic> json) => CardDraftIssued(
    draftId: json['recordCardDraftId'] as String,
    // ⚠️ **오프셋 없는 KST다.** `.toUtc()`를 붙이면 9시간 밀려, 아직 살아
    // 있는 초안을 만료된 것으로 읽는다.
    expiresAt: DateTime.parse(json['expiresAt'] as String),
    uploads: [
      if (json['uploads'] case final List slots)
        for (final slot in slots)
          if (slot is Map<String, dynamic>) _slot(slot),
    ],
  );

  /// 9-3(PATCH)의 200 응답에 든 `draft`. **없으면 저장이 끝난 것이다.**
  static CardDraftIssued? draftOf(Map<String, dynamic> json) =>
      switch (json['draft']) {
        final Map<String, dynamic> draft => from(draft),
        _ => null,
      };

  static CardUploadSlot _slot(Map<String, dynamic> json) => CardUploadSlot(
    imageId: json['recordCardImageId'] as String,
    // ⚠️ **모르는 값을 `SINGLE`로 뭉개지 않는다.** 조각내 올려야 하는 것을
    // 한 번에 올리면 S3가 받아 주고 확정이 거절한다 — 그때는 어느 사진이
    // 문제인지 알 길이 없다.
    uploadType: json['uploadType'] as String? ?? '',
    uploadUrl: json['uploadUrl'] as String? ?? '',
    thumbnailUploadUrl: json['thumbnailUploadUrl'] as String?,
  );
}

/// 발급받은 초안 하나.
class CardDraftIssued {
  const CardDraftIssued({
    required this.draftId,
    required this.expiresAt,
    required this.uploads,
  });

  final String draftId;

  /// **30분**이다(가이드 7절). 그 안에 업로드와 확정을 마쳐야 한다.
  final DateTime expiresAt;

  /// 요청에 실은 **새 사진 순서 그대로** 온다.
  final List<CardUploadSlot> uploads;
}

/// 사진 한 장을 올릴 자리.
class CardUploadSlot {
  const CardUploadSlot({
    required this.imageId,
    required this.uploadType,
    required this.uploadUrl,
    required this.thumbnailUploadUrl,
  });

  /// `record_card_image_id`. 업로드가 끝나는 순서가 달라도 이것으로 사진을
  /// 가린다.
  final String imageId;

  /// `SINGLE` 또는 `MULTIPART`.
  final String uploadType;

  final String uploadUrl;

  /// 썸네일 자리. 서버가 원본 키에서 계산하므로 앱은 여기에 올리기만 한다.
  final String? thumbnailUploadUrl;

  /// 한 번에 올릴 수 있나. `MULTIPART`면 조각내야 하는데 그 길은 없다.
  bool get isSingle => uploadType == 'SINGLE';
}
