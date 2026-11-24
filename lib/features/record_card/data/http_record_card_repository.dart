import 'package:dio/dio.dart';
import 'package:runiverse/core/storage/token_store.dart';
import 'package:runiverse/features/auth/domain/token_refresher.dart';
import 'package:runiverse/features/profile/domain/picked_image.dart';
import 'package:runiverse/features/record_card/data/card_photo_uploader.dart';
import 'package:runiverse/features/record_card/data/record_card_draft_dto.dart';
import 'package:runiverse/features/record_card/domain/record_card_activity.dart';
import 'package:runiverse/features/record_card/domain/record_card_visibility.dart';
import 'package:runiverse/features/record_card/data/record_card_detail_dto.dart';
import 'package:runiverse/features/record_card/data/record_card_list_dto.dart';
import 'package:runiverse/features/record_card/data/recorded_run_dto.dart';
import 'package:runiverse/features/record_card/domain/composable_record.dart';
import 'package:runiverse/features/record_card/domain/edit_record_card.dart';
import 'package:runiverse/features/record_card/domain/new_record_card.dart';
import 'package:runiverse/features/record_card/domain/record_card.dart';
import 'package:runiverse/features/record_card/domain/record_card_list_item.dart';
import 'package:runiverse/features/record_card/domain/record_card_repository.dart';

/// 진짜 서버를 부르는 [RecordCardRepository].
///
/// 계약은 **「💾 [1.3.2] 기록 카드 프론트엔드 연동 가이드」**가 정본이다.
/// `docs/specs/2026-11-16-record-card-design.md` 3절·10절의 추측은 낡았다.
///
/// ## 사진은 우리 서버를 거치지 않는다
///
/// 작성·수정은 **초안 발급 → S3에 직접 PUT → 확정** 세 걸음이다. 가운데가
/// [CardPhotoUploader]이고, 거기에는 인증 헤더가 붙지 않는다.
///
/// ## 401은 한 번만 갱신한다
///
/// `HttpRunRecordRepository`와 같은 규칙이고, 갱신은 반드시 [TokenRefresher]를
/// 거친다. 저장소마다 재시도를 적으면 한쪽만 고쳐지는 일이 생긴다.
/// 확정을 **한 번 더** 해 볼 만한 실패. 밖으로 나가지 않는다.
class _RetryComplete {
  const _RetryComplete({required this.uploadAgain});

  /// 빠진 파일을 먼저 올려야 하나.
  final bool uploadAgain;
}

class HttpRecordCardRepository implements RecordCardRepository {
  HttpRecordCardRepository(
    this._dio,
    this._store,
    this._refresher, {
    CardPhotoUploader? uploader,
  }) : _uploader = uploader ?? CardPhotoUploader();

  /// S3에 직접 올리는 쪽. 인증이 붙지 않은 [Dio]를 따로 든다.
  final CardPhotoUploader _uploader;

  /// 카드 경로. 작성·확정·수정·삭제가 모두 여기서 갈린다.
  static const _cards = '/api/v1/record-cards';

  /// 서버가 받는 활동 유형. **대문자다**(가이드 3절).
  static String activityWire(RecordCardActivity activity) => switch (activity) {
    RecordCardActivity.daily => 'DAILY',
    RecordCardActivity.race => 'RACE',
    RecordCardActivity.travel => 'TRAVEL',
  };

  /// 서버가 받는 공개 범위. **대문자다.**
  static String visibilityWire(RecordCardVisibility visibility) =>
      switch (visibility) {
        RecordCardVisibility.friends => 'FRIENDS',
        RecordCardVisibility.public => 'PUBLIC',
        RecordCardVisibility.private => 'PRIVATE',
      };

