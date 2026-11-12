import 'package:flutter/material.dart';
import 'package:runiverse/core/strings/app_strings.dart';
import 'package:runiverse/core/theme/v2/app_colors.dart';
import 'package:runiverse/core/theme/v2/app_radius.dart';
import 'package:runiverse/core/theme/v2/app_spacing.dart';
import 'package:runiverse/core/theme/v2/app_typography.dart';
import 'package:runiverse/core/widgets/v2/party_chip.dart';

/// 메시지 한 줄.
///
/// ## ⚠️ 이름과 사진은 메시지가 들고 온 것이다
///
/// 서버가 메시지마다 보낸 사람을 실어 준다. 방 명단에서 찾지 않는다 — 방을
/// 떠난 사람의 지난 메시지가 전부 '탈퇴한 사용자'로 그려지기 때문이다.
///
/// 색만은 방 명단이 정한다. 러닝 화면에서 본 그 사람 색과 같아야 한다.
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
    this.deleted = false,
    this.edited = false,
    this.onLongPress,
    super.key,
  });

  /// 보여 줄 본문. [deleted]면 쓰지 않는다.
  final String text;

  /// `19:28`. **한국 시각으로 고정해서** 넘어온다.
  final String time;

  final bool mine;

  /// 남의 메시지에만 쓴다.
  final String nickname;

  /// 닉네임 색. 파티 색이라 러닝 화면에서 본 그 사람 색과 같다.
  final Color accent;

  final String? imageUrl;

  /// 보낸 사람이 지웠다. **자리를 지키고 문구만 바꾼다.**
  final bool deleted;

  /// 고친 적이 있다. 시각 옆에 "수정됨"을 붙인다.
  final bool edited;

  /// 길게 누르면 할 일. **내 메시지이고 안 지워졌을 때만 넘어온다** —
  /// 남의 말이나 지운 말에는 수정·삭제가 없다.
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColorsV2;

    // ⚠️ **지운 자리는 색과 기울기로 구분한다.** 같은 모양으로 두면 누가
    // "삭제된 메시지"라고 **말한 것처럼** 읽힌다.
    final body = deleted
        ? Text(
            AppStrings.chatDeleted,
            style: AppTypographyV2.body12.copyWith(
              color: colors.textTertiary,
              fontStyle: FontStyle.italic,
            ),
          )
        : Text(
            text,
            style: AppTypographyV2.body12.copyWith(
              color: mine ? colors.textOnPrimary : colors.textPrimary,
            ),
          );

    final bubble = GestureDetector(
      onLongPress: onLongPress,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.space3,
          vertical: AppSpacing.space2,
        ),
        decoration: BoxDecoration(
          color: deleted
              ? colors.bgSurface
              : (mine ? colors.primary : colors.bgSurface),
          borderRadius: AppRadius.lg,
        ),
        child: body,
      ),
    );

    final stamp = Column(
      crossAxisAlignment: mine
          ? CrossAxisAlignment.end
          : CrossAxisAlignment.start,
      children: [
        if (edited)
          Text(
            AppStrings.chatEdited,
            style: AppTypographyV2.body18.copyWith(color: colors.textTertiary),
          ),
        Text(
          time,
          style: AppTypographyV2.body18.copyWith(color: colors.textTertiary),
        ),
      ],
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

/// 아직 서버가 받지 않은 내 말.
///
/// ## ⚠️ 성공한 척 그리지 않는다
///
/// 보내는 중에는 흐리게, 실패하면 **다시 보내기와 지우기**를 함께 둔다. 성공한
/// 모양으로 두면 사람은 전해졌다고 믿고 방을 떠난다.
///
/// 자동으로 다시 보내지 않는다 — 응답을 못 받았어도 서버에는 저장됐을 수 있어
/// 같은 말이 두 번 남는다. 누를지는 사람이 정한다.
class ChatPendingBubble extends StatelessWidget {
  const ChatPendingBubble({
    required this.content,
    required this.failed,
    required this.onResend,
    required this.onDiscard,
    super.key,
  });

  final String content;
  final bool failed;
  final VoidCallback onResend;
  final VoidCallback onDiscard;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColorsV2;

    final bubble = Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.space3,
        vertical: AppSpacing.space2,
      ),
      decoration: BoxDecoration(
        color: colors.primary,
        borderRadius: AppRadius.lg,
      ),
      child: Text(
        content,
        style: AppTypographyV2.body12.copyWith(color: colors.textOnPrimary),
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            // 보내는 중에는 흐리게 둔다 — 멈춘 것이 아니라 가는 중이다.
            Flexible(child: Opacity(opacity: failed ? 1 : 0.5, child: bubble)),
          ],
        ),
        if (failed) ...[
          const SizedBox(height: AppSpacing.space1),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Text(
                AppStrings.chatSendFailed,
                style: AppTypographyV2.body18.copyWith(color: colors.error),
              ),
              const SizedBox(width: AppSpacing.space2),
              _Action(label: AppStrings.chatResend, onTap: onResend),
              const SizedBox(width: AppSpacing.space2),
              _Action(label: AppStrings.chatDiscard, onTap: onDiscard),
            ],
          ),
        ],
      ],
    );
  }
}

/// 실패한 말 아래의 작은 글자 버튼. **버튼처럼 크게 두지 않는다** — 대화보다
/// 눈에 띄면 안 된다.
class _Action extends StatelessWidget {
  const _Action({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColorsV2;

    return GestureDetector(
      onTap: onTap,
      child: Text(
        label,
        style: AppTypographyV2.body18.copyWith(
          color: colors.textSecondary,
          decoration: TextDecoration.underline,
        ),
      ),
    );
  }
}
