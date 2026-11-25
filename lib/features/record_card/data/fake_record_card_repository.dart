import 'dart:math' as math;

import 'package:runiverse/features/record/domain/run_record.dart';
import 'package:runiverse/features/record_card/domain/card_music.dart';
import 'package:runiverse/features/record_card/domain/composable_record.dart';
import 'package:runiverse/features/record_card/domain/edit_record_card.dart';
import 'package:runiverse/features/record_card/domain/music_inputs.dart';
import 'package:runiverse/features/record_card/domain/new_record_card.dart';
import 'package:runiverse/features/record_card/domain/record_card.dart';
import 'package:runiverse/features/record_card/domain/record_card_activity.dart';
import 'package:runiverse/features/record_card/domain/record_card_list_item.dart';
import 'package:runiverse/features/record_card/domain/record_card_repository.dart';
import 'package:runiverse/features/record_card/domain/record_card_summary.dart';
import 'package:runiverse/features/record_card/domain/record_card_visibility.dart';
import 'package:runiverse/features/record_card/domain/route_art.dart';
import 'package:runiverse/features/session/domain/geo_point.dart';

/// 서버 없이 기록카드 탭을 세우기 위한 목.
///
/// ## ⚠️ 진짜 카드가 아니다
///
/// 3차 API 명세서의 `record-card` 엔드포인트 여섯 줄이 **본문이 비어 있어**
/// 붙일 서버가 없다. 화면이 갈라야 하는 경우가 전부 한 번씩 나오도록 **일부러**
/// 만든 값이다 — 사진 없는 카드, 다섯 장짜리, 하루에 둘인 날, 유형 셋,
/// 공개범위 셋.
///
/// 서버가 열리면 provider에서 `HttpRecordCardRepository`로 바꾼다. 이 파일은
/// 그때 테스트용으로 남는다.
///
/// ## ⚠️ 사진이 **번들 에셋 경로**다
///
/// 서버가 없어 열람 주소를 만들 수 없다. 그래서 `assets/images/...`를 그대로
/// 돌려주고, 그리는 쪽이 `assets/`로 시작하는 주소를 에셋으로 읽는다.
/// **HTTP 구현체가 붙으면 그 분기는 지운다.**
///
/// ## ⚠️ 러닝 기록 목을 건드리지 않는다
///
/// 카드가 지표·경로를 스스로 들고 있어 `FakeRunRecordRepository`에 매이지
/// 않는다. 그쪽 `_plan`을 손대면 **기록 탭의 주간·월 요약 눈검증 값이 같이
/// 바뀐다.**
class FakeRecordCardRepository implements RecordCardRepository {
  FakeRecordCardRepository({
    DateTime? today,
    this.delay = Duration.zero,
    this.failWith,
    this.clock = DateTime.now,
  }) : _today = today ?? DateTime.now();

  /// "오늘"을 어디로 볼 것인가. 목 데이터를 이 날 기준으로 만든다.
  final DateTime _today;

  /// 로딩 상태를 눈으로 보려고 두는 지연. 테스트에서는 0이다.
  final Duration delay;

  /// 지금 몇 시인가. **음악 상태를 시간으로 계산한다.**
  ///
  /// ⚠️ **타이머를 쓰지 않는 이유다.** 타이머로 흉내내면 테스트가 13초를
  /// 실제로 기다린다. 요청 시각만 적어 두고 흐른 시간으로 상태를 내면,
  /// 테스트는 시계를 밀고 기기는 진짜 시간을 쓴다.
  final DateTime Function() clock;

  /// 주면 **언제나 이 실패로 던진다.** 오류 화면을 눈으로 보는 길이다.
  ///
  /// 도중에 바꿀 수 있다 — "잘 보다가 한 번 끊겼다"를 흉내내는 데 쓴다.
  RecordCardFailure? failWith;

  /// 몇 번 불렸나. 화면이 받은 달을 다시 받는지 본다.
  var calls = 0;

  /// 물어본 구간들. 무엇을 받아 왔는지 보는 데 쓴다.
  final queries = <({DateTime from, DateTime to})>[];