  /// 새 사진 한 장의 메타데이터.
  ///
  /// ⚠️ **`fileName`은 필수**이고 경로 구분자와 제어 문자를 넣을 수 없다
  /// (가이드 3절). 100자를 넘으면 서버가 거절하므로 뒤를 자른다 — 앞을
  /// 자르면 확장자가 날아간다.
  ///
  /// ⚠️ **빈 캡션은 보내지 않는다.** 공백만 보내도 서버가 `null`로 저장하지만,
  /// 보내지 않는 쪽이 "안 썼다"는 뜻에 가깝다.
  static Map<String, Object?> imageWire(
    PickedImage file,
    PickedImage thumbnail,
    String? caption,
  ) => {
    'mimeType': file.mimeType,
    'fileSizeBytes': file.sizeBytes,
    'thumbnailFileSizeBytes': thumbnail.sizeBytes,
    'fileName': fileNameOf(file.path),
    if (caption != null && caption.trim().isNotEmpty) 'caption': caption,
  };

  /// 경로에서 보낼 파일 이름을 뽑는다. 최대 100자.
  static String fileNameOf(String path) {
    final last = path.split(RegExp(r'[/\\]')).last;
    // 제어 문자는 서버가 막는다. 남기면 400 하나를 더 받을 뿐이다.
    final clean = last.replaceAll(RegExp(r'[\x00-\x1f]'), '');
    final name = clean.isEmpty ? 'photo.jpg' : clean;
    return name.length <= 100 ? name : name.substring(name.length - 100);
  }

  final Dio _dio;
  final TokenStore _store;
  final TokenRefresher _refresher;

  // ── 읽기 ─────────────────────────────────────────────────────

  /// 러닝 기록 목록 + 카드 유무 (7-1).
  @override
  Future<List<ComposableRecord>> runsInRange({
    required DateTime from,
    required DateTime to,
  }) async {
    // ⚠️ **서버에 묻기 전에 걸러 낸다.** 400을 받고 나서야 아는 것보다 낫고,
    // 무엇보다 이건 사용자 입력이 아니라 **앱의 버그**다.
    if (from.isAfter(to)) {
      throw const RecordCardException(RecordCardFailure.invalidRequest);
    }
    // 가이드 1절: 시작일과 종료일을 **포함해** 최대 31일이다.
    if (to.difference(from).inDays >= RecordCardRepository.maxRangeDays) {
      throw const RecordCardException(RecordCardFailure.invalidRequest);
    }

    final body = await authorized(
      (token) => _dio.get<Map<String, dynamic>>(
        '/api/v1/users/me/running-records',
        queryParameters: {'from': day(from), 'to': day(to)},
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      ),
    );
    return RecordedRunDto.listFrom(body);
  }

  /// 그 사람의 카드 한 페이지 (10-3).
  @override
  Future<RecordCardListPage> cardsOf({
    required String userId,
    int? limit,
    String? cursor,
  }) async {
    // ⚠️ **번호를 경로에 그대로 붙이지 않는다.** 닉네임이 번호로 쓰이는 날
    // `/`가 든 값 하나가 경로를 갈라 **다른 엔드포인트를 부른다.**
    final path = '/api/v1/users/${Uri.encodeComponent(userId)}/record-cards';
    final body = await authorized(
      (token) => _dio.get<Map<String, dynamic>>(
        path,
        queryParameters: {
          // ⚠️ **`null`을 싣지 않는다.** `?limit=null`은 400이다.
          'limit': ?limit,
          'cursor': ?cursor,
        },
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      ),
    );
    return RecordCardListDto.from(body);
  }

  /// 카드 한 장 전부 (8-1).
  @override
  Future<RecordCard> detailOf(String cardId) async {
    // ⚠️ **번호를 경로에 그대로 붙이지 않는다.** UUID라 지금은 안전하지만,
    // 서버가 형식을 바꾸면 `/`가 들어온 번호 하나가 경로를 갈라 **다른
    // 엔드포인트를 부른다.**
    final path = '/api/v1/record-cards/${Uri.encodeComponent(cardId)}';
    final body = await authorized(
      (token) => _dio.get<Map<String, dynamic>>(
        path,
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      ),
    );
    return RecordCardDetailDto.from(body);
  }

