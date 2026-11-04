import 'package:flutter/material.dart';
import 'package:runiverse/core/strings/app_strings.dart';
import 'package:runiverse/core/theme/v2/app_colors.dart';
import 'package:runiverse/core/theme/v2/app_radius.dart';
import 'package:runiverse/core/theme/v2/app_spacing.dart';
import 'package:runiverse/core/theme/v2/app_typography.dart';
import 'package:runiverse/core/widgets/v2/app_input.dart';

/// 빠른 답장 칩 + 입력창.
///
/// ## ⚠️ 칩은 누르면 바로 보낸다
///
/// 입력창을 채우고 한 번 더 누르게 하면 칩을 둔 이유가 없어진다. 대신 **전송이
/// 끝날 때까지 칩을 잠근다** — 안 잠그면 같은 말이 다섯 번 도배된다.
///
/// 글자 수 제한을 두지 않는다. 서버 한도를 모르는데 조용히 자르는 것이 가장
/// 나쁘다.
class ChatComposer extends StatefulWidget {
  const ChatComposer({
    required this.onSend,
    required this.sendButtonKey,
    super.key,
  });

  /// 보낸다. **끝날 때까지 기다린다** — 그 동안 칩과 버튼이 잠긴다.
  final Future<void> Function(String text) onSend;

  final Key sendButtonKey;

  @override
  State<ChatComposer> createState() => _ChatComposerState();
}

class _ChatComposerState extends State<ChatComposer> {
  final _controller = TextEditingController();
  final _focus = FocusNode();

  var _sending = false;

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  bool get _typed => _controller.text.trim().isNotEmpty;

  /// [fromInput]이면 보낸 뒤 입력칸을 비운다.
  ///
  /// ⚠️ **칩은 비우지 않는다.** 칩 문구는 입력칸에서 온 것이 아니므로, 비우면
  /// 쓰다 말고 칩을 누른 사람의 **글을 지운다.**
  Future<void> _send(String text, {bool fromInput = false}) async {
    if (_sending || text.trim().isEmpty) return;

    setState(() => _sending = true);
    try {
      await widget.onSend(text);
      // 보낸 뒤 비우고 **포커스는 유지한다** — 연달아 말할 수 있어야 한다.
      if (fromInput) _controller.clear();
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColorsV2;
    final canSend = _typed && !_sending;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.space4,
        AppSpacing.space2,
        AppSpacing.space4,
        AppSpacing.space4,
      ),
      child: Column(
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final reply in AppStrings.chatQuickReplies)
                  Padding(
                    padding: const EdgeInsets.only(right: AppSpacing.space2),
                    child: _Chip(
                      label: reply,
                      onTap: _sending ? null : () => _send(reply),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.space3),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: AppInputV2(
                  controller: _controller,
                  focusNode: _focus,
                  hint: AppStrings.chatHint,
                  // 세 줄까지 늘어난다. 그 뒤로는 안에서 스크롤된다.
                  maxLines: 3,
                  textInputAction: TextInputAction.newline,
                  keyboardType: TextInputType.multiline,
                  onChanged: (_) => setState(() {}),
                ),
              ),
              const SizedBox(width: AppSpacing.space2),
              Semantics(
                button: true,
                enabled: canSend,
                label: AppStrings.chatSendSemantics,
                child: GestureDetector(
                  key: widget.sendButtonKey,
                  onTap: canSend
                      ? () => _send(_controller.text, fromInput: true)
                      : null,
                  // ⚠️ **PNG가 버튼 면 자체다.** 두 색 아이콘이라 틴트하면
                  // 화살표가 사라지고, 파란 원 위에 코랄 원을 또 얹을 수도 없다.
                  child: Opacity(
                    opacity: canSend ? 1 : 0.4,
                    child: Image.asset(
                      'assets/images/icon_send.png',
                      width: _sendSize,
                      height: _sendSize,
                      // 테스트 번들에 그림이 없어도 화면 전체가 죽지 않게 한다.
                      errorBuilder: (_, _, _) => Container(
                        width: _sendSize,
                        height: _sendSize,
                        decoration: BoxDecoration(
                          color: colors.primary,
                          borderRadius: AppRadius.full,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// 44 터치 타깃을 그림 자체로 채운다.
  static const _sendSize = 44.0;
}

class _Chip extends StatelessWidget {
  const _Chip({required this.label, this.onTap});

  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColorsV2;
    final locked = onTap == null;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.space3,
          vertical: AppSpacing.space2,
        ),
        decoration: BoxDecoration(
          color: colors.bgSurface,
          borderRadius: AppRadius.full,
          border: Border.all(color: colors.borderDefault),
        ),
        child: Text(
          label,
          style: AppTypographyV2.body12.copyWith(
            color: locked ? colors.textDisabled : colors.textSecondary,
          ),
        ),
      ),
    );
  }
}