  /// 러닝 기록 목록 + 카드 유무 (7-1).
  ///
  /// ## ⚠️ 맞춰 붙이는 일을 **여기서** 한다
  ///
  /// 묶음 6까지는 화면이 `joinCards`로 붙였다. 서버가 한 응답에 싣기로 하면서
  /// 그 일은 **서버의 것**이 됐고, 가짜가 서버 자리에 선다.
  ///
  /// ## ⚠️ 카드 없는 러닝도 낸다
  ///
  /// 달력은 **뛰었는데 카드를 안 쓴 날**에 운동화를 둔다(설계 6-1). 카드가
  /// 있는 날만 내면 그 길을 눈으로 볼 수 없다. [_runOnlyOffsets] 가 그 날들을
  /// 정한다 — 난수로 두면 "방금 그 화면"을 다시 못 본다.
  @override
  Future<List<ComposableRecord>> runsInRange({
    required DateTime from,
    required DateTime to,
  }) async {
    calls++;

    if (failWith != null) throw RecordCardException(failWith!);

    // ⚠️ **진짜와 같은 규칙으로 거절한다.** 가짜가 뭐든 받아 주면 화면이 구간을
    // 넓혀도 테스트가 다 통과하고, 기기에서만 400 이 난다.
    if (from.isAfter(to) ||
        to.difference(from).inDays >= RecordCardRepository.maxRangeDays) {
      throw const RecordCardException(RecordCardFailure.invalidRequest);
    }

    if (delay > Duration.zero) await Future<void>.delayed(delay);

    final start = DateTime(from.year, from.month, from.day);
    final end = DateTime(to.year, to.month, to.day);
    queries.add((from: start, to: end));

    bool inRange(DateTime day) => !day.isBefore(start) && !day.isAfter(end);

    final rows = <ComposableRecord>[
      for (final card in _live())
        if (inRange(card.day))
          ComposableRecord(
            record: _runOf(card),
            existingCard: summaryOf(card),
          ),
    ];

    final withCards = {for (final row in rows) row.day};
    for (final back in _runOnlyOffsets) {
      final day = DateTime(_today.year, _today.month, _today.day - back);
      if (!inRange(day) || withCards.contains(day)) continue;
      rows.add(ComposableRecord(record: _runOnly(day, back)));
    }

    return rows
      ..sort((a, b) => a.record.startedAt.compareTo(b.record.startedAt));
  }

  /// 카드를 안 쓴 러닝이 있는 날 — **오늘로부터 며칠 전**인가.
  static const _runOnlyOffsets = [1, 4, 9, 17, 23, 38, 52];

  /// 달력 칸이 쓰는 요약. **카드 전부가 아니다**(연동 가이드 1절).
  ///
  /// ⚠️ **경로를 50점으로 줄이지 않는다.** 서버는 줄여 보내지만, 줄이는 쪽을
  /// 가짜가 흉내내면 "기기에서만 선이 거칠다"가 아니라 그 반대 — 가짜에서만
  /// 거칠어진다. 점 수는 그리는 쪽이 견디면 되는 값이다.
  static RecordCardSummary summaryOf(RecordCard card) => RecordCardSummary(
    id: card.id,
    startedAt: card.startedAt,
    distanceMeters: card.distanceMeters,
    thumbnailUrl: card.thumbnailUrl,
    route: card.route,
    activity: card.activity,
  );

  /// 카드가 매달린 러닝 한 건. 카드가 든 값을 그대로 쓴다.
  static RunRecord _runOf(RecordCard card) => RunRecord(
    id: card.runningRecordId,
    // ⚠️ **방 번호를 기록 번호로 쓴다.** 가짜에는 방이 따로 없고, 러닝 요약이
    // `runningRoomId`로 그 줄을 찾으므로(가이드 6절) 값이 있어야 한다.
    runningRoomId: card.runningRecordId,
    startedAt: card.startedAt,
    distanceMeters: card.distanceMeters,
    duration: card.duration,
    averagePace: card.averagePace,
    playerCount: card.runners.isEmpty ? 1 : card.runners.length + 1,
  );

  /// 카드를 안 쓴 러닝 한 건.
  static RunRecord _runOnly(DateTime day, int seed) {
    final startedAt = DateTime(day.year, day.month, day.day, 7, 20);
    final meters = 3000 + seed * 137;
    final seconds = (meters / 1000 * 330).round();
    return RunRecord(
      id: 50000 + seed,
      runningRoomId: 50000 + seed,
      startedAt: startedAt,
      distanceMeters: meters,
      duration: Duration(seconds: seconds),
      averagePace: const Duration(minutes: 5, seconds: 30),
      playerCount: 1,
    );
  }

  /// 누가 무엇을 물었나. 그리드가 여섯 장만 묻는지 보는 데 쓴다.
  final userQueries = <({String userId, int? limit, String? cursor})>[];

  /// 한 번에 줄 수 있는 최대. 서버와 같은 값이다(연동 가이드 5절 3번).
  static const maxLimit = 50;

