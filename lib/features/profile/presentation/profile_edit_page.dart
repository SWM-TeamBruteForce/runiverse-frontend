import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:runiverse/core/strings/app_strings.dart';
import 'package:runiverse/core/theme/v2/app_colors.dart';
import 'package:runiverse/core/theme/v2/app_sizes.dart';
import 'package:runiverse/core/theme/v2/app_spacing.dart';
import 'package:runiverse/core/theme/v2/app_typography.dart';
import 'package:runiverse/core/widgets/v2/app_icon.dart';
import 'package:runiverse/core/widgets/v2/app_input.dart';
import 'package:runiverse/features/profile/domain/pending_photo.dart';
import 'package:runiverse/features/profile/domain/profile_edit_failure.dart';
import 'package:runiverse/features/profile/domain/nickname_change_failure.dart';
import 'package:runiverse/features/profile/domain/profile_image_failure.dart';
import 'package:runiverse/features/profile/presentation/nickname_field.dart';
import 'package:runiverse/features/profile/presentation/background_image_provider.dart';
import 'package:runiverse/features/profile/presentation/background_picker.dart';
import 'package:runiverse/features/profile/presentation/profile_avatar.dart';
import 'package:runiverse/features/profile/presentation/profile_header.dart';
import 'package:runiverse/features/profile/presentation/profile_image_provider.dart';
import 'package:runiverse/features/profile/presentation/profile_provider.dart';

/// 프로필 편집 (S22.1).
///
/// ## 저장이 둘로 갈린다
///
/// | 무엇 | 언제 저장되나 |
/// |---|---|
/// | 닉네임 | 시트에서 **즉시** (52번 — 중복확인·409) |
/// | 사진 · 소개글 · 생년월일 · 키 · 몸무게 | **저장 버튼 하나로** |
///
/// 닉네임만 즉시인 것은 **중복 검사가 붙어 누르는 자리에서 답이 나야**
/// 하기 때문이다. 시트에서 "이미 쓰는 이름"을 듣고 다른 것을 넣는 흐름이라,
/// 저장까지 미루면 그 답을 어디서 들을지가 없어진다.
///
/// ## ⚠️ 사진도 예전에는 즉시였다
///
/// 고르는 순간 3단계 업로드가 끝나 버려서, **저장 버튼은 꺼진 채인데 이미
/// 저장된 뒤**였다. 버튼이 꺼져 있으면 저장할 것이 없다는 뜻으로 읽히는데
/// 실제로는 반대였고, 그냥 나가도 반영돼 있어 되돌릴 방법이 없었다.
///
/// 이제 고른 것을 [_photo]로 들고 있다가 저장할 때 보낸다.
///
/// ## ⚠️ 신체 정보는 서버에서 읽은 뒤에 만질 수 있다
///
/// 전에는 **기기에 남은 값으로만** 선택기를 열었다. 다른 기기에서 로그인한
/// 사람은 그 값이 없어 172cm·63kg으로 열렸고, **키만 고쳐 저장해도 몸무게가
/// 63kg으로 덮였다** — 시트가 두 값을 함께 돌려주기 때문이다.
///
/// 이제 들어올 때 `GET /users/me/profile`(51번)로 서버 값을 받는다. 못 받았으면
/// 세 칸을 잠근다 — 모르는 값 위에 기본값을 쓰는 것보다 못 고치는 편이 낫다.
///
/// | 51번 | 세 칸 |
/// |---|---|
/// | 읽는 중 | 기기에 남은 값으로 보여주고 **잠근다** |
/// | 읽었다 | 서버 값으로 채우고 연다 (`null`이면 온보딩 전이라 빈 칸으로 연다) |
/// | 실패 | 잠그고 이유를 적는다 |
///
/// ## 성별과 평균 페이스는 없다
///
/// 성별은 기능정의서(`SETTING-PERSONAL-001`)가 **설정 UI 미노출**로 정했고,
/// 평균 페이스는 서버가 러닝 기록으로 갱신한다. 둘 다 요청에 싣지 않는다.
class ProfileEditPage extends ConsumerStatefulWidget {
  const ProfileEditPage({super.key});

  @override
  ConsumerState<ProfileEditPage> createState() => _ProfileEditPageState();
}

