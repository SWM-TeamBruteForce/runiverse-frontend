import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:runiverse/core/strings/app_strings.dart';
import 'package:runiverse/core/theme/v2/app_colors.dart';
import 'package:runiverse/core/theme/v2/app_spacing.dart';
import 'package:runiverse/core/theme/v2/app_typography.dart';
import 'package:runiverse/core/widgets/v2/app_input.dart';
import 'package:runiverse/features/onboarding/domain/nickname_rule.dart';
import 'package:runiverse/features/profile/domain/nickname_change_failure.dart';
import 'package:runiverse/features/profile/presentation/profile_provider.dart';

/// 닉네임을 **그 자리에서** 고치는 칸.
///
/// ## ⚠️ 여기서 보내지 않는다
///
/// 전에는 시트였고 **누르는 자리에서 즉시 저장**됐다. 인라인으로 내려오면서
/// (2026-10-22 요청) 보내는 일은 편집 화면의 저장 버튼이 맡는다. 이 위젯은
/// **보낼 수 있는 값인지**만 판정해 [onReady]로 넘긴다.
///
/// ## 중복확인은 여기 남는다
///
/// 치는 동안 0.5초 쉬면 서버에 묻는다. 저장 버튼까지 미루면 사용자는 이름을
/// 다 짓고 나서야 "이미 있어요"를 듣는다.
///
/// ⚠️ 그래도 **저장할 때 또 겹칠 수 있다.** 묻고 누르는 사이에 남이 가져갈 수
/// 있어서다. 그때는 화면이 [submitFailure]로 알려 주고, 이 칸이 같은 자리에
/// 같은 문구를 띄운다 — 고칠 곳이 여기라는 뜻이다.
class NicknameField extends ConsumerStatefulWidget {
  const NicknameField({
    required this.current,
    required this.onReady,
    this.submitFailure,
    super.key,
  });

  /// 지금 쓰는 이름. **서버가 준 값이다** — 이것과 같으면 보낼 것이 없다.
  final String? current;

  /// 보낼 수 있는 값이면 그 값, 아니면 `null`.
  ///
  /// ⚠️ **`null`이 두 가지 뜻을 겸한다** — "안 바꿨다"와 "아직 못 보낸다".
  /// 화면 입장에서는 둘 다 *닉네임은 보내지 않는다*라서 가를 이유가 없다.
  final ValueChanged<String?> onReady;

  /// 저장하다 겹쳤다. 들어오면 칸 아래 문구가 그것으로 바뀐다.
  final NicknameChangeFailure? submitFailure;

  @override
  ConsumerState<NicknameField> createState() => _NicknameFieldState();
}

class _NicknameFieldState extends ConsumerState<NicknameField> {
  late final _nickname = TextEditingController(text: widget.current ?? '');

  /// 서버에 묻는 중.
  bool _checking = false;

  /// 물어보지 못했다. ⚠️ **"이미 있다"와 다르다** — 묶으면 네트워크가 잠깐
  /// 끊긴 것 때문에 멀쩡한 이름을 버리게 된다.
  bool _checkFailed = false;

  /// 마지막으로 답을 받은 이름과 그 답. **어떤 이름의 답인지 함께 들고 있어야**
  /// 이름을 고친 뒤에 지난 답이 남지 않는다.
  String? _checkedNickname;
  bool? _checkedAvailable;

  Timer? _checkTimer;
  static const _checkDebounce = Duration(milliseconds: 500);

  @override
  void didUpdateWidget(NicknameField old) {
    super.didUpdateWidget(old);
    // ⚠️ **서버 값이 뒤늦게 왔다.** 요약 조회가 끝나기 전에 이 칸이 먼저
    // 그려지면 빈 칸으로 열리는데, 그대로 두면 사용자가 손대지 않았는데도
    // "이름을 지웠다"가 된다. 손대지 않은 칸만 따라간다.
    if (old.current != widget.current &&
        _nickname.text == (old.current ?? '')) {
      _nickname.text = widget.current ?? '';
    }
  }

  @override
  void dispose() {
    _checkTimer?.cancel();
    _nickname.dispose();
    super.dispose();
  }

  // ── 판정 ──────────────────────────────────────────────────

  /// 사람이 보는 글자 수. 자소 단위로 센다 — 입력을 자르는
  /// [LengthLimitingTextInputFormatter]와 같은 기준이다.
  int get _length => _nickname.text.trim().characters.length;

  NicknameStatus get _status => NicknameRule.of(_length, _nickname.text.trim());

  /// 지금 쓰는 이름 그대로다.
  ///
  /// ## ⚠️ 이때는 서버에 묻지 않는다
  ///
  /// 중복확인은 "누가 쓰고 있나"를 답하는데, 이 이름을 쓰고 있는 사람은
  /// **본인이다.** 그대로 물으면 서버가 `available: false`라고 답하고,
  /// 화면에는 자기 이름 위에 빨간 경고가 뜬다.
  bool get _isUnchanged => _nickname.text.trim() == (widget.current ?? '');

  /// 이 이름에 대한 **답**을 들고 있는가. 실패한 확인은 답으로 치지 않는다.
  bool get _hasFreshAnswer =>
      _checkedAvailable != null && _checkedNickname == _nickname.text.trim();

  /// 보낼 수 있는가. 시트의 `_canSubmit`과 같은 판정이다.
  bool get _ready =>
      _status.isValid &&
      !_isUnchanged &&
      !_checking &&
      _hasFreshAnswer &&
      _checkedAvailable == true;