  /// 서버가 쓰는 기본값.
  static const defaultLimit = 20;

  /// 그 사람의 카드 한 페이지 (10-3).
  ///
  /// ⚠️ **커서는 "다음에 줄 첫 칸의 자리"다.** 카드 번호를 커서로 쓰면 그
  /// 사이에 그 카드가 지워졌을 때 이어 받을 데를 잃는다 — 가짜는 자리로 센다.
  ///
  /// ⚠️ **비공개도 준다.** 본인이 보는 자리라서다(사용자 결정 2026-11-24).
  /// 묶음 6까지는 가짜가 걸렀는데, 항목에 `visibility`가 없어 **앱이 가려낼
  /// 근거도 없다** — 서버가 보내면 그대로 선다.
  @override
  Future<RecordCardListPage> cardsOf({
    required String userId,
    int? limit,
    String? cursor,
  }) async {
    calls++;

    if (failWith != null) throw RecordCardException(failWith!);
    if (delay > Duration.zero) await Future<void>.delayed(delay);

    userQueries.add((userId: userId, limit: limit, cursor: cursor));

    final from = cursor == null ? 0 : int.tryParse(cursor);
    // 잘못된 커서와 1 미만은 `400`이다 — 진짜와 같은 규칙으로 거절한다.
    if (from == null || from < 0) {
      throw const RecordCardException(RecordCardFailure.invalidRequest);
    }
    if (limit != null && limit < 1) {
      throw const RecordCardException(RecordCardFailure.invalidRequest);
    }

    // 넘기면 깎는다 — 거절이 아니다(가이드 5절 3번).
    final size = (limit ?? defaultLimit).clamp(1, maxLimit);

    final all = _live()
      ..sort(
        // 최신순. 달력과 반대다.
        (a, b) => b.startedAt.compareTo(a.startedAt),
      );

    final page = all.skip(from).take(size).toList();
    final next = from + page.length;

    return RecordCardListPage(
      items: [
        for (final card in page)
          RecordCardListItem(
            id: card.id,
            startedAt: card.startedAt,
            distanceMeters: card.distanceMeters,
            imageCount: card.photos.length,
            thumbnailUrl: card.thumbnailUrl,
          ),
      ],
      // ⚠️ **끝에 닿았으면 `null`이다.** 빈 문자열을 주면 "더 있다"로 읽혀
      // 끝나지 않는 목록이 된다.
      nextCursor: next < all.length ? '$next' : null,
    );
  }

  /// 지금 **살아 있는** 카드 전부 — 목과 만든 것을 합치고, 고친 것으로 덮고,
  /// 지운 것을 뺀다. 날짜도 공개범위도 보지 않는다.
  ///
  /// ⚠️ **조회마다 따로 모으지 않는다.** 따로 모으면 지운 카드가 한쪽에만
  /// 남아, 달력에서는 사라졌는데 프로필에는 서는 카드가 생긴다.
  ///
  /// ⚠️ **고친 것이 있으면 그쪽을 준다.** `_all()`이 목을 매번 새로 만들어,
  /// 안 덮으면 고친 카드가 다음 조회에 되돌아간다.
  List<RecordCard> _live() => [
    for (final card in [..._all(), ..._created])
      if (!_deletedIds.contains(card.id)) _edited[card.id] ?? card,
  ];

  /// 이 앱이 만든 카드들. **앱을 끄면 사라진다.**
  ///
  /// ⚠️ 영속화하지 않는다 — 서버가 올 자리에 로컬 DB를 세우면 서버가 붙는 날
  /// 두 번 걷어내야 한다.
  final _created = <RecordCard>[];

  /// 몇 번 만들었나. 저장을 두 번 누르지 않았는지 보는 데 쓴다.
  var creates = 0;

  /// 카드 한 장 전부 (8-1).
  ///
  /// ⚠️ **목 카드는 전부 내 것이다.** 달력이 내 카드를 보여 주는 화면이고,
  /// 남의 카드를 흉내내는 것은 테스트가 [notMineIds]로 따로 지정한다.
  @override
  Future<RecordCard> detailOf(String cardId) async {
    if (delay > Duration.zero) await Future<void>.delayed(delay);
    if (failWith != null) throw RecordCardException(failWith!);

    final found = _find(cardId);
    if (found == null) {
      throw const RecordCardException(RecordCardFailure.notFound);
    }
    return _withMusic(_withMine(found, !notMineIds.contains(cardId)));
  }

  /// 남의 카드로 보이게 할 번호들. 테스트가 채운다.
  final notMineIds = <String>{};

