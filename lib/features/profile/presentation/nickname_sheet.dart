import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:runiverse/core/strings/app_strings.dart';
import 'package:runiverse/core/theme/extensions/app_colors.dart';
import 'package:runiverse/core/theme/tokens/app_radius.dart';
import 'package:runiverse/core/theme/tokens/app_spacing.dart';
import 'package:runiverse/core/theme/tokens/app_typography.dart';
import 'package:runiverse/core/widgets/app_button.dart';
import 'package:runiverse/core/widgets/app_input.dart';
import 'package:runiverse/features/onboarding/domain/nickname_rule.dart';
import 'package:runiverse/features/profile/domain/nickname_change_failure.dart';
import 'package:runiverse/features/profile/presentation/profile_provider.dart';

/// 닉네임 변경 시트를 띄운다. **바꿨으면 `true`.** 취소하면 `null`.
///
/// ## 왜 시트인가
///
/// 다이얼로그는 키보드가 올라오면 화면 가운데에서 밀려 자리를 잃는다.
/// 입력이 하나뿐인 화면은 아래에서 올라오는 편이 맞고, 프로필 사진 시트와
/// 같은 뼈대를 쓰면 **같은 자리에서 하는 같은 종류의 일**로 읽힌다.
///
/// [current]는 지금 쓰는 이름이다. 미리 채워 두면 고칠 사람이 지우고 다시
/// 치지 않아도 되고, **바뀐 게 없을 때 묻지 않기 위해서도** 필요하다.
Future<bool?> showNicknameSheet(BuildContext context, {String? current}) {
  return showModalBottomSheet<bool>(
    context: context,
    backgroundColor: Colors.transparent,
    barrierColor: context.appColors.bgScrim,
    // ⚠️ 없으면 키보드가 시트를 덮는다. 입력이 있는 시트는 항상 켠다.
    isScrollControlled: true,
    builder: (context) => _NicknameSheet(current: current),
  );
}

class _NicknameSheet extends ConsumerStatefulWidget {
  const _NicknameSheet({this.current});

  final String? current;

  @override
  ConsumerState<_NicknameSheet> createState() => _NicknameSheetState();
}

/// 온보딩(`profile_setup_page.dart`)의 검증 흐름을 **다시 쓰지 않고 여기에
/// 다시 적었다.**
///
/// 그쪽 로직은 단계 넘김(`_advance`)과 흔들림 애니메이션에 얽혀 있어 그대로
/// 뽑히지 않는다. 뽑으려면 지금 잘 도는 온보딩 화면을 크게 건드려야 한다.
/// 대신 **[NicknameRule]을 함께 본다** — 두 화면이 어긋날 수 있는 지점은
/// 길이·문자 규칙 하나뿐이고, 그것은 공유하고 있다.
class _NicknameSheetState extends ConsumerState<_NicknameSheet> {
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

  /// 바꾸는 중. 버튼이 두 번 눌리는 것을 막는다.
  bool _submitting = false;

  /// 바꾸다 실패한 이유.
  NicknameChangeFailure? _submitFailure;

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

  bool get _canSubmit =>
      _status.isValid &&
      !_isUnchanged &&
      !_checking &&
      !_submitting &&
      // 겹친다는 답을 이미 들었으면 잠근다 — 눌러봐야 같은 답을 받으러
      // 한 번 더 나갈 뿐이다.
      !(_hasFreshAnswer && _checkedAvailable == false);

  // ── 중복확인 ──────────────────────────────────────────────

  /// 이름이 바뀌었다. **서버가 한 말은 전부 낡은 말이 된다.**
  void _onChanged() {
    _checkTimer?.cancel();
    setState(() {
      _checkedNickname = null;
      _checkedAvailable = null;
      _checkFailed = false;
      _submitFailure = null;
    });

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
    // 다시 눌러보는 것 하나다.
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
  }

  // ── 변경 ──────────────────────────────────────────────────

