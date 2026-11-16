import 'package:flutter/material.dart';
import 'package:runiverse/core/strings/app_strings.dart';
import 'package:runiverse/core/theme/v2/app_colors.dart';
import 'package:runiverse/core/theme/v2/app_spacing.dart';
import 'package:runiverse/core/theme/v2/app_typography.dart';
import 'package:runiverse/core/widgets/v2/app_icon.dart';
import 'package:runiverse/features/record_card/domain/record_card.dart';
import 'package:runiverse/features/record_card/presentation/card_media_pager.dart';

/// 기록카드 한 장 — **포토북이다. 읽기만 한다.**
///
/// ## 위아래가 사진을 비켜 준다
///
/// 날짜와 기록은 **위 가운데**, 캡션은 **아래 가운데**다(시안). 가운데는
/// 사진 한 장이 크게 차지한다 — 숫자를 사진 옆에 늘어놓으면 둘 다 묻힌다.
///
/// ## ⚠️ 없는 버튼을 그려 두지 않는다
///
/// 수정·삭제(`⋮`)와 음악 줄은 다음 PR이다. 자리를 비워 두되 **눌러도 아무 데도
/// 가지 않는 버튼을 두지 않는다** — 고장으로 읽힌다(`run_summary_page.dart`가
/// 같은 이유를 적어 두었다).
///
/// ## ⚠️ 탭 셸 밖이다
///
/// 프로필 그리드나 러닝 요약에서 열어도 탭이 바뀌면 안 된다
/// (`app_routes.dart`의 `recordCardDetail`).
class CardDetailPage extends StatelessWidget {
  const CardDetailPage({required this.card, super.key});

  final RecordCard card;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColorsV2;

    return Scaffold(
      backgroundColor: colors.bgBase,
      appBar: AppBar(
        backgroundColor: colors.bgBase,
        // ⚠️ **제목을 두지 않는다.** 날짜는 바로 아래 가운데에 크게 선다.
        // 둘 다 두면 같은 말이 두 번이다.
        leading: IconButton(
          icon: const AppIcon(AppIcons.left),
          onPressed: () => Navigator.of(context).maybePop(),
          tooltip: AppStrings.authBack,
        ),
      ),
      body: ListView(
        // ⚠️ **바닥을 시스템에 비킨다.** 제스처 바가 맨 아래를 덮는다. 여기는
        // `SafeArea`로 감싸지 않고 여백에 직접 더한다 — 페이저가 화면 폭을
        // 꽉 써야 해서 좌우까지 깎이면 안 된다(`test/bottom_inset_test.dart`).
        padding: EdgeInsets.only(
          bottom: AppSpacing.space8 + MediaQuery.paddingOf(context).bottom,
        ),
        children: [
          _Header(card: card),
          const SizedBox(height: AppSpacing.space4),
          CardMediaPager(card: card),
          const SizedBox(height: AppSpacing.space4),
          // 캡션은 사진 바로 아래(페이저 안), 회고는 그 아래에 선다.
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.space4),
            child: Text(
              card.reviewText,
              textAlign: TextAlign.center,
              style: AppTypographyV2.body12.copyWith(
                color: context.appColorsV2.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 날짜 · 기록 · 함께 뛴 사람. **전부 가운데 정렬이다.**
class _Header extends StatelessWidget {
  const _Header({required this.card});

  final RecordCard card;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: AppSpacing.space4),
    // ⚠️ **유형과 함께 뛴 사람 줄은 두지 않는다.** 달력의 필터가 유형을 이미
    // 말했고, 줄이 늘면 사진·캡션·회고가 한 화면에서 밀려난다.
    child: Column(
      children: [
        Text(
          AppStrings.recordCardDateTitle(card.day),
          textAlign: TextAlign.center,
          style: AppTypographyV2.body07.copyWith(
            color: context.appColorsV2.textStrong,
          ),
        ),
        const SizedBox(height: AppSpacing.space1),
        // ⚠️ 한 덩어리 문자열로 잇지 않는다. 조각마다 따로 두어야 좁은 화면에서
        // 줄이 바뀌고, 테스트도 값 하나씩 짚을 수 있다.
        _MetaLine(
          parts: [
            '${AppStrings.kmFloor(card.distanceMeters)} '
                '${AppStrings.runPartyUnitKm}',
            AppStrings.recordRunDuration(card.duration),
            '${AppStrings.recordRunDuration(card.averagePace)}'
                '${AppStrings.runPartyUnitPerKm}',
          ],
        ),
      ],
    ),
  );
}

/// 가운데 정렬 메타 줄. 조각 사이에 가운뎃점을 넣는다.
class _MetaLine extends StatelessWidget {
  const _MetaLine({required this.parts});

  final List<String> parts;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColorsV2;
    // 상세에 남은 숫자가 이것뿐이라 작게 두면 읽을 것이 없어 보인다.
    final style = AppTypographyV2.body12.copyWith(color: colors.textPrimary);

    return Wrap(
      alignment: WrapAlignment.center,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        for (var index = 0; index < parts.length; index++) ...[
          if (index > 0) Text(AppStrings.recordCardMetaDot, style: style),
          Text(parts[index], style: style),
        ],
      ],
    );
  }
}
