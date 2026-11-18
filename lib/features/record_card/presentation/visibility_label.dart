import 'package:runiverse/core/strings/app_strings.dart';
import 'package:runiverse/features/record_card/domain/record_card_visibility.dart';

/// 공개범위를 화면에 쓸 말로.
///
/// ⚠️ **`AppStrings`에 넣지 않는다.** 거기 두려면 `core/`가 feature의 enum을
/// import해야 해서 의존이 거꾸로 선다. 문구 자체는 `AppStrings`에 있고 고르는
/// 일만 여기서 한다 — `activity_label.dart`와 같은 꼴이다.
String recordCardVisibilityLabel(RecordCardVisibility visibility) =>
    switch (visibility) {
      RecordCardVisibility.public => AppStrings.recordCardVisibilityPublic,
      RecordCardVisibility.friends => AppStrings.recordCardVisibilityFriends,
      RecordCardVisibility.private => AppStrings.recordCardVisibilityPrivate,
    };

/// 그 범위가 **누구에게 보이는지** 한 줄로.
String recordCardVisibilityBody(
  RecordCardVisibility visibility,
) => switch (visibility) {
  RecordCardVisibility.public => AppStrings.recordCardVisibilityPublicBody,
  RecordCardVisibility.friends => AppStrings.recordCardVisibilityFriendsBody,
  RecordCardVisibility.private => AppStrings.recordCardVisibilityPrivateBody,
};

/// 이 범위로 올리면 **경로가 남에게 보이나.**
///
/// ⚠️ 경고를 늘 띄우면 나만 보기로 바꾼 사람에게 거짓말이 되고, 아예 안
/// 띄우면 집이나 직장 근처가 드러나는 것을 모르고 공개한다(설계 6-4).
bool recordCardVisibilityShowsRoute(RecordCardVisibility visibility) =>
    visibility != RecordCardVisibility.private;
