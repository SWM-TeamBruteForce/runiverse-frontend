import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

/// 지름 [diameter]에 그릴 프로필 사진. **그 크기로 줄여서 디코딩한다.**
///
/// ## 왜 필요한가
///
/// 원본은 8160×6120까지 온다. 88px 원에 띄워도 [Image.network]는 **통째로
/// 푼다** — 약 190MB다. 아바타가 여러 개 뜨는 화면(매칭 대기실·파티원 비교)에서는
/// 그만큼이 겹친다. `cacheWidth`를 주면 디코더가 처음부터 작게 읽는다.
///
/// ⚠️ **기기 픽셀 비를 곱한다.** 논리 픽셀을 그대로 주면 고해상도 기기에서
/// 흐릿해진다 — 88px 원이 실제로는 264px이다.
ImageProvider<Object> profilePhoto(
  BuildContext context,
  String url,
  double diameter,
) => ResizeImage.resizeIfNeeded(
  (diameter * MediaQuery.devicePixelRatioOf(context)).round(),
  null,
  ProfilePhotoImage(url),
);

/// 프로필 사진을 **서명을 뺀 경로로** 캐시하는 [ImageProvider].
///
/// ## 왜 [NetworkImage]를 그냥 쓰면 안 되나
///
/// 서버는 조회할 때마다 **새 서명 URL**을 준다. 경로는 같고 `?` 뒤만 달라지는데,
/// [NetworkImage]의 캐시 키는 URL 전체라 **같은 사진을 매번 다시 내려받는다.**
///
/// ```
/// https://.../profile/abc.jpg?X-Amz-Date=20261014T...&X-Amz-Signature=9f1c...
/// └──────────── 캐시 키로 쓰는 자리 ────────────┘└── 매번 바뀐다 ──┘
/// ```
///
/// ## `==`는 URL로, 캐시 키는 경로로 가른다
///
/// 둘을 같은 기준으로 두면 안 된다.
///
/// | 자리 | 기준 | 그래서 |
/// |---|---|---|
/// | [operator ==] | URL 전체 | 주소가 바뀌면 위젯이 **다시 풀어 본다** |
/// | [obtainKey] | `?` 앞 경로 | 다시 풀어 봐도 **캐시에서 꺼낸다** |
///
/// `==`까지 경로로 두면, 처음 받기에 실패한 사진이 새 주소를 받아도 영영
/// 다시 시도하지 않는다. 반대로 캐시 키를 URL로 두면 이 클래스가 할 일이 없다.
///
/// ## 크기는 여기서 줄이지 않는다
///
/// 부르는 쪽이 [ResizeImage]로 감싼다. 아바타마다 지름이 다르고(88 · 28 …)
/// 기기 픽셀 비도 달라서, 얼마로 줄일지는 그리는 자리만 안다.
@immutable
class ProfilePhotoImage extends ImageProvider<String> {
  const ProfilePhotoImage(this.url);

  /// 서명이 붙은 열람 주소. **만료된다.**
  final String url;

  /// 서명·만료 파라미터를 뗀 자리. 같은 사진이면 이 값이 같다.
  static String cacheKeyOf(String url) {
    final query = url.indexOf('?');
    return query < 0 ? url : url.substring(0, query);
  }

  @override
  Future<String> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture<String>(cacheKeyOf(url));

  /// 받아오는 일은 [NetworkImage]에 맡긴다.
  ///
  /// ⚠️ **키가 아니라 [url]로 받는다.** 키에는 서명이 없어서 그대로 요청하면
  /// S3가 거절한다. 캐시를 가르는 값과 요청할 주소가 다른 것이 이 클래스의 전부다.
  @override
  ImageStreamCompleter loadImage(String key, ImageDecoderCallback decode) {
    final source = NetworkImage(url);
    return source.loadImage(source, decode);
  }

  @override
  bool operator ==(Object other) =>
      other is ProfilePhotoImage && other.url == url;

  @override
  int get hashCode => url.hashCode;

  @override
  String toString() => 'ProfilePhotoImage(${cacheKeyOf(url)})';
}
