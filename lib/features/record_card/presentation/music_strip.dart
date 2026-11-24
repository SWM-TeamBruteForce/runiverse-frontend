import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:runiverse/core/strings/app_strings.dart';
import 'package:runiverse/core/theme/v2/app_colors.dart';
import 'package:runiverse/core/theme/v2/app_spacing.dart';
import 'package:runiverse/core/theme/v2/app_typography.dart';
import 'package:runiverse/features/record_card/domain/card_music.dart';
import 'package:runiverse/features/record_card/presentation/card_music_provider.dart';

/// 카드 상세의 **음악 한 줄** (설계 6-5).
///
/// ## ⚠️ 줄은 **지금 보고 있는 장**의 곡을 말한다
///
/// 곡이 장마다 하나다(연동 가이드 2절) — 기본곡 하나 + 사진마다 하나. 그래서
/// 줄도 장을 넘길 때마다 달라진다. 묶음 5까지는 상태가 카드 하나에 하나여서
/// 줄도 카드 하나에 하나였다.
///
/// `다시 만들기`는 **못 만든 곡 전부**를 다시 건다 — 서버가 `FAILED`인 것만
/// 골라서, 어느 장에서 눌러도 결과가 같다(가이드 4절).
///
/// ## ⚠️ 진행바를 두지 않는다
///
/// 설계 8절이 "▶를 누르면 진행바가 찬다"고 적었지만, **2026-11-17에 사용자가
/// 기기에서 보고 차는 막대를 작은 흰 점으로 바꿨다**(6-5의 변경 기록) — 남은
/// 시간을 안 알리는 쪽으로 정한 것이고, 11절이 그것을 미결로 적어 두었다.
/// 여기서 막대를 되살리면 그 결정을 조용히 뒤집는다. **점이 몇 번째 장인지
/// 말하고, 이 줄은 음악을 말한다.**
///
/// ## ⚠️ 이 줄은 오디오를 모른다
///
/// `재생`/`멈춤`은 **소리**를 쥐지만(2026-11-25부터 `just_audio`로 실제로
/// 난다), 트는 일은 상세 화면이 한다. 이 줄은 [playing]을 받아 글자를 고르고
/// 눌린 것을 [onTogglePlay]로 올려 보낼 뿐이다 — 설계 6-1이 "두 군데서 몰면
/// 어긋난다"고 적은 그 선이다.
class MusicStrip extends ConsumerWidget {
  const MusicStrip({
    required this.cardId,
    required this.music,
    required this.hasFailed,
    required this.playing,
    required this.canRequest,
    required this.onTogglePlay,
    super.key,
  });

  /// 줄 높이. **세 갈래가 같은 높이여야** 받아 오는 동안 아래가 튀지 않는다.
  static const _height = 40.0;

  final String cardId;

  /// **지금 보고 있는 장**의 곡. 서버가 안 줬으면 `null`이다.
  ///
  /// ⚠️ `null`과 실패는 다르다 — 못 만든 것과 아직 모르는 것을 같이 보면,
  /// 받아 오는 중인 카드에 "못 만들었어요"가 선다.
  final CardMusic? music;

  /// 이 카드에 **못 만든 곡이 하나라도** 있나.
  ///
  /// ⚠️ **지금 장이 아니라 카드 전체를 본다.** 재요청은 `FAILED`인 곡 전부를
  /// 다시 거는 것이라(가이드 4절), 다 된 장에 서 있어도 다른 장이 실패했으면
  /// 다시 걸 일이 있다.
  final bool hasFailed;

  /// 소리가 지금 나고 있나. **줄은 이것의 반대를 권한다** — 나고 있으면
  /// `멈춤`, 멈춰 있으면 `재생`이다.
  final bool playing;

  /// 음악을 만들라고 할 수 있나. **내 카드가 아니면 못 한다** — 생성 요청은
  /// 쓰기다(설계 6-5 "남의 카드면 `⋮`가 없다"와 같은 선).
  ///
  /// ⚠️ **못 할 때는 줄을 아예 세우지 않는다**(다 된 음악만 예외). 못 하는 일을
  /// 적어 두면 남의 카드에 쓸모없는 글이 남고, 빈 40px만 남기면 그 자리가
  /// 고장으로 읽힌다.
  final bool canRequest;

  final VoidCallback onTogglePlay;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final retry = ref.watch(cardMusicProvider(cardId));
    final playable = music?.isPlayable ?? false;

    // ⚠️ **남의 카드에서는 들을 수만 있다.** 듣는 것은 읽기라 다 된 곡은
    // 그대로 세우고, 나머지(없다·만드는 중·실패)는 자리를 비운다.
    if (!canRequest && !playable) return const SizedBox.shrink();