  /// 못 만든 곡을 다시 만들어 달라고 한다 (9-6). 본문이 없고 `204`가 온다.
  @override
  Future<void> retryMusic(String cardId) => authorizedVoid(
    (token) => _dio.post<void>(
      '/api/v1/record-cards/${Uri.encodeComponent(cardId)}/retry',
      options: Options(headers: {'Authorization': 'Bearer $token'}),
    ),
  );

  // ── 쓰기 — 묶음 8까지 가짜가 받는다 ──────────────────────────

  @override
  Future<RecordCard> create(NewRecordCard card) async {
    final body = await authorized(
      (token) => _dio.post<Map<String, dynamic>>(
        _cards,
        data: {
          'runningRecordId': card.record.id,
          'activityType': activityWire(card.activity),
          'memo': card.reviewText,
          'visibility': visibilityWire(card.visibility),
          if (card.photos.isNotEmpty) ...{
            'images': [
              for (final photo in card.photos)
                imageWire(photo.file, photo.thumbnail, photo.caption),
            ],
            // 대표는 **늘 첫 장**이다 — 화면이 `makeCover`로 순서를 바꿔
            // 대표를 맨 앞에 둔다(`CardPhotoSlide`).
            'thumbnailIndex': 0,
          },
        },
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      ),
    );

    final draft = RecordCardDraftDto.from(body);
    await _uploadAll(card.photos, draft.uploads);
    final cardId = await _complete(
      draft,
      onMissing: () => _uploadAll(card.photos, draft.uploads),
    );
    // ⚠️ **상세를 다시 읽는다.** 확정은 번호만 준다(가이드 3절). 여기서
    // 카드를 지어 내면 서버가 채운 값(경로·파티원·음악)이 비어서 돌아간다.
    return detailOf(cardId);
  }

  /// 새 사진마다 크롭본과 썸네일을 올린다.
  ///
  /// ⚠️ **`uploads[i]`는 요청에 실은 새 사진 순서 그대로**다(가이드 3절).
  Future<void> _uploadAll(
    List<Object?> photos,
    List<CardUploadSlot> slots,
  ) async {
    for (var i = 0; i < slots.length; i++) {
      final slot = slots[i];
      // ⚠️ **조각내 올리는 길이 없다.** 조용히 한 번에 올리면 S3는 받아
      // 주고 확정이 거절하는데, 그때는 어느 사진인지 알 수 없다.
      if (!slot.isSingle) {
        throw const RecordCardException(RecordCardFailure.invalidRequest);
      }
      final pair = _pairAt(photos, i);
      await _uploader.put(
        url: slot.uploadUrl,
        path: pair.file.path,
        mimeType: pair.file.mimeType,
        sizeBytes: pair.file.sizeBytes,
      );
      final thumbnailUrl = slot.thumbnailUploadUrl;
      if (thumbnailUrl == null) continue;
      await _uploader.put(
        url: thumbnailUrl,
        path: pair.thumbnail.path,
        mimeType: pair.thumbnail.mimeType,
        sizeBytes: pair.thumbnail.sizeBytes,
      );
    }
  }

  /// 올릴 자리 [index]에 해당하는 새 사진. 작성은 전부 새 사진이고, 수정은
  /// 새 사진만 추려서 넘긴다.
  static ({PickedImage file, PickedImage thumbnail}) _pairAt(
    List<Object?> photos,
    int index,
  ) {
    final photo = photos[index];
    return switch (photo) {
      NewCardPhoto() => (file: photo.file, thumbnail: photo.thumbnail),
      EditCardPhoto() => (file: photo.file!, thumbnail: photo.thumbnail!),
      _ => throw StateError('올릴 사진이 아니다'),
    };
  }

