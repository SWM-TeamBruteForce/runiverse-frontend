import 'package:flutter/material.dart';
import 'package:runiverse/core/strings/app_strings.dart';
import 'package:runiverse/core/theme/v2/app_colors.dart';
import 'package:runiverse/core/theme/v2/app_radius.dart';
import 'package:runiverse/core/theme/v2/app_spacing.dart';
import 'package:runiverse/core/theme/v2/app_typography.dart';
import 'package:runiverse/core/widgets/v2/party_chip.dart';

/// 메시지 한 줄.
///
/// ## ⚠️ 이름과 사진을 받아서 그린다
///
/// 메시지는 `senderUserId`만 들고 있다. 누구인지는 **화면이 방 명단에서 찾아**
/// 여기로 넘긴다 — 명단에 없으면 탈퇴 표기가 넘어온다.
///
/// 내 버블에는 이름도 사진도 붙이지 않는다. 내가 한 말인 것은 자리와 색으로
/// 이미 안다.
class ChatBubble extends StatelessWidget {
  const ChatBubble({
    required this.text,
    required this.time,
    required this.mine,
    required this.nickname,
    required this.accent,
    this.imageUrl,
    super.key,
  });

  final String text;

  /// `19:28`. **한국 시각으로 고정해서** 넘어온다.
  final String time;

  final bool mine;

  /// 남의 메시지에만 쓴다.
  final String nickname;

  /// 닉네임 색. 파티 색이라 러닝 화면에서 본 그 사람 색과 같다.
  final Color accent;

  final String? imageUrl;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColorsV2;

    final bubble = Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.space3,
        vertical: AppSpacing.space2,
      ),
      decoration: BoxDecoration(
        color: mine ? colors.primary : colors.bgSurface,
        borderRadius: AppRadius.lg,
      ),
      child: Text(
        text,
        style: AppTypographyV2.body12.copyWith(
          color: mine ? colors.textOnPrimary : colors.textPrimary,
        ),
      ),
    );

    final stamp = Text(
      time,
      style: AppTypographyV2.body18.copyWith(color: colors.textTertiary),
    );

    if (mine) {
      return Row(
        mainAxisAlignment: MainAxisAlignment.end,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          stamp,
          const SizedBox(width: AppSpacing.space2),
          // ⚠️ `Flexible`이어야 긴 한 줄이 줄바꿈으로 접힌다. 안 감싸면
          // 가로로 밀고 나가 넘친다.
          Flexible(child: bubble),
        ],
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        PartyChip(
          name: nickname,
          accent: accent,
          imageUrl: imageUrl,
          size: 32,
          showName: false,
        ),
        const SizedBox(width: AppSpacing.space2),
        Flexible(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                nickname,
                style: AppTypographyV2.body19.copyWith(color: accent),
              ),
              const SizedBox(height: AppSpacing.space1),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Flexible(child: bubble),
                  const SizedBox(width: AppSpacing.space2),
                  stamp,
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// 누가 들어왔다는 알림. **버블이 아니다.**
///
/// 가운데 회색 알약으로 둔다 — 버블처럼 보이면 누가 한 말인지 모를 발언이 된다.
class ChatJoinedNotice extends StatelessWidget {
  const ChatJoinedNotice({required this.nickname, super.key});

  final String nickname;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColorsV2;

    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.space3,
          vertical: AppSpacing.space1,
        ),
        decoration: BoxDecoration(
          color: colors.bgSurface,
          borderRadius: AppRadius.full,
        ),
        child: Text(
          AppStrings.chatJoined(nickname),
          style: AppTypographyV2.body18.copyWith(color: colors.textTertiary),
        ),
      ),
    );
  }
}
