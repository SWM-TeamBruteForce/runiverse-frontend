import 'package:runiverse/core/strings/app_strings.dart';
import 'package:runiverse/features/record_card/domain/record_card_activity.dart';

/// 활동 유형을 화면에 쓸 말로.
///
/// ⚠️ **`AppStrings`에 넣지 않는다.** 거기 두려면 `core/`가 feature의 enum을
/// import해야 해서 의존이 거꾸로 선다. 문구 자체는 `AppStrings`에 있고 고르는
/// 일만 여기서 한다.
String recordCardActivityLabel(RecordCardActivity activity) =>
    switch (activity) {
      RecordCardActivity.daily => AppStrings.recordCardActivityDaily,
      RecordCardActivity.race => AppStrings.recordCardActivityRace,
      RecordCardActivity.travel => AppStrings.recordCardActivityTravel,
    };