  /// [RecordCard]에 `copyWith`가 없다 — 한 필드만 바꿔 다시 짓는다.
  ///
  /// `copyWith`를 더하지 않는 이유: 카드는 **서버가 주는 것을 그대로 드는**
  /// 값이라, 앱이 한 칸씩 고칠 일이 없다. 가짜가 소유자를 흉내내는 이 자리
  /// 하나뿐이다.
  static RecordCard _withMine(RecordCard card, bool mine) => RecordCard(
    id: card.id,
    runningRecordId: card.runningRecordId,
    startedAt: card.startedAt,
    activity: card.activity,
    visibility: card.visibility,
    reviewText: card.reviewText,
    photos: card.photos,
    route: card.route,
    distanceMeters: card.distanceMeters,
    duration: card.duration,
    averagePace: card.averagePace,
    runners: card.runners,
    isMine: mine,
  );

  @override
  Future<RecordCard> create(NewRecordCard card) async {
    creates++;

    if (delay > Duration.zero) await Future<void>.delayed(delay);
    if (failWith != null) throw RecordCardException(failWith!);

    // ⚠️ **목 데이터와 번호가 겹치면 안 된다.** 겹치면 달력이 두 장을 한 장으로
    // 보고 상세가 엉뚱한 것을 연다. 목은 `card-`로 시작하고 여기는 `new-`라
    // **접두사만으로 겹칠 수 없다** — 숫자로 셀 때처럼 "9000 위에서 센다"는
    // 약속을 지킬 필요가 없다.
    final id = 'new-${_nextCardId++}';
    final made = RecordCard(
      id: id,
      runningRecordId: card.record.id,
      startedAt: card.record.startedAt,
      activity: card.activity,
      visibility: card.visibility,
      reviewText: card.reviewText,
      photos: [
        for (var i = 0; i < card.photos.length; i++)
          RecordCardPhoto(
            id: '$id-img$i',
            url: card.photos[i].path,
            thumbnailUrl: card.photos[i].thumbnailPath,
            caption: card.photos[i].caption,
          ),
      ],
      route: card.route,
      distanceMeters: card.record.distanceMeters,
      duration: card.record.duration,
      averagePace: card.record.averagePace,
      // ⚠️ **비어 있다.** `RunRecord`는 `playerCount`만 알고 함께 뛴 사람의
      // 닉네임·프로필은 모른다. 서버가 붙으면 응답이 싣는다(설계 3절).
      runners: const [],
    );
    _created.add(made);
    // ⚠️ **늘 건다.** 서버는 카드를 확정할 때 기본곡과 사진별 곡 생성을
    // 항상 요청한다(연동 가이드 3절) — 끄는 길이 없다. 가짜도 같은 자리에서
    // 같이 건다. 저장하고 상세로 가면 줄이 `준비 중…`으로 서 있다.
    _musicRequestedAt[id] = clock();
    return made;
  }

  /// 만든 카드에 붙일 다음 번호. `new-1`, `new-2`로 센다 — 목 데이터는
  /// `card-`로 시작해 겹치지 않는다.
  var _nextCardId = 1;

  /// 고쳐진 카드들. **목 데이터도 고칠 수 있어야 한다** — `_all()`이 매번 목을
  /// 새로 만들어서, 여기 없으면 고친 것이 다음 조회에 되돌아간다.
  final _edited = <String, RecordCard>{};

  /// 몇 번 고쳤나.
  var updates = 0;

  @override
  Future<RecordCard> update(EditRecordCard card) async {
    updates++;

    if (delay > Duration.zero) await Future<void>.delayed(delay);
    if (failWith != null) throw RecordCardException(failWith!);

    final before = _find(card.cardId);
    if (before == null) {
      throw const RecordCardException(RecordCardFailure.notFound);
    }

    final made = RecordCard(
      id: before.id,
      runningRecordId: before.runningRecordId,
      startedAt: before.startedAt,
      activity: card.activity,
      visibility: card.visibility,
      reviewText: card.reviewText,
      // ⚠️ **받은 것이 남길 전체다.** 빠진 것은 지워진 것이다.
      photos: [
        for (var i = 0; i < card.photos.length; i++)
          _photoOf(card.photos[i], before: before, index: i),
      ],
      route: before.route,
      distanceMeters: before.distanceMeters,
      duration: before.duration,
      averagePace: before.averagePace,
      runners: before.runners,
    );
    _edited[made.id] = made;
    // ⚠️ **활성 요청을 무효화하고 전곡을 다시 만든다**(설계 3절). 입력이
    // 그대로면(공개범위만 바꿨다면) 건드리지 않는다.
    if (MusicInputs.ofEdit(card) != MusicInputs.ofCard(before)) {
      _musicWillFail.remove(made.id);
      _musicRequestedAt[made.id] = clock();
    }
    return made;
  }

