import 'package:flutter/material.dart';
import 'package:runiverse/core/strings/app_strings.dart';
import 'package:runiverse/core/theme/v2/app_colors.dart';
import 'package:runiverse/core/theme/v2/app_radius.dart';
import 'package:runiverse/core/widgets/card_face.dart';
import 'package:runiverse/features/record_card/domain/record_card_list_item.dart';
import 'package:runiverse/features/record_card/domain/route_art.dart';

/// 프로필 그리드의 칸 하나 — **9:16 사진 한 장**(설계 6-7).
///
/// 비율은 두는 쪽(그리드)이 정한다.
///
/// ## ⚠️ 사진이 없는 카드는 선을 못 긋는다
///
/// 10-3 항목에는 **경로가 없다**(연동 가이드 5절: "경로 선은 달력·상세 응답에서
/// 제공됩니다"). 그래서 썸네일이 없으면 [CardFace]가 점 하나를 남긴다 —
/// 달력 칸은 같은 카드에 선을 긋는다. **두 화면이 달라 보이는 자리**이고,
/// 경로를 이 응답에 실어 주면 같아진다.
class ProfileCardTile extends StatelessWidget {
  const ProfileCardTile({
    required this.card,
    required this.onTap,
    this.onExpired,
    super.key,
  });

  final RecordCardListItem card;

  final VoidCallback onTap;

  /// 사진을 못 받았다. **1시간 뒤 만료된다**(가이드 7절) — 두는 쪽이
  /// 그 주소를 준 조회를 버린다. 그리드와 전체 보기가 다른 조회를 쓴다.
  final VoidCallback? onExpired;

  @override
  Widget build(BuildContext context) => Semantics(
    // ⚠️ **칸에는 사진뿐이다.** 날짜도 숫자도 없어 스크린리더가 읽을 것이
    // 없다. 탭 바에 글자 라벨이 없는 것과 같은 문제다(CLAUDE.md).
    label: AppStrings.profileCardsOn(card.startedAt),
    button: true,
    // ⚠️ **탭 동작을 여기로 올린다.** [excludeSemantics]가 안쪽 노드를 가리면
    // 탭을 들고 있는 것도 함께 사라져, **읽히고 "버튼"이라고 말하지만 눌러도
    // 아무 일도 없는 칸**이 된다(달력 칸도 같은 이유로 둘을 함께 적는다).
    onTap: onTap,
    excludeSemantics: true,
    child: GestureDetector(
      onTap: onTap,
      child: ClipRRect(
        borderRadius: AppRadius.sm,
        // 사진을 못 받았거나 선이 한 점으로 뭉친 카드도 **칸으로 보여야**
        // 한다. 바탕이 없으면 빈 자리와 구별되지 않는다.
        child: ColoredBox(
          color: context.appColorsV2.bgSurface,
          child: CardFace(
            thumbnailUrl: card.thumbnailUrl,
            route: RouteArt.empty,
            onExpired: onExpired,
          ),
        ),
      ),
    ),
  );
}