  /// 초안을 확정한다 (9-2).
  ///
  /// ## ⚠️ 두 가지만 **한 번** 다시 해 본다
  ///
  /// `409 RECORD_CARD_DRAFT_IN_PROGRESS`는 잠시 뒤 같은 초안으로 다시 부르면
  /// 되고, `400 RECORD_CARD_IMAGE_NOT_UPLOADED`는 빠진 파일을 올린 뒤 같은
  /// 초안으로 다시 부르면 된다(가이드 7절). **두 번째도 실패하면 던진다** —
  /// 끝없이 다시 걸면 망이 죽었을 때 저장 표시가 영원히 돈다.
  Future<String> _complete(
    CardDraftIssued draft, {
    required Future<void> Function() onMissing,
  }) async {
    try {
      return await _completeOnce(draft.draftId, allowRetry: true);
    } on _RetryComplete catch (retry) {
      if (retry.uploadAgain) await onMissing();
      // ⚠️ **마지막 시도다.** 여기서도 같은 답이 오면 그대로 실패로 올린다 —
      // 끝없이 다시 걸면 망이 죽었을 때 저장 표시가 영원히 돈다.
      return _completeOnce(draft.draftId, allowRetry: false);
    }
  }

  Future<String> _completeOnce(
    String draftId, {
    required bool allowRetry,
  }) async {
    final stored = await _store.read();
    final token = stored.accessToken;
    if (token == null) {
      throw const RecordCardException(RecordCardFailure.sessionExpired);
    }
    try {
      final response = await _dio.post<Map<String, dynamic>>(
        '$_cards/drafts/$draftId/complete',
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );
      return response.data!['recordCardId'] as String;
    } on DioException catch (error) {
      // ⚠️ **`authorized`를 쓰지 않는다.** 그쪽은 `DioException`을 삼켜
      // `RecordCardException`으로 바꾸는데, 여기서는 **다시 해 볼 실패인지**
      // 보려고 원본이 필요하다. 401 갱신은 9-1에서 이미 지났다.
      throw allowRetry ? _retryOrFail(error) : exceptionOf(error);
    }
  }

  /// 다시 해 볼 만한 실패인가.
  static Object _retryOrFail(DioException error) {
    final body = error.response?.data;
    final code = body is Map ? body['code'] : null;
    return switch (code) {
      'RECORD_CARD_DRAFT_IN_PROGRESS' => const _RetryComplete(
        uploadAgain: false,
      ),
      'RECORD_CARD_IMAGE_NOT_UPLOADED' => const _RetryComplete(
        uploadAgain: true,
      ),
      _ => exceptionOf(error),
    };
  }

  @override
  Future<RecordCard> update(EditRecordCard card) async {
    // ⚠️ **러닝 기록을 보내지 않는다.** 수정에서 바꿀 수 없다(가이드 4절) —
    // 보내지 않으면 서버가 건드릴 일도 없다.
    //
    // ⚠️ **`images`는 남길 전체다.** 빈 배열은 "전부 지웠다"는 뜻이고,
    // 필드를 빼야 "안 바꿨다"가 된다. 화면은 늘 전체를 들고 오므로 늘 싣는다.
    final body = await authorized(
      (token) => _dio.patch<Map<String, dynamic>>(
        '$_cards/${Uri.encodeComponent(card.cardId)}',
        data: {
          'memo': card.reviewText,
          'activityType': activityWire(card.activity),
          'visibility': visibilityWire(card.visibility),
          'images': [
            for (final photo in card.photos)
              if (photo.savedId case final savedId?)
                // ⚠️ **캡션을 다시 보낸다.** 생략하면 `null`로 저장되고,
                // 설명이 지워진 사진의 곡도 다시 만들어진다.
                {'recordCardImageId': savedId, 'caption': photo.caption}
              else
                imageWire(photo.file!, photo.thumbnail!, photo.caption),
          ],
          // 대표는 늘 첫 장이다 — 화면이 순서로 정한다.
          if (card.photos.isNotEmpty) 'thumbnailIndex': 0,
        },
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      ),
    );

    // ⚠️ **`draft`가 없으면 저장이 끝난 것이다**(가이드 4절). 있으면 응답의
    // `recordCard`는 **수정 전 상태**라 그대로 쓰면 고친 값이 안 보인다.
    final draft = RecordCardDraftDto.draftOf(body);
    if (draft != null) {
      final added = [
        for (final photo in card.photos)
          if (photo.savedId == null) photo,
      ];
      await _uploadAll(added, draft.uploads);
      await _complete(draft, onMissing: () => _uploadAll(added, draft.uploads));
    }

    // 끝나면 다시 읽는다 — 파서를 한 벌만 둔다.
    return detailOf(card.cardId);
  }