  /// 남길 사진 하나를 카드의 사진으로. 이미 있던 것이면 **주소를 지킨다.**
  RecordCardPhoto _photoOf(
    EditCardPhoto photo, {
    required RecordCard before,
    required int index,
  }) {
    final savedId = photo.savedId;
    if (savedId != null) {
      final kept = before.photos.where((p) => p.id == savedId).firstOrNull;
      return RecordCardPhoto(
        id: savedId,
        url: kept?.url ?? '',
        thumbnailUrl: kept?.thumbnailUrl,
        caption: photo.caption,
      );
    }
    return RecordCardPhoto(
      id: '${before.id}-add$index',
      url: photo.path!,
      thumbnailUrl: photo.thumbnailPath,
      caption: photo.caption,
    );
  }

  /// 지워진 카드 번호들.
  ///
  /// ⚠️ **목 데이터도 지울 수 있어야 한다.** `_all()`이 매번 목을 새로 만들어,
  /// 거르지 않으면 지운 카드가 다음 조회에 되살아난다.
  final _deletedIds = <String>{};

  /// 몇 번 지웠나.
  var deletes = 0;

  @override
  Future<void> delete(String cardId) async {
    deletes++;

    if (delay > Duration.zero) await Future<void>.delayed(delay);
    if (failWith != null) throw RecordCardException(failWith!);

    if (_find(cardId) == null) {
      throw const RecordCardException(RecordCardFailure.notFound);
    }

    _deletedIds.add(cardId);
    _edited.remove(cardId);
    _created.removeWhere((card) => card.id == cardId);
    _musicRequestedAt.remove(cardId);
    _musicWillFail.remove(cardId);
  }

  // ── 음악 흉내 (설계 8절) ───────────────────────────────────────

  /// 카드별 **마지막 요청 시각**. 없으면 한 번도 요청하지 않은 것이다.
  final _musicRequestedAt = <String, DateTime>{};

  /// 이 요청은 끝에서 떨어뜨릴 것. [musicRequests]의 20번째다.
  final _musicWillFail = <String>{};

  /// 몇 번 만들어 달라고 했나.
  var musicRequests = 0;

  /// 몇 번 물었나. **폴링이 멈추는지 보는 데 쓴다.**
  var musicCalls = 0;

  /// 요청한 곡이 다 되는 데 걸리는 시간. **요청 시각 기준**이다.
  static const _toDone = Duration(seconds: 13);

  /// 못 만든 곡을 다시 만들어 달라고 한다 (9-6).
  ///
  /// ⚠️ **실패한 곡이 없어도 성공한다.** 진짜 서버가 `FAILED`인 곡만 골라
  /// 다시 걸고, 하나도 없으면 아무것도 하지 않고 `204`를 준다.
  @override
  Future<void> retryMusic(String cardId) async {
    musicRequests++;

    if (delay > Duration.zero) await Future<void>.delayed(delay);
    if (failWith != null) throw RecordCardException(failWith!);

    final card = _find(cardId);
    if (card == null) {
      throw const RecordCardException(RecordCardFailure.notFound);
    }

    // ⚠️ **난수로 떨구지 않는다.** 재현되지 않는 가짜 실패는 눈검증을 망친다 —
    // "방금 그 실패"를 다시 볼 수 없다. 강제 실패는 [failWith]가 이미 한다.
    if (musicRequests % 20 == 0) {
      _musicWillFail.add(cardId);
    } else {
      _musicWillFail.remove(cardId);
    }
    _musicRequestedAt[cardId] = clock();
  }

  /// 이 카드의 곡들을 지금 상태로 얹어 돌려준다.
  ///
  /// ⚠️ **상세가 음악을 싣는다**(연동 가이드 2절). 따로 묻는 길이 없으므로
  /// 가짜도 상세에 실어 준다.
  RecordCard _withMusic(RecordCard card) {
    final base = _trackOf(card, 0);
    return RecordCard(
      id: card.id,
      runningRecordId: card.runningRecordId,
      startedAt: card.startedAt,
      activity: card.activity,
      visibility: card.visibility,
      reviewText: card.reviewText,
      photos: [
        for (var i = 0; i < card.photos.length; i++)
          RecordCardPhoto(
            id: card.photos[i].id,
            url: card.photos[i].url,
            thumbnailUrl: card.photos[i].thumbnailUrl,
            caption: card.photos[i].caption,
            isThumbnail: card.photos[i].isThumbnail,
            music: _trackOf(card, i + 1),
          ),
      ],
      route: card.route,
      distanceMeters: card.distanceMeters,
      duration: card.duration,
      averagePace: card.averagePace,
      runners: card.runners,
      isMine: card.isMine,
      baseMusic: base,
    );
  }

