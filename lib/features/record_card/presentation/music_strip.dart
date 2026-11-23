import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:runiverse/core/strings/app_strings.dart';
import 'package:runiverse/core/theme/v2/app_colors.dart';
import 'package:runiverse/core/theme/v2/app_spacing.dart';
import 'package:runiverse/core/theme/v2/app_typography.dart';
import 'package:runiverse/features/record_card/domain/music_generation.dart';
import 'package:runiverse/features/record_card/presentation/card_music_provider.dart';

/// 카드 상세의 **음악 한 줄** (설계 6-5).
///
/// ## ⚠️ 줄이 하나다
///
/// 상태가 카드 하나에 하나라서(설계 3절) "3번 사진 음악만 다시"가 없다. 그래서
/// 줄도 하나이고, `다시 만들기`는 **전곡**을 다시 만든다.
///
/// ## ⚠️ 진행바를 두지 않는다
///
/// 설계 8절이 "▶를 누르면 진행바가 찬다"고 적었지만, **2026-11-17에 사용자가
/// 기기에서 보고 차는 막대를 작은 흰 점으로 바꿨다**(6-5의 변경 기록) — 남은
/// 시간을 안 알리는 쪽으로 정한 것이고, 11절이 그것을 미결로 적어 두었다.
/// 여기서 막대를 되살리면 그 결정을 조용히 뒤집는다. **점이 몇 번째 장인지
/// 말하고, 이 줄은 음악을 말한다.**
///
/// ## ⚠️ 소리가 없다
///
/// 오디오 패키지를 안 넣는다(설계 9절). `재생`은 **포토북이 장을 넘기는
/// 것**이고, 음악이 붙으면 넘기는 길이의 출처만 바뀐다.
class MusicStrip extends ConsumerWidget {
  const MusicStrip({
    required this.cardId,
    required this.playing,
    required this.canAdvance,
    required this.canRequest,
    required this.onTogglePlay,
    super.key,
  });

  /// 줄 높이. **세 갈래가 같은 높이여야** 받아 오는 동안 아래가 튀지 않는다.
  static const _height = 40.0;

  final String cardId;

  /// 포토북이 지금 넘어가고 있나. **줄은 이것의 반대를 권한다.**
  final bool playing;

  /// 더 넘어갈 장이 있나.
  ///
  /// ⚠️ **없으면 `재생`도 `멈춤`도 거짓이다.** 사진이 없는 카드는 한 장뿐이라
  /// 타이머를 아예 걸지 않고, 마지막 장에서는 멈춘 뒤 처음으로 돌아가지
  /// 않는다(설계 6-5) — 그 자리에 토글을 세우면 **눌러도 아무 일도 없는
  /// 버튼**이 된다.
  final bool canAdvance;

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
    final state = ref.watch(cardMusicProvider(cardId));

    // ⚠️ **남의 카드에서는 들을 수만 있다.** 듣는 것은 읽기라 다 된 음악은
    // 그대로 세우고, 나머지(없다·만드는 중·실패·못 읽음)는 자리를 비운다.
    if (!canRequest &&
        !(state is CardMusicData && state.generation.isPlayable)) {
      return const SizedBox.shrink();
    }

    return SizedBox(
      height: _height,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.space4),
        child: switch (state) {
          // ⚠️ 받아 오는 동안 **아무 말도 하지 않는다.** 한 프레임일 수도 있는
          // 구간에 글자를 세우면 열 때마다 글자가 번쩍인다. 자리만 지킨다.
          CardMusicLoading() => const _Line(),
          CardMusicError() => _Line(
            label: AppStrings.recordCardMusicError,
            action: AppStrings.recordCardMusicReload,
            onAction: () => ref.read(cardMusicProvider(cardId).notifier).load(),
          ),
          // ⚠️ **요청이 날아가는 동안을 먼저 가린다.** 상태는 아직 바뀌지
          // 않았으므로, 안 가리면 같은 라벨이 그대로 서서 누른 사람에게
          // 아무 일도 일어나지 않은 것으로 보인다.
          CardMusicData(requesting: true) => const _Line(
            label: AppStrings.recordCardMusicRequesting,
          ),
          CardMusicData(:final generation) => _forStatus(
            context,
            ref,
            generation,
          ),
        },
      ),
    );
  }

  Widget _forStatus(
    BuildContext context,
    WidgetRef ref,
    MusicGeneration music,
  ) {
    void request() => ref.read(cardMusicProvider(cardId).notifier).request();

    return switch (music.status) {
      // 줄 전체가 버튼이다 — 누르는 곳이 글자뿐이면 어디를 누를지 헷갈린다.
      MusicStatus.none => _Line(
        label: AppStrings.recordCardMusicCreate,
        onTap: request,
      ),
      MusicStatus.queued => const _Line(
        label: AppStrings.recordCardMusicQueued,
      ),
      MusicStatus.processing => const _Line(
        label: AppStrings.recordCardMusicProcessing,
      ),
      // ⚠️ **지금 상태가 아니라 "누르면 될 일"을 쓴다.** 상세를 열면 책이 이미
      // 돌고 있어서, 도는 중에 `재생`을 세우면 이미 하는 것을 하라는 버튼이다.
      // 넘어갈 장이 없으면 둘 다 거짓이라 **버튼을 두지 않는다**([canAdvance]).
      MusicStatus.succeeded =>
        canAdvance
            ? _Line(
                icon: playing ? LucideIcons.pause : LucideIcons.play,
                label: playing
                    ? AppStrings.recordCardMusicPause
                    : AppStrings.recordCardMusicPlay,
                onTap: onTogglePlay,
              )
            : const _Line(label: AppStrings.recordCardMusicReady),
      MusicStatus.failed => _Line(
        label: AppStrings.recordCardMusicFailed,
        action: AppStrings.recordCardMusicRetry,
        onAction: request,
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