    return SizedBox(
      height: _height,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.space4),
        child: switch (retry) {
          // ⚠️ **요청이 날아가는 동안을 먼저 가린다.** 상태는 아직 바뀌지
          // 않았으므로, 안 가리면 같은 라벨이 그대로 서서 누른 사람에게
          // 아무 일도 일어나지 않은 것으로 보인다.
          CardMusicRetrying() => const _Line(
            label: AppStrings.recordCardMusicRequesting,
          ),
          CardMusicRetryFailed() => _Line(
            label: AppStrings.recordCardMusicError,
            action: AppStrings.recordCardMusicReload,
            onAction: () =>
                ref.read(cardMusicProvider(cardId).notifier).retry(),
          ),
          CardMusicIdle() => _forMusic(context, ref),
        },
      ),
    );
  }

  Widget _forMusic(BuildContext context, WidgetRef ref) {
    void retry() => ref.read(cardMusicProvider(cardId).notifier).retry();

    // ⚠️ **아직 안 온 곡에는 아무 말도 하지 않는다.** 한 프레임일 수도 있는
    // 구간에 글자를 세우면 열 때마다 글자가 번쩍인다. 자리만 지킨다.
    //
    // 다만 **다른 장이 실패했으면** 다시 걸 길은 남긴다 — 이 장이 아직
    // 안 왔다고 그 길이 사라지면, 실패한 장으로 넘어가야만 누를 수 있다.
    final here = music;
    if (here == null) {
      return hasFailed
          ? _Line(
              label: AppStrings.recordCardMusicFailed,
              action: AppStrings.recordCardMusicRetry,
              onAction: retry,
            )
          : const _Line();
    }

    return switch (here.status) {
      MusicStatus.generating => const _Line(
        label: AppStrings.recordCardMusicProcessing,
      ),
      // ⚠️ **지금 상태가 아니라 "누르면 될 일"을 쓴다.** 상세를 열면 소리가
      // 이미 나고 있어서, 나는 중에 `재생`을 세우면 이미 하는 것을 하라는
      // 버튼이다.
      //
      // ⚠️ **마지막 장에도 선다.** 곡이 끝나면 반복하므로 "넘어갈 장이
      // 있나"는 더 이상 묻지 않는다(설계 2절).
      MusicStatus.completed => _Line(
        icon: playing ? LucideIcons.pause : LucideIcons.play,
        label: playing
            ? AppStrings.recordCardMusicPause
            : AppStrings.recordCardMusicPlay,
        onTap: onTogglePlay,
      ),
      MusicStatus.failed => _Line(
        label: AppStrings.recordCardMusicFailed,
        action: AppStrings.recordCardMusicRetry,
        onAction: retry,
      ),
    };
  }
}

/// 줄 하나 — 아이콘 · 말 · (있으면) 오른쪽 버튼.
class _Line extends StatelessWidget {
  const _Line({
    this.icon = LucideIcons.music,
    this.label,
    this.onTap,
    this.action,
    this.onAction,
  });

  final IconData icon;

  /// `null`이면 자리만 지킨다(받아 오는 중).
  final String? label;

  /// 줄 전체를 누를 수 있나.
  final VoidCallback? onTap;

  /// 오른쪽 끝의 작은 버튼. `다시 만들기` · `다시`.
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColorsV2;
    final text = label;

    final row = Row(
      children: [
        Icon(
          icon,
          size: 16,
          // 말이 없는 구간(받아 오는 중)은 아이콘도 흐리다.
          color: text == null ? colors.textDisabled : colors.textSecondary,
        ),
        const SizedBox(width: AppSpacing.space2),
        Expanded(
          child: text == null
              ? const SizedBox.shrink()
              : Text(
                  text,
                  style: AppTypographyV2.body20.copyWith(
                    color: colors.textSecondary,
                  ),
                ),
        ),
        if (action != null)
          TextButton(
            onPressed: onAction,
            child: Text(
              action!,
              style: AppTypographyV2.body20.copyWith(color: colors.primary),
            ),
          ),
      ],
    );

    // ⚠️ **글자 라벨이 없는 구간이 있다**(받아 오는 중에는 아이콘만 선다).
    // 그래서 줄에 라벨을 박아 둔다 — 탭 바와 같은 이유다(CLAUDE.md).
    final labelled = Semantics(
      container: true,
      button: onTap != null,
      label: text == null
          ? AppStrings.recordCardMusicSemantics
          : '${AppStrings.recordCardMusicSemantics} $text',
      child: ExcludeSemantics(excluding: text == null, child: row),
    );

    if (onTap == null) return Center(child: labelled);

    return Center(
      child: GestureDetector(
        // 글자만 누르면 어디를 눌러야 하는지 알기 어렵다 — 줄 전체를 받는다.
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: labelled,
      ),
    );
  }
}