  /// 곡 하나. [track]이 0이면 기본곡, 그 뒤가 사진 순서다.
  ///
  /// ⚠️ **요청 기록이 있으면 그쪽이 먼저다.** 목에 심어 둔 상태는 한 번도
  /// 요청하지 않은 카드에만 쓴다 — 안 그러면 재요청해도 심어 둔 실패가 그대로
  /// 남아 "눌렀는데 아무 일도 없다"가 된다.
  CardMusic? _trackOf(RecordCard card, int track) {
    final requestedAt = _musicRequestedAt[card.id];
    if (requestedAt == null) return _seededTrack(card, track);

    if (clock().difference(requestedAt) < _toDone) {
      return const CardMusic(status: MusicStatus.generating);
    }
    if (_musicWillFail.contains(card.id)) {
      // ⚠️ **AI가 실패하면 그 요청에 든 사진 곡과 기본곡이 함께 실패한다**
      // (가이드 4절). 한 곡만 떨구면 진짜와 다르다.
      return const CardMusic(status: MusicStatus.failed);
    }
    return CardMusic(
      status: MusicStatus.completed,
      url: _musicUrl(card.id, track),
    );
  }

  /// 목 카드에 심어 둔 곡.
  ///
  /// ⚠️ **세 상태를 기다리지 않고 보려고** 일부러 갈라 둔다 — 전부 완료면
  /// `만드는 중…`·`만들지 못했어요` 줄을 한 번도 못 보고 넘어간다.
  ///
  /// `card-1000`은 **기본곡은 다 됐고 첫 사진만 만드는 중**이다. 곡별 상태가
  /// 생긴 뒤에야 볼 수 있는 모양이라, 그것을 눈으로 확인하는 자리다.
  CardMusic? _seededTrack(RecordCard card, int track) => switch (card.id) {
    'card-1000' when track == 1 => const CardMusic(
      status: MusicStatus.generating,
    ),
    'card-1001' => const CardMusic(status: MusicStatus.failed),
    // 서버가 아직 아무 곡도 주지 않은 카드. 받아 오는 중과 구별하는 자리다.
    'card-1002' => null,
    _ => CardMusic(
      status: MusicStatus.completed,
      url: _musicUrl(card.id, track),
    ),
  };

  static String _musicUrl(String cardId, int track) =>
      'https://example.invalid/music/$cardId/$track.m4a';

  /// 지금 있는 그 카드. 고친 것이 있으면 그쪽이고, 지워졌으면 `null`이다.
  RecordCard? _find(String id) {
    if (_deletedIds.contains(id)) return null;
    return _edited[id] ??
        [..._all(), ..._created].where((c) => c.id == id).firstOrNull;
  }

