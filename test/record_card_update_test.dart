import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runiverse/core/storage/token_store.dart';
import 'package:runiverse/features/auth/data/fake_auth_repository.dart';
import 'package:runiverse/features/auth/domain/token_refresher.dart';
import 'package:runiverse/features/profile/domain/picked_image.dart';
import 'package:runiverse/features/record_card/data/card_photo_uploader.dart';
import 'package:runiverse/features/record_card/data/http_record_card_repository.dart';
import 'package:runiverse/features/record_card/domain/edit_record_card.dart';
import 'package:runiverse/features/record_card/domain/record_card_activity.dart';
import 'package:runiverse/features/record_card/domain/record_card_repository.dart';
import 'package:runiverse/features/record_card/domain/record_card_visibility.dart';

/// 카드 수정 — 9-3 PATCH, 새 사진이 있으면 S3 → 9-2 (연동 가이드 4절).
void main() {
  const cardId = '019aa100-0000-7000-8000-0000000000aa';
  const draftId = '019aa100-0000-7000-8000-000000000099';

  late Directory dir;
  late PickedImage file;
  late PickedImage thumb;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('card_update_test');
    final one = File('${dir.path}/photo.jpg')
      ..writeAsBytesSync(List.filled(64, 7));
    final two = File('${dir.path}/thumb.jpg')
      ..writeAsBytesSync(List.filled(16, 7));
    file = PickedImage.validated(path: one.path, sizeBytes: 64);
    thumb = PickedImage.validated(path: two.path, sizeBytes: 16);
  });

  tearDown(() => dir.deleteSync(recursive: true));

  EditRecordCard edit({int kept = 0, int added = 0, String? keptCaption}) =>
      EditRecordCard(
        cardId: cardId,
        activity: RecordCardActivity.race,
        visibility: RecordCardVisibility.private,
        reviewText: '고친 글',
        photos: [
          for (var i = 0; i < kept; i++)
            EditCardPhoto.saved(savedId: 'image-$i', caption: keptCaption),
          for (var i = 0; i < added; i++)
            EditCardPhoto.added(file: file, thumbnail: thumb),
        ],
      );

  ({HttpRecordCardRepository repository, _Dio dio, _Uploader uploader})
  world() {
    final store = InMemoryTokenStore();
    store.saveSession(
      userId: 'me',
      accessToken: 'token',
      refreshToken: 'refresh',
      isOnboarded: true,
    );
    final dio = _Dio(draftId: draftId, cardId: cardId);
    final uploader = _Uploader();
    return (
      repository: HttpRecordCardRepository(
        dio,
        store,
        TokenRefresher(FakeAuthRepository(), store),
        uploader: uploader,
      ),
      dio: dio,
      uploader: uploader,
    );
  }

  test('새 사진이 없으면 PATCH 한 번으로 끝난다', () async {
    final w = world();

    await w.repository.update(edit(kept: 1));

    expect(w.dio.completeCalls, 0);
    expect(w.uploader.calls, isEmpty);
  });

  test('러닝 기록은 보내지 않는다 — 수정에서 바꿀 수 없다', () async {
    final w = world();

    await w.repository.update(edit(kept: 1));

    expect(w.dio.lastPatch, isNot(contains('runningRecordId')));
    expect(w.dio.lastPatch!['memo'], '고친 글');
    expect(w.dio.lastPatch!['activityType'], 'RACE');
    expect(w.dio.lastPatch!['visibility'], 'PRIVATE');
  });

  test('⚠️ 남긴 캡션을 그대로 다시 보낸다', () async {
    // 생략하면 서버가 `null`로 저장하고, 설명이 지워진 사진의 곡도 다시
    // 만든다(가이드 4절).
    final w = world();

    await w.repository.update(edit(kept: 1, keptCaption: '노을'));

    final image =
        (w.dio.lastPatch!['images'] as List).single as Map<String, dynamic>;
    expect(image['recordCardImageId'], 'image-0');
    expect(image['caption'], '노을');
    expect(image, isNot(contains('mimeType')));
  });

  test('⚠️ 사진을 전부 지우면 빈 배열을 보낸다', () async {
    // 빈 목록은 "안 바꿨다"가 아니라 "전부 지웠다"는 뜻이다.
    final w = world();

    await w.repository.update(edit());

    expect(w.dio.lastPatch!['images'], isEmpty);
  });

  test('⚠️ draft가 오면 새 사진만 올리고 확정한다', () async {
    final w = world()..dio.patchGivesDraft = true;

    await w.repository.update(edit(kept: 1, added: 1));

    // 남긴 사진은 번호만 돌려보낸다 — 다시 올리지 않는다.
    expect(w.uploader.calls, hasLength(2));
    expect(w.dio.completeCalls, 1);
  });

  test('⚠️ 400 INVALID_RECORD_CARD_IMAGE는 다시 읽으라는 실패다', () async {
    final w = world()..dio.failPatch(400, 'INVALID_RECORD_CARD_IMAGE');

    await expectLater(
      w.repository.update(edit(kept: 1)),
      throwsA(
        isA<RecordCardException>().having(
          (e) => e.failure,
          'failure',
          RecordCardFailure.changed,
        ),
      ),
    );
  });

  test('끝나면 상세를 다시 읽는다', () async {
    final w = world();

    final card = await w.repository.update(edit(kept: 1));

    expect(card.id, cardId);
    expect(w.dio.paths.last, '/api/v1/record-cards/$cardId');
  });
}