class _ProfileEditPageState extends ConsumerState<ProfileEditPage> {
  late final TextEditingController _introduction;

  /// 화면에 들어올 때의 소개글. **바뀐 게 있는지**를 이것과 비교해 판단한다.
  late final String _initialIntroduction;

  /// 보낼 수 있는 새 닉네임. `null`이면 안 바꿨거나 **아직 못 보낸다**(형식이
  /// 틀렸거나 중복확인이 안 끝났거나 겹친다). 화면 입장에서는 둘 다 *닉네임은
  /// 보내지 않는다*라서 가르지 않는다 — [NicknameField.onReady] 참조.
  String? _nickname;

  /// 저장하다 닉네임이 겹쳤다. 묻고 누르는 사이에 남이 가져갈 수 있다.
  NicknameChangeFailure? _nicknameFailure;

  /// 고르거나 지우기로 했지만 **아직 안 보낸** 사진. `null`이면 안 건드렸다.
  PendingPhoto? _photo;

  /// 아직 안 보낸 배경. 사진과 **같은 규칙**으로 저장 버튼을 기다린다.
  PendingPhoto? _background;

  bool _saving = false;
  ProfileEditFailure? _failure;

  @override
  void initState() {
    super.initState();
    _initialIntroduction =
        ref.read(profileSummaryControllerProvider).summary?.introduction ?? '';
    _introduction = TextEditingController(text: _initialIntroduction);
  }

  @override
  void dispose() {
    _introduction.dispose();
    super.dispose();
  }

  // ── 판정 ──────────────────────────────────────────────────

  /// 저장 버튼이 다루는 값 중 **하나라도 바뀌었나.**
  ///
  /// ⚠️ **닉네임도 여기 든다**(2026-10-22). 전에는 시트에서 즉시 저장돼
  /// 저장 버튼이 할 일이 없었다.
  bool get _dirty =>
      _photo != null ||
      _background != null ||
      _nickname != null ||
      _dirtyProfile;

  /// `PATCH /users/me/profile` 이 다루는 값 중 하나라도 바뀌었나.
  ///
  /// **사진도 닉네임도 세지 않는다.** 둘 다 제 갈 길이 따로 있어서, 그것만
  /// 바꿨을 때 이 `PATCH` 까지 보내면 **전부 `null` 인 요청**이 된다.
  ///
  /// ⚠️ 신체 정보는 설정으로 갔다. 여기 남은 값은 소개글 하나다.
  bool get _dirtyProfile => _introduction.text.trim() != _initialIntroduction;

  bool get _introductionTooLong => _introduction.text.trim().length > 100;

  bool get _canSave => _dirty && !_saving && !_introductionTooLong;

  // ── 저장·이탈 ─────────────────────────────────────────────

  Future<void> _save() async {
    if (!_canSave) return;

    setState(() {
      _saving = true;
      _failure = null;
    });

    // ⚠️ **사진을 먼저 보내고, 실패하면 거기서 멈춘다.**
    //
    // 반만 저장되면 화면이 무엇을 들고 있는지 알 수 없다. 멈춰서 화면에
    // 남겨 두면 다시 누르는 것으로 둘 다 간다.
    if (!await _savePhoto()) return;

    // ⚠️ **배경도 같은 규칙으로 멈춘다.** 사진은 갔는데 배경이 실패한 채로
    // 프로필 값까지 보내면, 화면이 무엇을 들고 있는지 알 수 없다.
    if (!await _saveBackground()) return;

    // ⚠️ **닉네임도 같은 규칙으로 멈춘다.** 묻고 누르는 사이에 남이 가져갈
    // 수 있어서, 여기서 다시 겹칠 수 있다.
    if (!await _saveNickname()) return;

    // 사진·배경·닉네임만 바꿨다. 보낼 프로필 값이 없다.
    if (!_dirtyProfile) {
      if (mounted) context.pop();
      return;
    }

    final failure = await ref
        .read(profileSummaryControllerProvider.notifier)
        .saveProfile(introduction: _introduction.text.trim());

    if (!mounted) return;
    if (failure == null) {
      context.pop();
      return;
    }

    setState(() {
      _saving = false;
      _failure = failure;
    });
  }

