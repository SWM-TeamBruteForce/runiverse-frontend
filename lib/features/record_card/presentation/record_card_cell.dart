import 'dart:io';

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
    required this.hasUnwrittenRun,
    required this.onTap,
    super.key,
  });

  /// 이 칸의 날짜. 시·분이 잘려 있다.
  final DateTime day;

  /// 이 날의 카드. 비어 있으면 날짜만 그린다.
  final List<RecordCard> cards;

  /// 분기 보기에서는 칸이 26dp쯤이라 숫자가 안 읽힌다. 그때 `false`다.
  final bool showDayNumber;

  /// 이 날 **뛰었는데 카드를 안 썼나**. 운동화를 둘지 가른다.
  ///
  /// [cards]가 비어 있을 때만 쓴다 — 카드가 있으면 그림이 이미 칸을 채운다.
  final bool hasUnwrittenRun;

  /// `null`이면 눌리지 않는다.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColorsV2;
    // 가장 최근 카드를 깐다.
    final top = cards.isEmpty ? null : cards.last;

    // 뛴 것이 있는데 카드가 없는 칸은 눌러서 작성으로 간다. 운동화는 눈에만
    // 보이므로 읽는 말도 달라야 한다.
    final shoe = cards.isEmpty && hasUnwrittenRun;

    return Semantics(
      label: shoe
          ? AppStrings.recordCardCellUnwrittenSemantics(day)
          : AppStrings.recordCardCellSemantics(day: day, count: cards.length),
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
                  if (shoe) const RunShoeMark(),
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
      // ⚠️ **경로도 사진도 없는 카드가 있다.** 트레드밀이나 GPS를 못 받은
      // 러닝이다. 그대로 두면 `RouteArtView`가 아무것도 안 그려, 칸이 **안 뛴
      // 날과 픽셀 단위로 같아진다** — 쓴 카드를 달력에서 못 찾는다.
      if (card.route.isEmpty) return const CardMarkDot();

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

/// 뛰었는데 기록카드를 안 쓴 날의 자국.
///
/// ## ⚠️ 안 뛴 날과 갈라지는 것이 전부다
///
/// 날짜 숫자만 있는 칸이 "안 뛴 날"과 "쓸 거리가 있는 날"을 함께 뜻하면
/// **카드를 쓸 수 있는 날을 사용자가 찾을 수 없다.**
///
/// ## ⚠️ 색을 토큰으로 맞출 수 없다
///
/// 이모지는 제 색으로 그려져 `appColorsV2`가 닿지 않는다. 어두운 달력에서
/// 톤이 튀면 `LucideIcons.footprints`로 바꿀 자리다 — Lucide 에 운동화는
/// 없고 발자국이 가장 가깝다.
///
/// 크기를 고정한 이유: `FittedBox`로 늘리면 월 보기에서 칸을 가득 메우고,
/// 분기 보기(26dp 칸)에서는 이 크기가 들어간다.
class RunShoeMark extends StatelessWidget {
  const RunShoeMark({super.key});

  static const _fontSize = 14.0;

  @override
  Widget build(BuildContext context) => const Center(
    child: Text('👟', style: TextStyle(fontSize: _fontSize)),
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