class _Uploader extends CardPhotoUploader {
  final calls = <String>[];

  @override
  Future<void> put({
    required String url,
    required String path,
    required String mimeType,
    required int sizeBytes,
  }) async {
    calls.add(url);
  }
}

class _Dio extends DioMixin implements Dio {
  _Dio({required this.draftId, required this.cardId});

  final String draftId;
  final String cardId;

  final paths = <String>[];
  Map<String, dynamic>? lastPatch;
  var completeCalls = 0;
  var patchGivesDraft = false;

  int? _patchStatus;
  String? _patchCode;

  void failPatch(int status, String code) {
    _patchStatus = status;
    _patchCode = code;
  }

  @override
  Future<Response<T>> patch<T>(
    String path, {
    Object? data,
    Map<String, dynamic>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
    ProgressCallback? onSendProgress,
    ProgressCallback? onReceiveProgress,
  }) async {
    paths.add(path);
    lastPatch = data! as Map<String, dynamic>;

    final status = _patchStatus;
    if (status != null) {
      throw DioException(
        requestOptions: RequestOptions(path: path),
        type: DioExceptionType.badResponse,
        response: Response<Object?>(
          requestOptions: RequestOptions(path: path),
          statusCode: status,
          data: {'code': _patchCode},
        ),
      );
    }

    final added = (lastPatch!['images'] as List)
        .whereType<Map<String, dynamic>>()
        .where((image) => image.containsKey('mimeType'))
        .length;
    return _ok<T>(path, {
      'recordCard': <String, Object?>{},
      if (patchGivesDraft)
        'draft': {
          'recordCardDraftId': draftId,
          'expiresAt': '2026-11-24T05:00:00',
          'uploads': [
            for (var i = 0; i < added; i++)
              {
                'recordCardImageId': 'new-$i',
                'uploadType': 'SINGLE',
                'uploadUrl': 'https://s3.invalid/photo-$i',
                'thumbnailUploadUrl': 'https://s3.invalid/thumb-$i',
              },
          ],
        },
    });
  }

  @override
  Future<Response<T>> post<T>(
    String path, {
    Object? data,
    Map<String, dynamic>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
    ProgressCallback? onSendProgress,
    ProgressCallback? onReceiveProgress,
  }) async {
    paths.add(path);
    completeCalls++;
    return _ok<T>(path, {'recordCardId': cardId});
  }

  @override
  Future<Response<T>> get<T>(
    String path, {
    Object? data,
    Map<String, dynamic>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
    ProgressCallback? onReceiveProgress,
  }) async {
    paths.add(path);
    return _ok<T>(path, {
      'recordCardId': cardId,
      'isMine': true,
      'visibility': 'PRIVATE',
      'activityType': 'RACE',
      'memo': '고친 글',
      'record': {
        'runningRecordId': 123,
        'startedAt': '2026-11-24T04:28:00',
        'totalDistanceMeters': 5000,
        'totalDurationSeconds': 1800,
        'averagePaceSecondsPerKm': 360,
        'routeArt': <Object?>[],
      },
      'images': <Object?>[],
      'companions': <Object?>[],
    });
  }

  Response<T> _ok<T>(String path, Map<String, dynamic> body) => Response<T>(
    requestOptions: RequestOptions(path: path),
    statusCode: 200,
    data: body as T,
  );
}
