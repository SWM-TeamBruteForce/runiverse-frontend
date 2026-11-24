import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:runiverse/core/strings/app_strings.dart';
import 'package:runiverse/core/theme/v2/app_colors.dart';
import 'package:runiverse/core/theme/v2/app_radius.dart';
import 'package:runiverse/core/theme/v2/app_spacing.dart';
import 'package:runiverse/core/theme/v2/app_typography.dart';
import 'package:runiverse/features/record_card/domain/record_card.dart';
import 'package:runiverse/features/record_card/presentation/card_detail_provider.dart';
import 'package:runiverse/core/widgets/card_face.dart';
import 'package:runiverse/core/widgets/route_art_view.dart';

/// 카드의 포토북 — **경로 한 장 + 사진 N장**이 9:16으로 선다.
///
/// ## ⚠️ 장은 손으로만 넘어간다
///
/// 2026-11-25에 사용자가 **곡이 끝나면 그 곡을 반복**하기로 정했다
/// (`docs/specs/2026-11-25-record-card-audio-design.md` 2절). 곡이 끝나지
/// 않으니 넘길 신호가 없다 — **저절로 넘어가던 타이머를 걷었다.**
///
/// 그 전에는 "그 장의 길이만큼 지나면" 넘겼고, 길이는 `CardMusicTiming`이
/// 들고 있었다. 둘 다 없다.
///
/// ## ⚠️ 소리를 모른다
///
/// 이 위젯은 **플레이어를 쥐지 않는다.** 소리는 상세 화면이 혼자 몬다(설계
/// 6-1) — 두 군데서 몰면 줄은 `재생`인데 소리는 나는 어긋남이 생긴다.
/// 여기는 탭을 [onTap]으로 올려 보내기만 한다.
class CardMediaPager extends StatefulWidget {
  const CardMediaPager({
    required this.card,
    required this.onTap,
    required this.onPageChanged,
    super.key,
  });

  /// 양옆 이웃이 살짝 보이는 정도. 시안이 가운데 장을 크게 두고 좌우를
  /// 조금씩 드러낸다.
  static const _viewport = 0.82;

  /// 사진이 화면 높이의 몇 할까지 먹을 수 있나.
  ///
  /// ⚠️ **디자인 확인이 필요한 값이다.** 사진·캡션·회고가 한 화면에 들어오는
  /// 것이 기준이다.
  static const _maxHeightShare = 0.52;

  final RecordCard card;

  /// 사진을 탭했다. **스스로 아무것도 하지 않는다** — 받은 쪽이 정한다.
  final VoidCallback onTap;

  /// 몇 번째 장으로 갔나. 상세 화면이 **그 장의 곡**을 물려야 한다.
  final ValueChanged<int> onPageChanged;

  @override
  State<CardMediaPager> createState() => _CardMediaPagerState();
}

class _CardMediaPagerState extends State<CardMediaPager> {
  late final PageController _controller = PageController(
    viewportFraction: CardMediaPager._viewport,
  );

  var _page = 0;

  /// 경로 한 장 + 사진들.
  int get _count => widget.card.photos.length + 1;

  /// 페이저 높이. 9:16으로 낸 값과 화면의 [CardMediaPager._maxHeightShare]
  /// 중 **작은 쪽**이다.
  double _pagerHeight(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final ideal = size.width * CardMediaPager._viewport * 16 / 9;
    return math.min(ideal, size.height * CardMediaPager._maxHeightShare);
  }

  /// 사진 아래 글자 자리에 설 말.
  ///
  /// ⚠️ **자리는 하나다.** 경로 장에서는 회고, 사진 장에서는 **회고 대신**
  /// 그 사진의 캡션이 선다. 둘을 같이 두면 사진을 넘기는 내내 회고가 아래에
  /// 따라다닌다.
  String? get _below => _page == 0
      ? widget.card.reviewText
      : widget.card.photos[_page - 1].caption;