  /// 카드를 영구 삭제한다 (9-4). 본문이 없고 `204`가 온다.
  ///
  /// ## ⚠️ 가짜로 넘기지 않는다
  ///
  /// 쓰기 중 **삭제만 진짜로 보낸다.** 가짜로 넘기면 서버가 준 번호를 못 찾아
  /// `404`가 나고, 화면은 그것을 **"이미 지워졌다"로 받아 성공으로 끝낸다**
  /// (`CardDeleteController`) — 지워지지 않았는데 지워졌다고 말하고, 다시
  /// 받아 보면 그대로 있다.
  ///
  /// 음악 생성 중에도 지울 수 있다. 되돌릴 수 없고, 확인은 화면이 먼저 받는다.
  @override
  Future<void> delete(String cardId) => authorizedVoid(
    (token) => _dio.delete<void>(
      '/api/v1/record-cards/${Uri.encodeComponent(cardId)}',
      options: Options(headers: {'Authorization': 'Bearer $token'}),
    ),
  );

  // ── 공통 ─────────────────────────────────────────────────────

  /// 토큰을 실어 보내고, **401이면 한 번만** 갱신해서 다시 부른다.
  ///
  /// 읽기 셋이 같은 규칙을 쓰도록 여기 모았다.
  Future<Map<String, dynamic>> authorized(
    Future<Response<Map<String, dynamic>>> Function(String token) send,
  ) async {
    final stored = await _store.read();
    final accessToken = stored.accessToken;
    if (accessToken == null) {
      throw const RecordCardException(RecordCardFailure.sessionExpired);
    }

    try {
      return _body(await send(accessToken));
    } on DioException catch (error) {
      if (error.response?.statusCode != 401) {
        throw exceptionOf(error);
      }
      try {
        return _body(await send(await _refreshed()));
      } on DioException catch (retried) {
        throw exceptionOf(retried);
      }
    }
  }

  /// 본문이 없는 요청(`204`)을 보낸다. 401 규칙은 [authorized]와 같다.
  ///
  /// ⚠️ **[authorized]를 쓰지 않는다.** 그쪽은 본문을 요구해서, 본문 없는
  /// `204`를 **서버 오류로** 읽는다.
  Future<void> authorizedVoid(
    Future<Response<void>> Function(String token) send,
  ) async {
    final stored = await _store.read();
    final accessToken = stored.accessToken;
    if (accessToken == null) {
      throw const RecordCardException(RecordCardFailure.sessionExpired);
    }

    try {
      await send(accessToken);
    } on DioException catch (error) {
      if (error.response?.statusCode != 401) {
        throw exceptionOf(error);
      }
      try {
        await send(await _refreshed());
      } on DioException catch (retried) {
        throw exceptionOf(retried);
      }
    }
  }

  /// 읽기 구현이 쓸 [Dio]. 묶음 7의 다음 작업들이 쓴다.
  Dio get dio => _dio;

  static Map<String, dynamic> _body(Response<Map<String, dynamic>> response) {
    final data = response.data;
    if (data == null) {
      throw const RecordCardException(RecordCardFailure.server);
    }
    return data;
  }

