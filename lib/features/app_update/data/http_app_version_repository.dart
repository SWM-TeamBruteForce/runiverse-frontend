import 'dart:io' show Platform;

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:runiverse/features/app_update/domain/app_update_status.dart';
import 'package:runiverse/features/app_update/domain/app_version_repository.dart';

/// `GET /api/v1/app/version` — 이 플랫폼의 최소·최신 버전.
///
/// ## ⚠️ `Authorization`을 싣지 않는다
///
/// 공개 API지만 **헤더가 있으면 서버가 토큰을 검증한다**(공통 규칙). 만료된
/// 토큰을 실으면 버전 확인이 401로 막히는데, 하필 **앱을 오래 안 켠 사람**이
/// 그 상태다 — 업데이트가 가장 필요한 사람이 판정을 못 받는다.
///
/// 지금 `createDio()`에는 토큰을 끼우는 인터셉터가 없어 저절로 지켜지지만,
/// 나중에 생기면 이 호출만 빠져나가야 한다. 그래서 테스트가 **헤더가 없음**을
/// 직접 확인한다.
class HttpAppVersionRepository implements AppVersionRepository {
  const HttpAppVersionRepository(this._dio);

  final Dio _dio;

  static const _path = '/api/v1/app/version';

  /// 스플래시가 이것을 기다린다. dio 기본값(10초)이면 앱이 멈춘 것처럼 보인다.
  static const _timeout = Duration(seconds: 5);

  @override
  Future<AppVersionPolicy> fetch() async {
    try {
      final response = await _dio.get<Map<String, dynamic>>(
        _path,
        queryParameters: {'platform': _platform},
        options: Options(
          sendTimeout: _timeout,
          receiveTimeout: _timeout,
          // ⚠️ **빈 맵으로는 안 지워진다.** dio의 `Options.compose`가
          // `baseOptions.headers`에 이 맵을 `addAll`만 한다 — 덮어쓸 뿐
          // 지우지 않는다. `null`로 덮어야 빠진다.
          headers: const {'Authorization': null},
        ),
      );

      final policy = AppVersionPolicy.of(response.data);
      // 200을 받아도 값이 기대와 다를 수 있다. 못 읽으면 판정하지 않는다.
      if (policy == null) throw const AppVersionUnavailable();
      return policy;
    } on DioException catch (error) {
      debugPrint('[version] 버전 기준을 못 받았다 · ${error.type.name}');
      throw const AppVersionUnavailable();
    }
  }

  /// 서버가 받는 값은 `IOS` / `ANDROID` 둘뿐이다.
  ///
  /// ⚠️ **다른 플랫폼은 400이다.** 데스크톱·웹 빌드는 범위에 없지만, 테스트는
  /// 호스트(Windows)에서 돌아 `Platform.isIOS`가 늘 `false`다 — 그래서 기본을
  /// 안드로이드로 둔다. 판정이 틀려도 그쪽 최소 버전을 보게 될 뿐이다.
  static String get _platform => Platform.isIOS ? 'IOS' : 'ANDROID';
}
