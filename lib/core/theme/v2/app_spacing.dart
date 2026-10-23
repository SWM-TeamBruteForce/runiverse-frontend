/// 새 디자인의 간격 — **기존 값을 그대로 쓴다.**
///
/// 시안에는 간격 정의 시트가 없다. 파운데이션 프레임은 `Typography`(`160:4574`)
/// 와 `Color`(`162:4905`) 둘뿐이다. 값을 지어내지 않고 기존 것을 가리킨다.
///
/// 그런데도 이 파일이 있는 이유는 하나다. **옮긴 화면이 `v2`만 import 하게**
/// 하려는 것이다. 이게 없으면 화면이 `v2/app_colors`와 `tokens/app_spacing`을
/// 함께 읽게 되고, `test/theme_generation_test.dart`가 그것을 막는다.
///
/// 시안이 다른 값을 요구하는 화면이 나오면 그때 여기에 실제 값을 넣는다.
/// 그 시점에 **화면 코드는 한 줄도 안 바뀐다.**
library;

export 'package:runiverse/core/theme/tokens/app_spacing.dart';
