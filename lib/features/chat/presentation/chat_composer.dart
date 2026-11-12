import 'package:flutter/material.dart';
import 'package:runiverse/core/strings/app_strings.dart';
import 'package:runiverse/core/theme/v2/app_colors.dart';
import 'package:runiverse/core/theme/v2/app_radius.dart';
import 'package:runiverse/core/theme/v2/app_spacing.dart';
import 'package:runiverse/core/theme/v2/app_typography.dart';
import 'package:runiverse/core/widgets/v2/app_input.dart';
import 'package:runiverse/features/chat/presentation/chat_provider.dart';

/// 빠른 답장 칩 + 입력창.
///
/// ## ⚠️ 칩은 누르면 바로 보낸다
///
/// 입력창을 채우고 한 번 더 누르게 하면 칩을 둔 이유가 없어진다. 대신 **전송이
/// 끝날 때까지 칩을 잠근다** — 안 잠그면 같은 말이 다섯 번 도배된다.
///
/// ## ⚠️ 200자를 넘으면 자르지 않고 막는다
///
/// 서버가 받는 길이가 1~200자다. `maxLength`로 입력을 끊으면 **붙여넣은 글이
/// 조용히 잘린다.** 그래서 넘겨 쓸 수는 있게 두고 보내기만 잠근다 — 무엇이
/// 문제인지 보이고, 쓴 말은 그대로 남는다.
///
/// ## 수정도 이 입력창에서 한다
///
/// [editing]이 들어오면 그 내용을 채우고 칩을 감춘다. 수정 중에 "곧 도착해요"를
/// 누를 일은 없고, 누르면 고치던 내용이 날아간다.
class ChatComposer extends StatefulWidget {
  const ChatComposer({
    required this.onSend,
    required this.sendButtonKey,
    this.editing,
    this.onCancelEdit,
    super.key,
  });

  /// 보낸다(수정 중이면 고친다). **끝날 때까지 기다린다** — 그 동안 칩과
  /// 버튼이 잠긴다.
  final Future<void> Function(String text) onSend;

  final Key sendButtonKey;

  /// 수정 중인 메시지의 **현재 내용.** `null`이면 새 메시지를 쓰는 중이다.
  final String? editing;

  final VoidCallback? onCancelEdit;

  @override
  State<ChatComposer> createState() => _ChatComposerState();
}

class _ChatComposerState extends State<ChatComposer> {
  final _controller = TextEditingController();
  final _focus = FocusNode();

  var _sending = false;

  @override
  void didUpdateWidget(ChatComposer old) {
    super.didUpdateWidget(old);
    if (widget.editing == old.editing) return;

    final editing = widget.editing;
    if (editing == null) {
      // 수정이 끝났거나 취소됐다. 고치던 글을 남겨두면 다음에 쓸 때 섞인다.
      _controller.clear();
    } else {
      // ⚠️ **커서를 끝에 둔다.** 기본값은 맨 앞이라, 고치려고 누른 사람이
      // 글 앞에서 타이핑하게 된다.
      _controller.value = TextEditingValue(
        text: editing,
        selection: TextSelection.collapsed(offset: editing.length),
      );
      _focus.requestFocus();
    }
    setState(() {});
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  bool get _typed => _controller.text.trim().isNotEmpty;

  /// 서버가 받는 길이를 넘겼는가. **자르지 않고 보내기만 잠근다.**
  bool get _tooLong =>
      _controller.text.trim().length > ChatController.maxLength;

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
    final canSend = _typed && !_sending && !_tooLong;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.space4,
        AppSpacing.space2,
        AppSpacing.space4,
        AppSpacing.space4,
      ),
      child: Column(
        children: [
          // ⚠️ 수정 중에는 칩을 감춘다. 누르면 고치던 내용이 날아간다.
          if (widget.editing == null)
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
            )
          else
            Row(
              children: [
                Text(
                  AppStrings.chatEditing,
                  style: AppTypographyV2.body18.copyWith(
                    color: colors.textSecondary,
                  ),
                ),
                const Spacer(),
                GestureDetector(
                  onTap: widget.onCancelEdit,
                  child: Text(
                    AppStrings.chatEditCancel,
                    style: AppTypographyV2.body18.copyWith(
                      color: colors.textSecondary,
                      decoration: TextDecoration.underline,
                    ),
                  ),
                ),
              ],
            ),
          if (_tooLong) ...[
            const SizedBox(height: AppSpacing.space1),
            Row(
              children: [
                Text(
                  AppStrings.chatTooLong,
                  style: AppTypographyV2.body18.copyWith(color: colors.error),
                ),
              ],
            ),
          ],
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