  /// 들고 있던 사진 변경을 보낸다. **보낼 것이 없으면 그냥 참이다.**
  ///
  /// 실패하면 거짓을 돌려주고, 그 전에 스낵바로 이유를 알린다. 사진 실패는
  /// 화면 아래 문구([_failure])와 섞지 않는다 — 그쪽은 `PATCH` 의 이유라
  /// 같은 자리에 쓰면 어느 쪽이 실패한 것인지 알 수 없다.
  Future<bool> _savePhoto() async {
    final photo = _photo;
    if (photo == null) return true;

    final failure = await ref
        .read(profileImageControllerProvider.notifier)
        .apply(photo);

    if (!mounted) return false;
    if (failure == null) {
      // 보냈다. 다시 누를 때 또 올리지 않는다.
      //
      // 새 주소를 다시 받는 것은 여기서 하지 않는다 — **편집 화면을 연
      // `ProfileHeader` 가 돌아온 자리에서 이미 부른다.**
      setState(() => _photo = null);
      return true;
    }

    setState(() => _saving = false);
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(_photoMessageOf(failure))));
    return false;
  }

  /// 들고 있던 배경을 보낸다. 보낼 것이 없으면 그냥 참이다.
  ///
  /// ⚠️ **실패하면 멈춘다**([_savePhoto]와 같다). 화면에 남겨 두면 다시 누르는
  /// 것으로 나머지가 함께 간다.
  Future<bool> _saveBackground() async {
    final background = _background;
    if (background == null) return true;

    final failure = await ref
        .read(backgroundImageControllerProvider.notifier)
        .apply(background);

    if (!mounted) return false;
    if (failure == null) {
      // 보냈다. 다시 누를 때 또 올리지 않는다.
      setState(() => _background = null);
      return true;
    }

    setState(() => _saving = false);
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(_photoMessageOf(failure))));
    return false;
  }

  /// 들고 있던 닉네임을 보낸다(52번). 보낼 것이 없으면 그냥 참이다.
  ///
  /// ⚠️ **겹친 것만 칸 자리에 돌려준다.** 다른 실패(세션 만료·네트워크)도
  /// 같은 칸 아래에 서지만, 겹침은 helper 줄이 맡고 나머지는 그 아래 문구가
  /// 맡는다 — [NicknameField] 참조.
  Future<bool> _saveNickname() async {
    final nickname = _nickname;
    if (nickname == null) return true;

    final failure = await ref
        .read(profileSummaryControllerProvider.notifier)
        .changeNickname(nickname);

    if (!mounted) return false;
    if (failure == null) {
      // 보냈다. 다시 누를 때 또 보내지 않는다.
      setState(() => _nickname = null);
      return true;
    }

    setState(() {
      _saving = false;
      _nicknameFailure = failure;
    });
    return false;
  }

  /// 저장하지 않고 나가려 한다. **바꾼 게 없으면 묻지 않는다.**
  Future<bool> _confirmLeave() async {
    if (!_dirty) return true;

    final leave = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: context.appColorsV2.bgElevated,
        title: Text(
          AppStrings.profileEditDiscardTitle,
          style: AppTypographyV2.heading06.copyWith(
            color: context.appColorsV2.textPrimary,
          ),
        ),
        content: Text(
          AppStrings.profileEditDiscardBody,
          style: AppTypographyV2.body07.copyWith(
            color: context.appColorsV2.textSecondary,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(AppStrings.profileEditDiscardStay),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(
              AppStrings.profileEditDiscardLeave,
              style: TextStyle(color: context.appColorsV2.error),
            ),
          ),
        ],
      ),
    );
    return leave ?? false;
  }

  // ── 화면 ──────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final colors = context.appColorsV2;
    final summary = ref.watch(profileSummaryControllerProvider).summary;

    return PopScope(
      // 바꾼 게 있으면 먼저 묻는다. 뒤로 밀기(제스처)도 여기로 들어온다.
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (await _confirmLeave() && context.mounted) context.pop();
      },
      child: Scaffold(
        // ⚠️ **앱 테마가 아직 옛 세대라 바탕을 직접 깐다.** 안 깔면 토큰은
        // 전부 새것인데 바탕만 `#0b0e14`로 남는다 — 채널당 차이가 10 안쪽이라
        // 눈으로는 잘 안 보인다(`v2_screen_background_test`).
        backgroundColor: colors.bgBase,
        body: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _TopBar(
                onBack: () async {
                  if (await _confirmLeave() && context.mounted) context.pop();
                },
                onSave: _canSave ? _save : null,
                saving: _saving,
              ),

              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // ⚠️ **프로필 화면과 같은 배치다** — 커버가 맨 위에서 폭을
                      // 다 쓰고 아바타가 아래변에 걸친다. 바꾸는 자리와 보이는
                      // 자리가 닮아야 무엇을 바꾸는지 안다.
                      //
                      // ⚠️ **좌우 여백 밖에 둔다.** 스크롤 전체에 패딩을 걸면
                      // 커버만 안쪽으로 들어와 카드처럼 보인다. 그래서 패딩을
                      // 아래 [_Form]으로 내렸다.
                      //
                      // ⚠️ **사진과 같은 규칙이다** — 고른 것은 화면에만 남고
                      // 저장 버튼이 보낸다. 배경만 즉시 올리면 한 화면에 규칙이
                      // 둘이 되고, 사용자는 무엇이 이미 갔는지 알 수 없다.
                      BackgroundPicker(
                        pending: _background,
                        onPending: (photo) =>
                            setState(() => _background = photo),
                        // 사진과 같은 문구로 말해 준다 — 서버에 가기 전에
                        // 걸린 것이라 사용자가 할 일은 다시 고르는 것뿐이다.
                        onFailure: (failure) =>
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text(_photoMessageOf(failure))),
                            ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(
                          AppSpacing.space5,
                          0,
                          AppSpacing.space5,
                          AppSpacing.space8,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            // 고른 것은 화면에만 남는다. 보내는 것은 저장 버튼이다.
                            //
                            // ⚠️ **커버에 걸친다**(`ProfileHeader.coverOverlap`).
                            // `Transform`이라 **자리는 그대로 차지한다** — 아래
                            // 닉네임이 따라 올라오지 않는다.
                            Align(
                              alignment: Alignment.centerLeft,
                              child: Transform.translate(
                                offset: const Offset(
                                  0,
                                  -ProfileHeader.coverOverlap,
                                ),
                                // ⚠️ **글자를 달지 않는다**(2026-10-22 요청).
                                // 커버 버튼과 같은 규칙이다 — 아이콘만 두고,
                                // 낭독기가 읽을 것은 아바타의 `Semantics`
                                // 라벨(`프로필 사진 바꾸기`)뿐이다.
                                child: ProfileAvatar(
                                  url: summary?.profileImageUrl,
                                  editable: true,
                                  pending: _photo,
                                  onPending: (photo) =>
                                      setState(() => _photo = photo),
                                ),
                              ),
                            ),
                            // ⚠️ **여백을 더하지 않는다.** 위 `Transform`이
                            // 자리를 그대로 차지해 아바타 아래에 이미
                            // `coverOverlap`(43)만큼 빈 자리가 남는다. 여기에
                            // 여백을 또 주면 다음 구획과의 간격이 다른 곳의
                            // 세 배가 된다.

                            // ⚠️ **그 자리에서 고친다**(2026-10-22 요청).
                            // 전에는 시트였고 거기서 즉시 저장됐다. 지금은 아래
                            // 소개글과 같은 규칙이다 — **저장 버튼이 보낸다.**
                            // 중복확인만 치는 동안 계속 돈다.
                            _Label(AppStrings.profileNicknameLabel),
                            const SizedBox(height: AppSpacing.space2),
                            NicknameField(
                              current: summary?.nickname,
                              submitFailure: _nicknameFailure,
                              // ⚠️ **빌드 중에 들어올 수 있다.** 칸이 처음
                              // 그려질 때도 불리므로 그 프레임에서 `setState`를
                              // 하면 Flutter가 막는다. 값이 실제로 달라질
                              // 때만 고친다.
                              onReady: (value) {
                                if (value == _nickname) return;
                                setState(() {
                                  _nickname = value;
                                  _nicknameFailure = null;
                                });
                              },
                            ),
                            const SizedBox(height: AppSpacing.space6),

                            _Label(AppStrings.profileIntroductionLabel),
                            const SizedBox(height: AppSpacing.space2),
                            AppInputV2(
                              // ⚠️ **테스트가 이 입력을 찾는 유일한 손잡이다.**
                              // 부품이 `TextField` 인지 무엇인지에 기대면 디자인을
                              // 바꿀 때 테스트가 통째로 깨진다. 디자인을 바꿔도
                              // **이 키는 이어받는다.**
                              key: const ValueKey('profile-introduction'),
                              controller: _introduction,
                              hint: AppStrings.profileIntroductionHint,
                              helper: _introductionTooLong
                                  ? AppStrings.profileIntroductionTooLong
                                  : null,
                              tone: _introductionTooLong
                                  ? AppInputToneV2.error
                                  : AppInputToneV2.neutral,
                              counter:
                                  '${_introduction.text.trim().length}/100',
                              inputFormatters: [
                                LengthLimitingTextInputFormatter(100),
                              ],
                              onChanged: (_) => setState(() {}),
                            ),
                            // ⚠️ **신체 정보는 설정으로 갔다**(2026-10-22 요청).
                            // 생년월일·키·몸무게는 자주 고치는 값이 아니고,
                            // 여기 있으면 홈과 닮은 위쪽이 긴 폼에 묻힌다.
                            //
                            if (_failure != null) ...[
                              const SizedBox(height: AppSpacing.space4),
                              Text(
                                _messageOf(_failure!),
                                style: AppTypographyV2.body15.copyWith(
                                  color: colors.error,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 사진 실패 이유를 화면 문구로 옮긴다.
  ///
  /// **앞의 셋만 갈라 말한다.** 나머지는 사용자가 할 수 있는 일이
  /// "다시 해보기" 하나라서, 어디서 막혔는지 말해도 쓸 데가 없다.
  static String _photoMessageOf(ProfileImageFailure failure) =>
      switch (failure) {
        ProfileImageFailure.unsupportedFormat =>
          AppStrings.profilePhotoUnsupported,
        ProfileImageFailure.tooLarge => AppStrings.profilePhotoTooLarge,
        ProfileImageFailure.sessionExpired => AppStrings.profileSubmitExpired,
        _ => AppStrings.profilePhotoFailed,
      };

  static String _messageOf(ProfileEditFailure failure) => switch (failure) {
    ProfileEditFailure.notOnboarded => AppStrings.profileNicknameNotOnboarded,
    ProfileEditFailure.sessionExpired => AppStrings.profileSubmitExpired,
    _ => AppStrings.profileSubmitFailed,
  };
}

/// `‹  프로필 편집          저장`
class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.onBack,
    required this.onSave,
    required this.saving,
  });

  final VoidCallback onBack;

  /// `null`이면 잠긴다 — **바꾼 게 없을 때**가 그렇다.
  final VoidCallback? onSave;

  final bool saving;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColorsV2;

    return SizedBox(
      height: AppSizes.touchDefault + AppSpacing.space2,
      child: Row(
        children: [
          IconButton(
            onPressed: onBack,
            tooltip: AppStrings.authBack,
            constraints: const BoxConstraints(
              minWidth: AppSizes.touchDefault,
              minHeight: AppSizes.touchDefault,
            ),
            icon: AppIcon(
              AppIcons.left,
              size: AppSpacing.space6,
              color: colors.textSecondary,
            ),
          ),
          Expanded(
            child: Text(
              AppStrings.profileEditTitle,
              textAlign: TextAlign.center,
              style: AppTypographyV2.body07.copyWith(color: colors.textPrimary),
            ),
          ),
          // 뒤로 아이콘과 **같은 폭**을 잡아 제목이 가운데에 선다.
          SizedBox(
            width: AppSizes.touchDefault + AppSpacing.space4,
            child: saving
                ? const Center(
                    child: SizedBox(
                      width: AppSpacing.space4,
                      height: AppSpacing.space4,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                : TextButton(
                    onPressed: onSave,
                    child: Text(
                      AppStrings.profileEditSave,
                      style: AppTypographyV2.body07.copyWith(
                        color: onSave == null
                            ? colors.textDisabled
                            : colors.primary,
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _Label extends StatelessWidget {
  const _Label(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: AppSpacing.space1),
    child: Text(
      text,
      style: AppTypographyV2.body15.copyWith(
        color: context.appColorsV2.textSecondary,
      ),
    ),
  );
}