  Future<String> _refreshed() async {
    final accessToken = await _refresher.refresh();
    if (accessToken == null) {
      throw const RecordCardException(RecordCardFailure.sessionExpired);
    }
    return accessToken;
  }

  /// 서버가 받는 `YYYY-MM-DD`. **KST 달력 날짜**라 시각을 붙이지 않는다.
  static String day(DateTime date) {
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return '${date.year}-$month-$day';
  }

  /// `DioException`을 카드 실패로 옮긴다.
  ///
  /// ## ⚠️ 읽기에는 `code`로 갈릴 자리가 없다
  ///
  /// 가이드는 "앱의 분기는 `code`를 기준으로" 하라고 적었는데, 그 `code`가
  /// 갈라 주는 것은 **전부 쓰기 쪽**이다(7절 표의 `RECORD_CARD_ALREADY_EXISTS`
  /// ·`RECORD_CARD_CHANGED`·`RECORD_CARD_DRAFT_IN_PROGRESS`
  /// ·`RECORD_CARD_IMAGE_NOT_UPLOADED`·`INVALID_RECORD_CARD_IMAGE`). 복구
  /// 위치가 코드마다 달라 한 값으로 뭉개면 안 되지만, **읽기에서는 그 코드가
  /// 오지 않는다.** 그래서 지금은 상태 코드만 본다 — 묶음 8이 `code` 분기를
  /// 여기에 넣는다. 쓰지 않는 값을 미리 읽어 두면 "읽는데 안 쓰는 코드"가
  /// 남는다.
  ///
  /// ## ⚠️ `403 APP_UPDATE_REQUIRED`는 여기 오지 않는다
  ///
  /// `dio_client.dart`의 `updateRequiredInterceptor`가 저장소보다 **앞에서**
  /// 잡아 업데이트 관문으로 보낸다. 여기서 또 가르면 같은 일을 두 곳에서 하고,
  /// 한쪽만 고쳐지는 날이 온다.
  static RecordCardException exceptionOf(DioException error) =>
      RecordCardException(failureOf(error));

  static RecordCardFailure failureOf(DioException error) {
    // ⚠️ **응답이 없으면 망 문제다.** 시간 초과·연결 실패·취소가 여기다.
    if (error.type != DioExceptionType.badResponse) {
      return RecordCardFailure.network;
    }

    final status = error.response?.statusCode ?? 0;

    // ⚠️ **`code`를 먼저 본다**(공통 요청 규칙). 같은 `409`가 "이미 있다"와
    // "먼저 고쳐졌다"로 갈리고, 앱이 할 일이 다르다. **모르는 `code`는
    // 지어내지 않고** 아래 상태 코드 규칙으로 떨어진다.
    final body = error.response?.data;
    final code = body is Map ? body['code'] : null;
    final byCode = switch (code) {
      'RECORD_CARD_ALREADY_EXISTS' => RecordCardFailure.alreadyExists,
      'RECORD_CARD_CHANGED' => RecordCardFailure.changed,
      'INVALID_RECORD_CARD_IMAGE' => RecordCardFailure.changed,
      _ => null,
    };
    if (byCode != null) return byCode;

    return switch (status) {
      400 => RecordCardFailure.invalidRequest,
      401 => RecordCardFailure.sessionExpired,
      // ⚠️ **이 둘은 재시도 대상이 아니다.** `server`로 뭉치면 화면이
      // 기다렸다 다시 해 보라고 권하는데, 기다린다고 달라지지 않는다.
      //
      // 상세의 `404`는 삭제·권한·작성자 탈퇴를 한 응답으로 묶는다 —
      // 화면은 "찾을 수 없거나 볼 수 없습니다"로 안내한다(가이드 2절).
      403 => RecordCardFailure.forbidden,
      404 => RecordCardFailure.notFound,
      _ => RecordCardFailure.server,
    };
  }
}
