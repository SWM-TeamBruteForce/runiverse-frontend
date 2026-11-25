/// 그 러닝이 어떤 자리였나. 카드 하나에 하나다.
///
/// ## ⚠️ 코드는 네 곳이 같아야 한다
///
/// API · DB · AI · S3 경로가 **같은 대문자 코드**를 쓴다
/// (`AI 기능 아키텍처 및 data 입출력` 3절). 음악 파일이
/// `audio/{user_id}/{activity_type}/...`에 저장되므로, 나중에 값을 바꾸면
/// 이미 만들어진 음악의 경로와 어긋난다.
///
/// ⚠️ **DB 컬럼명은 `activity`인데 API·AI 필드명은 `activity_type`이다.**
/// 의도한 것인지 백엔드에 물어 두었다
/// (`docs/notes/2026-11-16-record-card-backend-questions.md` 3번).
enum RecordCardActivity {
  daily('DAILY'),
  race('RACE'),
  travel('TRAVEL');

  const RecordCardActivity(this.wire);

  /// 서버로 오가는 코드.
  final String wire;

  /// 서버 값을 읽는다. **모르는 값이면 `null`이다.**
  ///
  /// ⚠️ 아무 값으로도 뭉개지 않는다 — `RunKind.of`와 같은 이유다. 모르는 유형을
  /// `daily`로 읽으면 대회에서 뛴 기록이 일상으로 보이고, 필터가 거짓말을 한다.
  /// 허용값은 아직 백엔드와 확정 전이라 모르는 값이 실제로 올 수 있다.
  static RecordCardActivity? of(Object? wire) => switch (wire) {
    'DAILY' => RecordCardActivity.daily,
    'RACE' => RecordCardActivity.race,
    'TRAVEL' => RecordCardActivity.travel,
    _ => null,
  };
}