  Future<void> _submit() async {
    if (!_canSubmit) return;

    // 디바운스를 기다리는 중이었다면 지금 묻는다 — 기다릴 이유가 없다.
    if (!_hasFreshAnswer) {
      _checkTimer?.cancel();
      await _check();
      if (!mounted) return;
    }
    if (!(_hasFreshAnswer && _checkedAvailable == true)) return;

    setState(() {
      _submitting = true;
      _submitFailure = null;
    });

    final failure = await ref
        .read(profileSummaryControllerProvider.notifier)
        .changeNickname(_nickname.text.trim());

    if (!mounted) return;
    if (failure == null) {
      Navigator.of(context).pop(true);
      return;
    }

    setState(() {
      _submitting = false;
      _submitFailure = failure;
    });

    // 온보딩을 안 마친 사람은 이 시트에서 할 수 있는 일이 없다. 닫는다.
    if (failure == NicknameChangeFailure.notOnboarded) {
      Navigator.of(context).pop();
    }
  }

  // ── 화면 ──────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final (helper, tone) = _helper();

    return SafeArea(
      top: false,
      child: Padding(
        // 키보드가 올라온 만큼 시트를 밀어 올린다.
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Container(
          decoration: BoxDecoration(
            color: colors.bgElevated,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.space5,
            AppSpacing.space3,
            AppSpacing.space5,
            AppSpacing.space5,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: colors.borderStrong,
                    borderRadius: AppRadius.full,
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.space4),

              Text(
                AppStrings.profileNicknameChangeTitle,
                style: AppTypography.h3.copyWith(color: colors.textPrimary),
              ),
              const SizedBox(height: AppSpacing.space4),

              AppInput(
                controller: _nickname,
                autofocus: true,
                hint: AppStrings.profileNicknameHint,
                helper: helper,
                counter: '$_length/${NicknameRule.max}',
                tone: tone,
                textInputAction: TextInputAction.done,
                inputFormatters: [
                  LengthLimitingTextInputFormatter(NicknameRule.max),
                ],
                onChanged: (_) => _onChanged(),
                onSubmitted: (_) => _submit(),
              ),

              // 입력과 무관한 실패다. helper 자리에 두면 **고칠 곳이
              // 입력칸인 것처럼** 읽힌다.
              if (_submitFailure != null &&
                  _submitFailure != NicknameChangeFailure.taken) ...[
                const SizedBox(height: AppSpacing.space2),
                Text(
                  _messageOf(_submitFailure!),
                  style: AppTypography.caption.copyWith(color: colors.error),
                ),
              ],
              const SizedBox(height: AppSpacing.space4),

              AppButton(
                label: AppStrings.profileNicknameChangeSubmit,
                onPressed: _canSubmit ? _submit : null,
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// helper 한 줄을 고른다.
  ///
  /// **순서가 규칙이다.** 뒤로 갈수록 일반적인 말이라, 앞의 구체적인 사정이
  /// 있으면 그것이 이긴다.
  (String, AppInputTone) _helper() {
    if (_submitFailure == NicknameChangeFailure.taken ||
        (_hasFreshAnswer && _checkedAvailable == false)) {
      return (AppStrings.profileNicknameTaken, AppInputTone.error);
    }
    if (_checking) {
      return (AppStrings.profileNicknameChecking, AppInputTone.neutral);
    }
    if (_checkFailed) {
      return (AppStrings.profileNicknameCheckFailed, AppInputTone.error);
    }
    // 형식은 맞지만 지금 쓰는 이름 그대로다. 오류가 아니라 **할 일이 없는
    // 상태**라 중립으로 말한다.
    if (_isUnchanged && _status.isValid) {
      return (AppStrings.profileNicknameUnchanged, AppInputTone.neutral);
    }
    // ⚠️ 형식을 통과했어도 **서버가 답하기 전까지는** 쓸 수 있다고 말하지
    // 않는다. 곧 "이미 있다"로 뒤집힐 수 있는 말이다.
    if (_status.isValid && !_hasFreshAnswer) {
      return (AppStrings.profileNicknameCheckPending, AppInputTone.neutral);
    }
    return switch (_status) {
      NicknameStatus.empty => (
        AppStrings.profileNicknameGuide,
        AppInputTone.neutral,
      ),
      NicknameStatus.tooShort => (
        AppStrings.profileNicknameTooShort,
        AppInputTone.error,
      ),
      NicknameStatus.tooLong => (
        AppStrings.profileNicknameTooLong,
        AppInputTone.error,
      ),
      NicknameStatus.invalidChars => (
        AppStrings.profileNicknameInvalidChars,
        AppInputTone.error,
      ),
      NicknameStatus.valid => (
        AppStrings.profileNicknameOk,
        AppInputTone.success,
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