  /// 오늘로부터 며칠 전 · 몇 시 · 유형 · 사진 수 · 공개범위 · 거리(m) · 시간(초).
  ///
  /// ⚠️ **`daysAgo`가 46을 넘지 않게 둔다.** 두 달치를 보여 주려는 값이라, 더
  /// 멀어지면 세 번째 달이 한 장만 있는 채로 끼어든다.
  static const _plan =
      <
        ({
          int daysAgo,
          int hour,
          RecordCardActivity activity,
          int photos,
          RecordCardVisibility visibility,
          int meters,
          int seconds,
        })
      >[
        (
          daysAgo: 0,
          hour: 7,
          activity: RecordCardActivity.daily,
          photos: 1,
          visibility: RecordCardVisibility.friends,
          meters: 5400,
          seconds: 1690,
        ),
        (
          daysAgo: 1,
          hour: 19,
          activity: RecordCardActivity.daily,
          photos: 0,
          visibility: RecordCardVisibility.private,
          meters: 3100,
          seconds: 1120,
        ),
        (
          daysAgo: 3,
          hour: 6,
          activity: RecordCardActivity.travel,
          photos: 5,
          visibility: RecordCardVisibility.public,
          meters: 8200,
          seconds: 2640,
        ),
        (
          daysAgo: 5,
          hour: 8,
          activity: RecordCardActivity.daily,
          photos: 2,
          visibility: RecordCardVisibility.friends,
          meters: 4600,
          seconds: 1500,
        ),
        // ⚠️ 위와 같은 날이다. 하루에 두 번 뛰면 카드도 둘이다.
        (
          daysAgo: 5,
          hour: 21,
          activity: RecordCardActivity.daily,
          photos: 1,
          visibility: RecordCardVisibility.private,
          meters: 2800,
          seconds: 960,
        ),
        (
          daysAgo: 8,
          hour: 9,
          activity: RecordCardActivity.race,
          photos: 4,
          visibility: RecordCardVisibility.public,
          meters: 10000,
          seconds: 2880,
        ),
        (
          daysAgo: 11,
          hour: 18,
          activity: RecordCardActivity.daily,
          photos: 0,
          visibility: RecordCardVisibility.friends,
          meters: 5200,
          seconds: 1760,
        ),
        (
          daysAgo: 14,
          hour: 7,
          activity: RecordCardActivity.travel,
          photos: 3,
          visibility: RecordCardVisibility.public,
          meters: 6400,
          seconds: 2100,
        ),
        (
          daysAgo: 17,
          hour: 20,
          activity: RecordCardActivity.daily,
          photos: 1,
          visibility: RecordCardVisibility.private,
          meters: 3700,
          seconds: 1290,
        ),
        (
          daysAgo: 19,
          hour: 6,
          activity: RecordCardActivity.daily,
          photos: 2,
          visibility: RecordCardVisibility.friends,
          meters: 5000,
          seconds: 1650,
        ),
        (
          daysAgo: 22,
          hour: 10,
          activity: RecordCardActivity.race,
          photos: 5,
          visibility: RecordCardVisibility.public,
          meters: 21097,
          seconds: 7020,
        ),
        (
          daysAgo: 25,
          hour: 19,
          activity: RecordCardActivity.daily,
          photos: 0,
          visibility: RecordCardVisibility.private,
          meters: 4200,
          seconds: 1470,
        ),
        (
          daysAgo: 28,
          hour: 8,
          activity: RecordCardActivity.travel,
          photos: 3,
          visibility: RecordCardVisibility.friends,
          meters: 7300,
          seconds: 2460,
        ),
        (
          daysAgo: 31,
          hour: 7,
          activity: RecordCardActivity.daily,
          photos: 1,
          visibility: RecordCardVisibility.friends,
          meters: 5600,
          seconds: 1840,
        ),
        (
          daysAgo: 34,
          hour: 21,
          activity: RecordCardActivity.daily,
          photos: 0,
          visibility: RecordCardVisibility.private,
          meters: 3300,
          seconds: 1200,
        ),
        (
          daysAgo: 37,
          hour: 9,
          activity: RecordCardActivity.travel,
          photos: 4,
          visibility: RecordCardVisibility.public,
          meters: 9100,
          seconds: 3000,
        ),
        (
          daysAgo: 40,
          hour: 18,
          activity: RecordCardActivity.daily,
          photos: 2,
          visibility: RecordCardVisibility.friends,
          meters: 4800,
          seconds: 1620,
        ),
        (
          daysAgo: 43,
          hour: 6,
          activity: RecordCardActivity.race,
          photos: 1,
          visibility: RecordCardVisibility.public,
          meters: 10000,
          seconds: 2760,
        ),
        (
          daysAgo: 45,
          hour: 20,
          activity: RecordCardActivity.daily,
          photos: 0,
          visibility: RecordCardVisibility.private,
          meters: 2600,
          seconds: 900,
        ),
        (
          daysAgo: 46,
          hour: 7,
          activity: RecordCardActivity.daily,
          photos: 3,
          visibility: RecordCardVisibility.friends,
          meters: 6100,
          seconds: 2040,
        ),
      ];

  /// 돌려 쓰는 번들 사진. 서버가 없어 열람 주소를 만들 수 없다.
  ///
  /// ⚠️ **진짜 사진만 쓴다.** `home_*.webp`와 `onboarding_together.png`는 사진이
  /// 아니라 **앱 화면을 찍은 그림**이라, 카드 썸네일로 깔면 달력에 앱 스크린샷이
  /// 끼어 있는 것처럼 보인다. 기기에서 보고 알았다(2026-11-16).
  ///
  /// 둘뿐이라 같은 사진이 되풀이된다. 서버가 붙으면 없어질 목이라 그대로 둔다.
  static const _photoPool = [
    'assets/images/sign_in_hero.png',
    'assets/images/onboarding_record.jpg',
  ];