  /// 보고 있는 장. **카드가 바뀌면 범위 안으로 당긴다.**
  ///
  /// ⚠️ **수정으로 사진이 줄면 보던 자리가 사라진다.** 그대로 두면 상세가
  /// 통째로 빨간 화면이 된다 — 2026-11-24 에뮬레이터에서 사진 두 장 중
  /// 하나를 지우고 저장했을 때 실제로 그렇게 터졌다(RangeError).
  void _clampPage() {
    final last = _count - 1;
    if (_page <= last) return;
    _page = last;
    // 그리는 중이라 여기서 state 를 건드리지 않는다. 페이저도 함께 당긴다.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _controller.hasClients) _controller.jumpToPage(last);
    });
  }

  @override
  void didUpdateWidget(CardMediaPager oldWidget) {
    super.didUpdateWidget(oldWidget);
    _clampPage();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onPage(int page) {
    setState(() => _page = page);
    widget.onPageChanged(page);
  }

  @override
  Widget build(BuildContext context) {
    final photos = widget.card.photos;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          // ⚠️ **한 장이 9:16이지 페이저가 9:16이 아니다.** 한 장의 폭은
          // 뷰포트 폭의 [_viewport]배라 높이는 `폭 × _viewport × 16/9`다.
          // 그 값이 화면 높이의 [_maxHeightShare]를 넘으면 잘라 낸다 —
          // 사진은 `BoxFit.cover`라 잘려도 가운데가 남는다.
          height: _pagerHeight(context),
          child: Semantics(
            label: AppStrings.recordCardPageSemantics(
              index: _page + 1,
              count: _count,
            ),
            container: true,
            child: GestureDetector(
              // 탭하면 멈추고 다시 탭하면 이어간다. 무엇을 할지는 위가 정한다.
              onTap: widget.onTap,
              child: PageView.builder(
                controller: _controller,
                onPageChanged: _onPage,
                itemCount: _count,
                itemBuilder: (context, index) => Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.space1,
                  ),
                  child: _Page(
                    card: widget.card,
                    photo: index == 0 ? null : photos[index - 1],
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.space3),
        // ⚠️ **사진과 글 사이다.** 장이 하나뿐이면 두지 않는다 — 점 하나는
        // 알려 주는 것이 없다.
        if (_count > 1) ...[
          CardPageDots(count: _count, current: _page),
          const SizedBox(height: AppSpacing.space3),
        ],
        if (_below != null && _below!.trim().isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.space4),
            child: Text(
              _below!,
              textAlign: TextAlign.center,
              style: AppTypographyV2.body12.copyWith(
                color: context.appColorsV2.textSecondary,
              ),
            ),
          ),
      ],
    );
  }
}

/// 한 장. 첫 장은 경로 선 아트, 나머지는 사진이다.
class _Page extends StatelessWidget {
  const _Page({required this.card, required this.photo});

  final RecordCard card;

  /// `null`이면 경로 장이다.
  final RecordCardPhoto? photo;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColorsV2;

    return ClipRRect(
      borderRadius: AppRadius.lg,
      child: ColoredBox(
        color: colors.bgSurface,
        child: photo == null
            ? RouteArtView(
                art: card.route,
                color: colors.primary,
                strokeWidth: 3,
                padding: AppSpacing.space6,
              )
            : _Photo(card: card, url: photo!.url),
      ),
    );
  }
}

/// 포토북의 사진 한 장.
///
/// ## ⚠️ 못 받았으면 **한 번만** 다시 받는다
///
/// 조회용 주소는 1시간 뒤 만료된다(연동 가이드 7절). `403`이면 그 주소를 준
/// 상세(8-1)를 다시 불러야 하는데, 막지 않으면 **새 주소도 만료됐을 때 끝나지
/// 않는 고리**가 된다. 깃발은 위젯 상태에 둔다 — provider에 두면 다음 카드가
/// 그것을 물려받는다.
class _Photo extends ConsumerStatefulWidget {
  const _Photo({required this.card, required this.url});

  final RecordCard card;
  final String url;

  @override
  ConsumerState<_Photo> createState() => _PhotoState();
}

class _PhotoState extends ConsumerState<_Photo> {
  var _reported = false;

  void _expired() {
    if (_reported) return;
    _reported = true;
    // ⚠️ **그리는 중에 버리지 않는다.** `errorBuilder`는 빌드 안에서 불린다.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ref.invalidate(cardDetailProvider(widget.card.id));
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColorsV2;

    return Image(
      image: cardThumbnail(context, widget.url),
      fit: BoxFit.cover,
      errorBuilder: (context, _, _) {
        _expired();
        return RouteArtView(
          art: widget.card.route,
          color: colors.primary,
          strokeWidth: 3,
          padding: AppSpacing.space6,
        );
      },
    );
  }
}

/// 몇 번째 장인지 알리는 작은 흰 점들. **사진과 글 사이**에 선다.
class CardPageDots extends StatelessWidget {
  const CardPageDots({required this.count, required this.current, super.key});

  /// 점 지름.
  static const _size = 6.0;

  final int count;
  final int current;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColorsV2;

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var index = 0; index < count; index++) ...[
          if (index > 0) const SizedBox(width: AppSpacing.space1),
          Container(
            width: _size,
            height: _size,
            decoration: BoxDecoration(
              // 지금 장만 또렷하고 나머지는 흐리다.
              color: index == current ? colors.textStrong : colors.textDisabled,
              shape: BoxShape.circle,
            ),
          ),
        ],
      ],
    );
  }
}
