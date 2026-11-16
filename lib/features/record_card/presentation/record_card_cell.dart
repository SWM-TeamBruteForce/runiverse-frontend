import 'package:flutter/material.dart';
import 'package:runiverse/core/strings/app_strings.dart';
import 'package:runiverse/core/theme/v2/app_colors.dart';
import 'package:runiverse/core/theme/v2/app_radius.dart';
import 'package:runiverse/core/theme/v2/app_spacing.dart';
import 'package:runiverse/core/theme/v2/app_typography.dart';
import 'package:runiverse/core/widgets/profile_photo_image.dart';
import 'package:runiverse/features/record_card/domain/record_card.dart';
import 'package:runiverse/features/record_card/presentation/route_art_view.dart';

/// 달력의 날짜 한 칸.
///
/// ## ⚠️ 카드를 쓴 날은 반드시 달라 보여야 한다
///
/// 사진이 있으면 썸네일, **없으면 그날의 경로 선**을 그린다. 썸네일이 없다고
/// 칸을 비우면 카드를 쓴 날이 안 쓴 날처럼 보인다.
///
/// ## ⚠️ 하루에 카드가 둘 이상일 수 있다
///
/// 하루에 두 번 뛰면 기록이 둘이고 카드도 둘이다. 최신 것을 깔고 **오른쪽 위에
/// 개수 배지**를 둔다. 하나뿐이면 배지를 두지 않는다 — `1`은 알려 주는 것이 없다.
class RecordCardCell extends StatelessWidget {
  const RecordCardCell({
    required this.day,
    required this.cards,
    required this.showDayNumber,
    required this.onTap,
    super.key,
  });

  /// 이 칸의 날짜. 시·분이 잘려 있다.
  final DateTime day;

  /// 이 날의 카드. 비어 있으면 날짜만 그린다.
  final List<RecordCard> cards;

  /// 분기 보기에서는 칸이 26dp쯤이라 숫자가 안 읽힌다. 그때 `false`다.
  final bool showDayNumber;

  /// `null`이면 눌리지 않는다.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColorsV2;
    // 가장 최근 카드를 깐다.
    final top = cards.isEmpty ? null : cards.last;

    return Semantics(
      label: AppStrings.recordCardCellSemantics(day: day, count: cards.length),
      button: onTap != null,
      onTap: onTap,
      // ⚠️ **`container`가 없으면 라벨이 자기 노드를 못 만든다** — 조상에
      // 얹히기만 해서 아무것도 읽히지 않는다(`runner_avatar.dart:41-46`).
      container: true,
      // ⚠️ **속을 읽지 않게 막는다.** 안 막으면 날짜 숫자와 개수 배지가 따로
      // 읽혀 `2`, `2`가 뒤따른다 — 라벨이 이미 다 말했다.
      excludeSemantics: true,
      child: GestureDetector(
        onTap: onTap,
        // 빈 칸에도 탭이 닿아야 한다. 안 그러면 투명한 데가 눌리지 않는다.
        behavior: HitTestBehavior.opaque,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.space1 / 2),
          child: ClipRRect(
            borderRadius: AppRadius.sm,
            child: ColoredBox(
              color: colors.bgSurface,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (top != null) _Face(card: top),
                  if (showDayNumber)
                    Align(
                      alignment: Alignment.bottomCenter,
                      child: Padding(
                        padding: const EdgeInsets.only(
                          bottom: AppSpacing.space1,
                        ),
                        child: _DayNumber(day: day, covered: top != null),
                      ),
                    ),
                  if (cards.length > 1)
                    Align(
                      alignment: Alignment.topRight,
                      child: _CountBadge(count: cards.length),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 칸을 채우는 그림 — 썸네일이 있으면 사진, 없으면 선.
class _Face extends StatelessWidget {
  const _Face({required this.card});

  final RecordCard card;

  @override
  Widget build(BuildContext context) {
    final url = card.thumbnailUrl;
    if (url == null) {
      return RouteArtView(
        art: card.route,
        color: context.appColorsV2.primary,
        strokeWidth: 1.5,
        padding: AppSpacing.space1,
      );
    }

    return Image(
      image: cardThumbnail(context, url),
      fit: BoxFit.cover,
      // 못 받아도 칸이 비지 않게 선으로 떨어진다.
      errorBuilder: (context, _, _) => RouteArtView(
        art: card.route,
        color: context.appColorsV2.primary,
        strokeWidth: 1.5,
        padding: AppSpacing.space1,
      ),
    );
  }
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
/// 서명이 붙은 주소는 [ProfilePhotoImage]에 맡긴다. 조회할 때마다 서명이
/// 달라져도 **경로가 같으면 다시 받지 않는다.**
ImageProvider<Object> cardThumbnail(BuildContext context, String url) {
  if (url.startsWith('assets/')) return AssetImage(url);
  return ProfilePhotoImage(url);
}

class _DayNumber extends StatelessWidget {
  const _DayNumber({required this.day, required this.covered});

  final DateTime day;

  /// 그림 위에 얹히나. 그러면 글자가 묻히지 않게 그늘을 깐다.
  final bool covered;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColorsV2;

    return Container(
      padding: covered
          ? const EdgeInsets.symmetric(horizontal: 4, vertical: 1)
          : EdgeInsets.zero,
      decoration: covered
          ? BoxDecoration(color: colors.bgScrim, borderRadius: AppRadius.sm)
          : null,
      child: Text(
        '${day.day}',
        style: AppTypographyV2.body18.copyWith(
          color: covered ? colors.textOnPrimary : colors.textTertiary,
        ),
      ),
    );
  }
}

class _CountBadge extends StatelessWidget {
  const _CountBadge({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColorsV2;

    return Container(
      margin: const EdgeInsets.all(2),
      padding: const EdgeInsets.symmetric(horizontal: 4),
      decoration: BoxDecoration(
        color: colors.primary,
        borderRadius: AppRadius.sm,
      ),
      child: Text(
        '$count',
        style: AppTypographyV2.body18.copyWith(color: colors.textOnPrimary),
      ),
    );
  }
}
