import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:runiverse/features/record_card/domain/record_card_repository.dart';

/// 카드 사진을 **S3에 직접** 올린다 (연동 가이드 3절).
///
/// 초안 발급(9-1)이 준 주소에 `PUT` 한 번이다. 크롭본과 썸네일이 각각 한
/// 번씩이고, 조립은 서버가 한다 — 앱이 ETag를 모을 일이 없다.
///
/// ## ⚠️ 우리 서버의 [Dio]를 쓰지 않는다
///
/// `dio_client`의 것에는 `baseUrl`이 박혀 있고 인증 헤더가 실린다. **S3가 그
/// 헤더까지 서명 검증에 넣어 `403`을 준다.** 아무것도 붙지 않은 [Dio]를
/// 따로 든다 — `HttpProfileImageRepository`가 같은 함정을 적어 두었다.
class CardPhotoUploader {
  CardPhotoUploader({Dio? uploadDio}) : _dio = uploadDio ?? Dio(uploadOptions);

  /// S3 전용 [Dio]의 설정.
  ///
  /// ## ⚠️ 시간 제한을 여기서 꼭 준다
  ///
  /// `dio`의 기본값은 **무제한 대기**다. 인터셉터도 `baseUrl`도 일부러
  /// 비우는데, 그러면서 `dio_client`가 쥐고 있던 제한까지 함께 빠진다. 망이
  /// 죽으면 `PUT`이 끝나지 않고 **저장 회전 표시도 멈추지 않는다.**
  ///
  /// ## ⚠️ 보내는 시간만 길다
  ///
  /// 사진 본문이 올라가는 구간이라 나머지와 같은 값으로 묶으면 **느린 망에서
  /// 멀쩡한 업로드가 잘린다.**
  static BaseOptions get uploadOptions => BaseOptions(
    connectTimeout: const Duration(seconds: 10),
    sendTimeout: const Duration(seconds: 60),
    receiveTimeout: const Duration(seconds: 10),
  );

  final Dio _dio;

  /// ⚠️ **[uploadOptions]가 실제로 걸렸는지 보려고 연다.** 설정 객체만
  /// 검사하면 "값은 맞는데 아무 데도 안 쓰는" 상태를 못 잡는다.
  @visibleForTesting
  Dio get uploadDio => _dio;

  /// [path]의 파일을 [url]에 통째로 올린다.
  ///
  /// [mimeType]과 [sizeBytes]는 **초안 발급 때 보낸 값 그대로**여야 한다 —
  /// 서명에 들어가 있어 하나라도 어긋나면 `403`이다.
  Future<void> put({
    required String url,
    required String path,
    required String mimeType,
    required int sizeBytes,
  }) async {
    // ⚠️ **`Uint8List`여야 한다.** dio는 이것만 그대로 흘려보내고, 그냥
    // `List<int>`면 `toString()`을 거쳐 `[137, 80, ...]`이라는 **글자**가
    // 올라간다. 길이도 내용도 서명과 어긋나 403이 되는데 원인이 안 보인다.
    final Uint8List bytes;
    try {
      bytes = await File(path).readAsBytes();
    } on FileSystemException {
      // 자른 임시 파일이 사라졌다. 올릴 것이 없다.
      throw const RecordCardException(RecordCardFailure.invalidRequest);
    }

    // 읽어 보니 발급 때와 크기가 다르다. 그대로 올리면 403인데, 그 응답에는
    // 이유가 전혀 드러나지 않는다 — 여기서 멈춰야 원인이 가까운 곳에 남는다.
    if (bytes.length != sizeBytes) {
      throw const RecordCardException(RecordCardFailure.invalidRequest);
    }

    try {
      await _dio.put<Object?>(
        url,
        data: bytes,
        options: Options(
          contentType: mimeType,
          // S3는 성공에 빈 몸통을 준다. json으로 파싱하려 들면 그때 깨진다.
          responseType: ResponseType.plain,
        ),
      );
    } on DioException catch (_) {
      // 여기 오는 403은 서명 불일치다. 사용자에게 가를 것이 없고, 우리 서버의
      // 실패와 섞이지만 않으면 된다.
      throw const RecordCardException(RecordCardFailure.network);
    }
  }
}