  /// 지금 판정을 화면에 알린다. **빌드 중에 부르지 않는다** — 부모가
  /// `setState`를 하게 되어 Flutter가 막는다.
  void _report() {
    widget.onReady(_ready ? _nickname.text.trim() : null);
  }

  // ── 중복확인 ──────────────────────────────────────────────

  /// 이름이 바뀌었다. **서버가 한 말은 전부 낡은 말이 된다.**
  void _onChanged() {
    _checkTimer?.cancel();
    setState(() {
      _checkedNickname = null;
      _checkedAvailable = null;
      _checkFailed = false;
    });
    _report();

    // 형식이 틀렸거나 바뀐 게 없으면 묻지 않는다.
    if (!_status.isValid || _isUnchanged) return;

    _checkTimer = Timer(_checkDebounce, () {
      if (mounted) _check();
    });
  }

  Future<void> _check() async {
    if (!_status.isValid || _isUnchanged) return;

    // ⚠️ 앞 요청이 안 끝났다. 그냥 돌아가면 **이 이름은 영영 안 물어본다** —
    // 타이머는 소진됐고 다시 걸어줄 사람이 없어 화면이 "확인할게요"에 멈춘다.
    if (_checking) {
      _checkTimer?.cancel();
      _checkTimer = Timer(_checkDebounce, () {
        if (mounted) _check();
      });
      return;
    }

    final nickname = _nickname.text.trim();
    setState(() {
      _checking = true;
      _checkFailed = false;
    });

    // 못 물었으면 `null`이 온다. 사유는 가르지 않는다 — 사용자가 할 일은
    // 다시 쳐보는 것 하나다.
    final available = await ref
        .read(profileRepositoryProvider)
        .isNicknameAvailable(nickname);

    if (!mounted) return;
    // 기다리는 사이에 이름을 고쳤다면 이 답은 **다른 이름의 답**이다. 버린다.
    if (_nickname.text.trim() != nickname) {
      setState(() => _checking = false);
      return;
    }

    setState(() {
      _checking = false;
      _checkedNickname = nickname;
      _checkedAvailable = available;
      _checkFailed = available == null;
    });
    _report();
  }

  // ── 화면 ──────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final colors = context.appColorsV2;
    final (helper, tone) = _helper();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppInputV2(
          controller: _nickname,
          hint: AppStrings.profileNicknameHint,
          helper: helper,
          counter: '$_length/${NicknameRule.max}',
          tone: tone,
          textInputAction: TextInputAction.done,
          inputFormatters: [LengthLimitingTextInputFormatter(NicknameRule.max)],
          onChanged: (_) => _onChanged(),
        ),

        // 입력과 무관한 실패다. helper 자리에 두면 **고칠 곳이 입력칸인
        // 것처럼** 읽힌다.
        if (widget.submitFailure != null &&
            widget.submitFailure != NicknameChangeFailure.taken) ...[
          const SizedBox(height: AppSpacing.space2),
          Text(
            _messageOf(widget.submitFailure!),
            style: AppTypographyV2.body15.copyWith(color: colors.error),
          ),
        ],
      ],
    );
  }

  /// helper 한 줄을 고른다.
  ///
  /// **순서가 규칙이다.** 뒤로 갈수록 일반적인 말이라, 앞의 구체적인 사정이
  /// 있으면 그것이 이긴다.
  (String, AppInputToneV2) _helper() {
    if (widget.submitFailure == NicknameChangeFailure.taken ||
        (_hasFreshAnswer && _checkedAvailable == false)) {
      return (AppStrings.profileNicknameTaken, AppInputToneV2.error);
    }
    if (_checking) {
      return (AppStrings.profileNicknameChecking, AppInputToneV2.neutral);
    }
    if (_checkFailed) {
      return (AppStrings.profileNicknameCheckFailed, AppInputToneV2.error);
    }
    // 형식은 맞지만 지금 쓰는 이름 그대로다. 오류가 아니라 **할 일이 없는
    // 상태**라 중립으로 말한다.
    if (_isUnchanged && _status.isValid) {
      return (AppStrings.profileNicknameUnchanged, AppInputToneV2.neutral);
    }
    // ⚠️ 형식을 통과했어도 **서버가 답하기 전까지는** 쓸 수 있다고 말하지
    // 않는다. 곧 "이미 있다"로 뒤집힐 수 있는 말이다.
    if (_status.isValid && !_hasFreshAnswer) {
      return (AppStrings.profileNicknameCheckPending, AppInputToneV2.neutral);
    }
    return switch (_status) {
      NicknameStatus.empty => (
        AppStrings.profileNicknameGuide,
        AppInputToneV2.neutral,
      ),
      NicknameStatus.tooShort => (
        AppStrings.profileNicknameTooShort,
        AppInputToneV2.error,
      ),
      NicknameStatus.tooLong => (
        AppStrings.profileNicknameTooLong,
        AppInputToneV2.error,
      ),
      NicknameStatus.invalidChars => (
        AppStrings.profileNicknameInvalidChars,
        AppInputToneV2.error,
      ),
      NicknameStatus.valid => (
        AppStrings.profileNicknameOk,
        AppInputToneV2.success,
      ),
    };
  }

  /// 실패 이유를 화면 문구로 옮긴다. [NicknameChangeFailure.taken]은 여기
  /// 오지 않는다 — helper가 맡는다.
  static String _messageOf(NicknameChangeFailure failure) => switch (failure) {
    NicknameChangeFailure.notOnboarded =>
      AppStrings.profileNicknameNotOnboarded,
    NicknameChangeFailure.sessionExpired => AppStrings.profileSubmitExpired,
    _ => AppStrings.profileNicknameChangeFailed,
  };
}
