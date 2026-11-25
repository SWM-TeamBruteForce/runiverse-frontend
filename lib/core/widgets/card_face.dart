import 'dart:io';

import 'package:flutter/material.dart';
import 'package:runiverse/core/theme/v2/app_colors.dart';
import 'package:runiverse/core/theme/v2/app_spacing.dart';
import 'package:runiverse/core/widgets/profile_photo_image.dart';
import 'package:runiverse/core/widgets/route_art_view.dart';
import 'package:runiverse/features/record_card/domain/route_art.dart';

/// 칸을 채우는 그림 — 썸네일이 있으면 사진, 없으면 선.
///
/// ## ⚠️ `core/`에 있는 이유
///
/// **달력 칸과 프로필 그리드가 같은 그림을 그려야 한다**(설계 6-7 — "사진 없는
/// 카드는 캘린더와 같은 경로 선 아트"). 그리드는 `profile/`에 있고(설계 7절)
/// CLAUDE.md가 **다른 feature의 위젯 import를 막는다** — 공유가 필요하면
/// `core/widgets/`로 올리라고 적혀 있다. `run_map_view.dart`가 `session/domain`
/// 을 import하는 것과 같은 모양이다.
/// ## ⚠️ 못 받았으면 **한 번만** 알린다
///
/// 조회용 주소는 **1시간 뒤 만료된다**(연동 가이드 7절). `403`이면 그 주소를
/// 준 API를 다시 불러야 하는데, 알림을 막지 않으면 **다시 받은 주소도
/// 만료됐을 때 끝나지 않는 고리**가 된다 — 새 주소로 또 `403`, 또 재조회.
///
/// 깃발을 **위젯 상태에 둔다.** provider에 두면 다음 카드가 그 깃발을
/// 물려받아, 한 장이 만료되면 다른 장들이 영영 재조회를 못 한다.
class CardFace extends StatefulWidget {
  const CardFace({
    required this.thumbnailUrl,
    required this.route,
    this.onExpired,
    super.key,
  });

  /// 깔 그림. **없으면 [route]로 선을 긋는다.**
  final String? thumbnailUrl;

  /// 사진을 못 받았다고 알린다. **한 번만 불린다.**
  ///
  /// 부르는 쪽은 그 주소를 준 provider를 버린다 — 달력은 달력을, 프로필
  /// 그리드는 그리드를, 상세는 상세를.
  final VoidCallback? onExpired;

  /// 썸네일이 없을 때 그릴 선. 비어 있으면 점 하나를 남긴다.
  ///
  /// ⚠️ **엔티티를 받지 않는다.** 달력은 요약(`RecordCardSummary`)을 들고
  /// 프로필 그리드는 목록 항목을 드는데, 그 둘의 필드가 다르다 — 프로필
  /// 항목에는 경로가 아예 없다(연동 가이드 5절). 값 두 개만 받으면 둘 다
  /// 같은 그림을 그릴 수 있다.
  final RouteArt route;

  @override
  State<CardFace> createState() => _CardFaceState();
}

class _CardFaceState extends State<CardFace> {
  /// 이미 알렸나. **두 번 알리지 않는다.**
  var _reported = false;

  void _expired() {
    if (_reported) return;
    _reported = true;
    // ⚠️ **그리는 중에 provider를 버리지 않는다.** `errorBuilder`는 빌드
    // 안에서 불린다 — 거기서 버리면 빌드 중에 다시 빌드가 걸린다.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.onExpired?.call();
    });
  }

  @override
  Widget build(BuildContext context) {
    final url = widget.thumbnailUrl;
    if (url == null) {
      // ⚠️ **경로도 사진도 없는 카드가 있다.** 트레드밀이나 GPS를 못 받은
      // 러닝이다. 그대로 두면 `RouteArtView`가 아무것도 안 그려, 칸이 **안 뛴
      // 날과 픽셀 단위로 같아진다** — 쓴 카드를 달력에서 못 찾는다.
      if (widget.route.isEmpty) return const CardMarkDot();

      return RouteArtView(
        art: widget.route,
        color: context.appColorsV2.primary,
        strokeWidth: 1.5,
        padding: AppSpacing.space1,
      );
    }

    return Image(
      image: cardThumbnail(context, url),
      fit: BoxFit.cover,
      // 못 받아도 칸이 비지 않게 선으로 떨어진다.
      errorBuilder: (context, _, _) {
        _expired();
        return RouteArtView(
        art: widget.route,
        color: context.appColorsV2.primary,
          strokeWidth: 1.5,
          padding: AppSpacing.space1,
        );
      },
    );
  }
}

/// 보여 줄 것이 아무것도 없는 카드의 자국.
///
/// 사진도 경로도 없을 때 칸 가운데에 작은 점 하나를 남긴다. **"여기 카드가
/// 있다"만 말하면 된다** — 빈 날과 구별되는 것이 전부다.
class CardMarkDot extends StatelessWidget {
  const CardMarkDot({super.key});

  static const _size = 8.0;

  @override
  Widget build(BuildContext context) => Center(
    child: Container(
      width: _size,
      height: _size,
      decoration: BoxDecoration(
        color: context.appColorsV2.primary,
        shape: BoxShape.circle,
      ),
    ),
  );
}

/// 카드 사진을 띄울 [ImageProvider].
///
/// ## ⚠️ `assets/`로 시작하면 번들에서 읽는다
///
/// 서버가 없어 `FakeRecordCardRepository`가 **번들 에셋 경로**를 준다
/// (`docs/plans/2026-11-16-record-card-calendar.md` Task 3 Ruling).
/// **HTTP 구현체가 붙으면 이 분기를 지운다** — 안 지우면 서버가 `assets/`로
/// 시작하는 키를 주는 날 조용히 깨진다.
///
/// ## ⚠️ `http`로 시작하지 않으면 기기 안 파일이다
///
/// 올릴 엔드포인트가 아직 없어(3차 명세에 사진 업로드가 없다) 방금 만든 카드의
/// 사진은 **잘라 둔 임시 파일**이다. **이 분기는 HTTP 구현체가 붙어도 남는다**
/// — 올리기 전의 카드를 그려야 한다.
///
/// 서명이 붙은 주소는 [ProfilePhotoImage]에 맡긴다. 조회할 때마다 서명이
/// 달라져도 **경로가 같으면 다시 받지 않는다.**
///
/// 순서가 중요하다. `assets/` → 번들, `http` → 망, 나머지 → 파일.
ImageProvider<Object> cardThumbnail(BuildContext context, String url) {
  if (url.startsWith('assets/')) return AssetImage(url);
  if (url.startsWith('http')) return ProfilePhotoImage(url);
  return FileImage(File(url));
}