  static const _captions = [
    '여기서 한 번 쉬었다',
    '해 지는 게 아까워서 멈췄다',
    '바람이 딱 좋았다',
    '다리 건너기 직전',
    '끝나고 나니 다 좋았다',
  ];

  static const _reviews = [
    '오늘은 퇴근 후 성수동에서 달렸다. 처음에는 몸이 무거웠는데 어느새 발걸음이 가벼워졌다.',
    '선선한 바람 덕분에 생각보다 편안하게 달릴 수 있었다. 다음엔 조금 더 멀리 가 봐야지.',
    '중간에 힘든 구간이 있었지만 끝까지 페이스를 지켰다. 지난번보다 안정적이어서 뿌듯하다.',
    '비 온 뒤라 공기가 맑았다. 사진으로는 다 안 담기는 하늘이었다.',
    '오랜만에 먼 거리를 뛰었다. 다리는 무겁지만 기분은 가볍다.',
  ];

  static const _runners = [
    CardRunner(userId: 'u-1', nickname: '동완러너'),
    CardRunner(userId: 'u-2', nickname: '바람'),
    CardRunner(userId: 'u-3', nickname: '해질녘'),
  ];

  List<RecordCard> _all() => [
    for (var i = 0; i < _plan.length; i++) _cardAt(i, _plan[i]),
  ];

  RecordCard _cardAt(
    int index,
    ({
      int daysAgo,
      int hour,
      RecordCardActivity activity,
      int photos,
      RecordCardVisibility visibility,
      int meters,
      int seconds,
    })
    spec,
  ) {
    final day = DateTime(
      _today.year,
      _today.month,
      _today.day,
    ).subtract(Duration(days: spec.daysAgo));
    final startedAt = DateTime(day.year, day.month, day.day, spec.hour, 54);
    final duration = Duration(seconds: spec.seconds);

    return RecordCard(
      id: 'card-${1000 + index}',
      runningRecordId: 2000 + index,
      startedAt: startedAt,
      activity: spec.activity,
      visibility: spec.visibility,
      reviewText: _reviews[index % _reviews.length],
      photos: [
        for (var p = 0; p < spec.photos; p++)
          RecordCardPhoto(
            id: 'img-$index-$p',
            url: _photoPool[(index + p) % _photoPool.length],
            // ⚠️ 사람이 쓴 말처럼 둔다. `그날의 한 장` 같은 꼬리표를 넣으면
            // 캡션이 아니라 화면이 붙인 글자로 읽힌다 — 기기에서 그렇게 보였다.
            caption: _captions[(index + p) % _captions.length],
          ),
      ],
      route: normalizeRoute(_shape(index, startedAt)),
      distanceMeters: spec.meters,
      duration: duration,
      // 1km당 평균 페이스.
      averagePace: Duration(
        seconds: (spec.seconds * 1000 / spec.meters).round(),
      ),
      runners: _runners.take(index % 4).toList(),
    );
  }

  /// 카드마다 다른 모양을 낸다. 전부 같은 선이면 달력 칸이 구별되지 않는다.
  ///
  /// ## ⚠️ 일부러 흔들어 놓는다
  ///
  /// 매끈한 원이나 8자를 그리면 **러닝 경로가 아니라 도형으로 보인다.** 길을
  /// 따라 달린 선은 꺾이고 삐뚤다. `seed`로 정해진 난수를 섞어 모양을 흐트러뜨린다
  /// — 같은 카드는 늘 같은 모양이어야 해서 시각을 섞지 않는다.
  ///
  /// 네 장에 한 번은 **두 조각**으로 끊어 일시정지를 흉내낸다.
  static List<List<GeoPoint>> _shape(int seed, DateTime at) {
    final random = math.Random(seed);
    final lobesX = 1 + seed % 3;
    final lobesY = 1 + (seed + 1) % 2;
    final points = [
      for (var i = 0; i <= 48; i++)
        GeoPoint(
          latitude:
              37.54 +
              0.008 * math.sin(i / 48 * 2 * math.pi * lobesY) +
              0.0018 * (random.nextDouble() - 0.5) +
              seed * 0.0002,
          longitude:
              127.05 +
              0.010 * math.cos(i / 48 * 2 * math.pi * lobesX) +
              0.0018 * (random.nextDouble() - 0.5),
          recordedAt: at.add(Duration(seconds: i * 30)),
        ),
    ];

    if (seed % 4 == 0) return [points.sublist(0, 20), points.sublist(26)];
    return [points];
  }
}
