# UI 전면 교체 — 파운데이션과 파일럿 계획

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 새 디자인의 토큰(글꼴·색·타이포)을 `lib/core/theme/v2/` 에 세우고, 화면 하나를 그것으로 갈아끼워 절차가 통하는지 확인한다.

**Architecture:** 토큰을 먼저 다 세운다 — 화면 하나를 옮기려면 색·타이포·간격이 동시에 필요해서 쪼갤 수 없다. 간격·반경은 시안에 정의 시트가 없으므로 `v2` 가 기존 값을 그대로 재수출한다(화면이 다른 값을 요구하면 그때 바꾼다). 그 다음 화면 하나를 옮겨, 깨지는 테스트 수와 `widgets/v2` 필요량을 **재고 나서** 나머지 순서를 정한다.

**Tech Stack:** Flutter (fvm) · flutter_test · Figma MCP

**Spec:** `docs/specs/2026-09-25-ui-redesign-workspace-design.md`

**Figma:** 파일 `MpJxkA7fPj6MJs5uL07CVb` (`runiverse_final2`), 페이지 `0:1` `디자인시안 확인용`. 화면 시안은 전부 `149:791` 아래에 있다.

## Global Constraints

- 모든 flutter/dart 명령은 `.\.fvm\flutter_sdk\bin\flutter.bat` / `dart.bat` 으로 직접 부른다 — fvm 이 PATH 에 없다.
- 모든 커밋 시점에 `analyze` 경고 **0개**, `test` **전체 통과**(현재 914개). 빨간 것을 다음 PR로 넘기지 않는다.
- 커밋 메시지 `<이모지> <Type>: <설명>` — `📍 Feat` `🔨 Fix` `📝 Docs` `🎨 Style` `🤖 Refactor` `✅ Test` `🚚 Chore` `✂️ Remove` `🔧 Rename`. **AI 를 공동 작성자로 넣지 않는다.**
- 브랜치 `<type>/<domain>` kebab-case. PR base 는 `dev`. PR 하나에 파일 20개 / 500줄을 넘기면 사유를 본문에 적는다.
- 아이콘은 **Lucide 만**. `Icons.*` 금지.
- `Color(0x...)` 등 값 하드코딩은 `core/theme/` 안에서만.
- **한 화면은 한 세대의 토큰만 쓴다.** `test/theme_generation_test.dart` 가 강제한다. `lib/core/theme/` 안은 예외다.
- 러닝 수치에 `FontFeature.tabularFigures()`.
- 화면은 **다크·라이트 두 테마**를 함께 정의한다.
- **GPS 좌표·경로를 파티원에게 노출하지 않는다.** 파티원 비교에 **순위를 표시하지 않는다.**

### 이번 작업에서 사용자가 정한 것

- 시안에만 있는 화면 4개(친구 목록·친구초대·뱃지 획득·도감 상세)는 **화면만 껍데기로** 만든다. 데이터는 붙이지 않는다. → 이 계획 범위 밖, 다음 계획.
- 시안에 없는 우리 화면 6개(프로필 편집·기록 상세·설정·비밀번호 변경·**러닝 준비**·준비중)는 **새 토큰만 입혀 유지**한다.
- 하단 탭은 **시안대로 4개** — 홈 · 기록 · **기록카드** · 프로필. `대회일정` 탭이 빠진다.
- **"친구"라는 말을 시안대로 쓴다.** CLAUDE.md 의 금지 규칙은 수정안을 제안한다(Task 6).

⚠️ 뒤의 둘은 CLAUDE.md 를 바꾸는 결정이다. **이 계획에서 CLAUDE.md 를 직접 고치지 않는다** — 수정안만 PR 본문에 적는다.

---

### Task 1: SUIT 글꼴을 들인다

시안의 글꼴은 **SUIT** 다(`160:4574` 의 `글꼴` 절이 `SUIT 수트 スーツ` 를 64px 로 보여준다). 타이포 토큰이 글꼴 이름을 들고 있어야 하므로 먼저 한다.

⚠️ **SUIT 를 이 프로젝트에 넣을 수 있는지 모른다.** 확인이 이 작업의 절반이다. 못 쓰면 여기서 멈추고 디자이너·기획과 상의한다 — 추측으로 다른 글꼴을 고르지 않는다.

**Files:**
- Create: `assets/fonts/` (SUIT 파일)
- Modify: `pubspec.yaml`

**Interfaces:**
- Consumes: 없음
- Produces: 글꼴 패밀리 이름 `SUIT` — Task 2 의 `AppTypographyV2` 가 `fontFamily` 로 쓴다

- [ ] **Step 1: 라이선스와 배포 형식을 확인한다**

SUIT 배포처(<https://sunn.us/suit/>)와 저장소(<https://github.com/sun-typeface/SUIT>)에서 확인할 것 셋:

1. 라이선스가 **SIL OFL 1.1** 인가 — 앱에 임베드해 배포할 수 있는가
2. `.ttf` 또는 `.otf` **정적 파일**을 받을 수 있는가 (가변 폰트만 있으면 Flutter 쪽 처리가 달라진다)
3. 우리가 쓰는 굵기 다섯이 다 있는가 — **Regular(400) · Medium(500) · SemiBold(600) · Bold(700) · ExtraBold(800)**

⚠️ **셋 중 하나라도 아니면 멈추고 보고한다.** 특히 `ExtraBold` 는 `Heading 04` 하나만 쓰므로, 없으면 Bold 로 대체할지 묻는다.

- [ ] **Step 2: 폰트 파일을 받아 넣는다**

받은 파일을 `assets/fonts/` 에 넣는다. 파일명은 배포본 그대로 둔다(예: `SUIT-Regular.ttf`).

```powershell
New-Item -ItemType Directory -Force assets/fonts | Out-Null
Get-ChildItem assets/fonts
```

Expected: 굵기 다섯에 해당하는 파일 5개.

- [ ] **Step 3: `pubspec.yaml` 에 등록한다**

`flutter:` 절 안에 더한다. 기존 `assets:` 항목이 있으면 그 아래 나란히 둔다.

```yaml
  fonts:
    - family: SUIT
      fonts:
        - asset: assets/fonts/SUIT-Regular.ttf
          weight: 400
        - asset: assets/fonts/SUIT-Medium.ttf
          weight: 500
        - asset: assets/fonts/SUIT-SemiBold.ttf
          weight: 600
        - asset: assets/fonts/SUIT-Bold.ttf
          weight: 700
        - asset: assets/fonts/SUIT-ExtraBold.ttf
          weight: 800
```

- [ ] **Step 4: 글꼴이 실제로 실리는지 확인한다**

```powershell
.\.fvm\flutter_sdk\bin\flutter.bat pub get
.\.fvm\flutter_sdk\bin\flutter.bat analyze
.\.fvm\flutter_sdk\bin\flutter.bat test
```

Expected: analyze `No issues found!`, 914개 통과.

⚠️ 테스트만으로는 글꼴이 실렸는지 알 수 없다. 위젯 테스트는 Ahem 이라는 네모 글꼴로 그린다. **에뮬레이터에서 눈으로 본다** — Task 5 의 파일럿 화면에서 확인한다.

- [ ] **Step 5: 시크릿이 섞이지 않았는지 보고 커밋**

```bash
git status --short
git add pubspec.yaml assets/fonts
git commit -F - <<'EOF'
🚚 Chore: 새 디자인의 글꼴 SUIT 을 들인다

시안(`160:4574` 글꼴 절)이 지정한 글꼴이다. 타이포 토큰이 이름을
들고 있어야 해서 토큰보다 먼저 넣는다.

굵기 다섯을 등록한다 — Regular/Medium/SemiBold/Bold/ExtraBold.
ExtraBold 는 Heading 04 하나만 쓴다.
EOF
```

---

### Task 2: 색 토큰을 세운다

시안 `162:4905` `Color` 가 정의하는 것은 셋이다 — **중립 11단**, **브랜드 2색**, **러닝 색 10군 × 3톤**.

⚠️ **러닝 색 10군은 우리에게 이미 있다.** `lib/core/theme/tokens/run_palette.dart` 의 `RunHue` 가 같은 이름 10개를 들고 있다. **하지만 색값이 전혀 다르다** — 우리 `거리` 는 틸, 시안의 `거리` 는 파랑(`#227dff`)이다. 이름 하나도 다르다(우리 `동행` / 시안 `동맹`).

**Files:**
- Create: `lib/core/theme/v2/app_palette.dart`
- Create: `lib/core/theme/v2/run_palette.dart`
- Test: `test/v2_run_palette_test.dart`

**Interfaces:**
- Consumes: 없음
- Produces:
  - `AppPaletteV2.neutral50`…`neutral950`, `AppPaletteV2.brand`, `AppPaletteV2.brandDeep`
  - `RunPaletteV2.of(RunHue hue) -> List<Color>` — 얕은 것 → 깊은 것 3개. 기존 `RunPalette` 와 같은 모양이라 화면 코드가 그대로 산다

- [ ] **Step 1: 기존 팔레트의 계약을 확인한다**

```powershell
.\.fvm\flutter_sdk\bin\flutter.bat --version
Select-String -Path lib/core/theme/tokens/run_palette.dart -Pattern "static|enum|RunHue\." | Select-Object -First 30
```

⚠️ `RunHue` **enum 자체는 v2 에 복제하지 않는다.** `features/color/domain/` 이 그것을 쓰고 있고, enum 을 두 벌 만들면 도메인이 어느 쪽을 가리키는지 알 수 없게 된다. v2 는 **색값만** 새로 든다.

- [ ] **Step 2: 중립·브랜드 색을 쓴다**

`lib/core/theme/v2/app_palette.dart`:

```dart
import 'package:flutter/painting.dart';

/// 새 디자인의 원색 — 시안 `162:4905` `Color`.
///
/// ## 이건 시맨틱이 아니다
///
/// 여기 있는 것은 **이름 붙은 물감**이다. "배경은 무슨 색인가"는
/// [AppColorsV2] 가 테마별로 정한다. 화면은 이 파일을 직접 읽지 않는다.
///
/// ## 중립 11단은 시안의 Figma 변수와 1:1이다
///
/// 시안은 이 램프만 변수로 묶어 뒀다(`--primary-100-f5f5f5` 꼴). 나머지는
/// 전부 하드코딩 hex 라, 값이 바뀌면 시안을 다시 읽어 여기를 고쳐야 한다.
abstract final class AppPaletteV2 {
  static const neutral50 = Color(0xFFFAFAFA);
  static const neutral100 = Color(0xFFF5F5F5);
  static const neutral200 = Color(0xFFE6E6E6);
  static const neutral300 = Color(0xFFD6D6D6);
  static const neutral400 = Color(0xFFA5A5A5);
  static const neutral500 = Color(0xFF767676);
  static const neutral600 = Color(0xFF575757);
  static const neutral700 = Color(0xFF434343);
  static const neutral800 = Color(0xFF292929);
  static const neutral900 = Color(0xFF171717);
  static const neutral950 = Color(0xFF0A0A0A);

  /// 하단 탭의 켜진 아이콘, 주 버튼. 시안에서 이름 없는 군의 50.
  static const brand = Color(0xFF227DFF);

  /// 같은 군의 100. 어두운 배경 위 브랜드색으로 쓴다.
  static const brandDeep = Color(0xFF202B43);

  /// 본문 글자. 시안이 `--label/normal` 로 쓰는 값이다.
  static const label = Color(0xFF171719);
}
```

- [ ] **Step 3: 러닝 색 10군을 쓴다**

`lib/core/theme/v2/run_palette.dart`:

```dart
import 'package:flutter/painting.dart';
import 'package:runiverse/core/theme/tokens/run_palette.dart';

/// 새 디자인의 러닝 색 — 시안 `162:4905` 의 `거리`~`악조건 극복` 10군.
///
/// ## [RunHue] 는 여기서 새로 만들지 않는다
///
/// `features/color/domain/` 이 그 enum 을 쓴다. 두 벌이 되면 도메인이 어느
/// 쪽을 가리키는지 알 수 없어진다. **이름은 기존 것을 그대로 쓰고 값만 바꾼다.**
///
/// ## ⚠️ 색값이 통째로 달라진다
///
/// 옛 `거리` 는 틸, 새 `거리` 는 파랑이다. 이미 수집한 색이 있는 사용자에게는
/// **같은 색이 다른 색으로 보인다.** 서버는 hue 이름만 들고 있으므로 데이터
/// 마이그레이션은 없다 — 보이는 것만 바뀐다.
///
/// ## 시안의 `동맹` 은 우리 [RunHue.companionship] 이다
///
/// 우리는 `동행` 이라 부른다. 이름을 맞출지는 정하지 않았다(Task 6).
abstract final class RunPaletteV2 {
  /// hue 마다 3개. 순서는 **얕은 것 → 깊은 것** — 기존 `RunPalette` 와 같다.
  /// 시안의 200 / 100 / 50 순서다.
  static const _shades = <RunHue, List<Color>>{
    RunHue.distance: [Color(0xFF7CB5FF), Color(0xFF227DFF), Color(0xFF1556B8)],
    RunHue.speed: [Color(0xFF79E4FF), Color(0xFF18C8FF), Color(0xFF0C7899)],
    RunHue.endurance: [Color(0xFFB09CFF), Color(0xFF6F5CFF), Color(0xFF4B3899)],
    RunHue.consistency: [Color(0xFF79E8A8), Color(0xFF33D17A), Color(0xFF237A4A)],
    RunHue.cadence: [Color(0xFFDEA2FF), Color(0xFFC05CFF), Color(0xFF743899)],
    RunHue.interval: [Color(0xFFFF91C7), Color(0xFFFF4FA3), Color(0xFF9B3266)],
    RunHue.hill: [Color(0xFFFFC278), Color(0xFFFF9F43), Color(0xFFA8642B)],
    RunHue.recovery: [Color(0xFFA0F1E1), Color(0xFF56E0C5), Color(0xFF2D8C7A)],
    RunHue.companionship: [Color(0xFFFFE9A8), Color(0xFFFFD36B), Color(0xFFB98A2F)],
    RunHue.adversity: [Color(0xFFFF9C9C), Color(0xFFFF5B5B), Color(0xFFB83C3C)],
  };

  /// 전 hue 공통 shade 개수.
  static const shadeCount = 3;

  /// [hue] 의 색 3개. 얕은 것부터.
  static List<Color> of(RunHue hue) => _shades[hue]!;
}
```

⚠️ **`RunHue` 의 실제 상수 이름을 Step 1 에서 확인한 것으로 맞춘다.** 위의
`distance`·`speed`·`companionship` 은 한글 주석에서 추정한 것이다. 다르면 그쪽을 따른다.

- [ ] **Step 4: 실패하는 테스트를 쓴다**

`test/v2_run_palette_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:runiverse/core/theme/tokens/run_palette.dart';
import 'package:runiverse/core/theme/v2/run_palette.dart';

/// 새 러닝 팔레트 — **빠진 hue 도 겹치는 색도 없다.**
///
/// 컬렉션 그리드는 30칸을 한 번에 그린다. hue 하나가 비면 화면이 깨지고,
/// 두 hue 가 같은 색이면 무엇을 모았는지 구분할 수 없다.
void main() {
  test('⚠️ 모든 hue 에 색이 있다', () {
    // `_shades` 에서 하나만 빠져도 `of` 가 죽는다.
    for (final hue in RunHue.values) {
      expect(RunPaletteV2.of(hue), hasLength(RunPaletteV2.shadeCount));
    }
  });

  test('⚠️ 30색이 전부 다르다', () {
    final all = [for (final hue in RunHue.values) ...RunPaletteV2.of(hue)];

    expect(all.toSet(), hasLength(all.length));
  });

  test('기존 팔레트와 hue 개수가 같다', () {
    // 옛 화면과 새 화면이 같은 분모(30색)를 말해야 한다.
    expect(RunPaletteV2.shadeCount, RunPalette.shadeCount);
  });
}
```

- [ ] **Step 5: 테스트를 돌린다**

```powershell
.\.fvm\flutter_sdk\bin\flutter.bat test test/v2_run_palette_test.dart
```

Expected: 3개 통과. `⚠️ 모든 hue 에 색이 있다` 가 죽으면 `_shades` 에서 hue 를 빠뜨린 것이다 — Step 3 의 enum 이름을 다시 본다.

- [ ] **Step 6: 세대 혼용 테스트가 통과하는지 확인한다**

```powershell
.\.fvm\flutter_sdk\bin\flutter.bat test test/theme_generation_test.dart
```

Expected: 5개 통과. `v2/run_palette.dart` 가 `tokens/run_palette.dart` 를 import 하지만 **`lib/core/theme/` 안이라 제외 대상**이다. 여기서 실패하면 제외 규칙이 안 먹은 것이다.

- [ ] **Step 7: 전체 검증과 커밋**

```powershell
.\.fvm\flutter_sdk\bin\dart.bat format lib test
.\.fvm\flutter_sdk\bin\flutter.bat analyze
.\.fvm\flutter_sdk\bin\flutter.bat test
```

Expected: analyze `No issues found!`, **917개 통과**(914 + 3).

```bash
git add lib/core/theme/v2 test/v2_run_palette_test.dart
git commit -F - <<'EOF'
📍 Feat: 새 디자인의 색을 v2 토큰으로 세운다

시안 `162:4905` 가 정의하는 셋을 옮긴다 — 중립 11단, 브랜드 2색,
러닝 색 10군 × 3톤.

러닝 색은 이름이 기존 `RunHue` 와 같지만 값이 전혀 다르다. 옛 `거리` 는
틸, 새 `거리` 는 파랑이다. 서버는 hue 이름만 들고 있어서 마이그레이션은
없고 보이는 것만 바뀐다.

`RunHue` enum 은 복제하지 않는다. `features/color/domain/` 이 그것을
쓰는데 두 벌이 되면 어느 쪽을 가리키는지 알 수 없어진다.
EOF
```

---

### Task 3: 시맨틱 색을 세운다

Task 2 가 만든 것은 **이름 붙은 물감**이다. 화면은 그것을 직접 읽지 않는다 —
"배경은 무슨 색인가"를 테마별로 정하는 층이 따로 있고, 기존에는
`lib/core/theme/extensions/app_colors.dart` 가 그 일을 한다(필드 21개 · dark/light 두 벌).

⚠️ **시안에는 시맨틱 정의가 없다.** 원색 시트만 있고 "이 색이 배경"이라는 지정이
없다. 그래서 여기서 **정하는 값이 생긴다.** 정하는 규칙을 코드에 적고, 정한 값을
전부 PR 리뷰 포인트에 올려 디자이너 확인을 받는다.

**Files:**
- Create: `lib/core/theme/v2/app_colors.dart`
- Test: `test/v2_app_colors_test.dart`

**Interfaces:**
- Consumes: Task 2 의 `AppPaletteV2`
- Produces: `AppColorsV2` — `ThemeExtension`. **필드 이름은 기존 `AppColors` 와
  같다**(`bgBase` `textPrimary` `primary` …). `context.appColorsV2` 로 꺼낸다

- [ ] **Step 1: 기존 필드 21개를 그대로 옮겨 적는다**

```powershell
Select-String -Path lib/core/theme/extensions/app_colors.dart -Pattern "final Color"
```

Expected: 21줄. **이름을 하나도 바꾸지 않는다.** 이름이 같아야 화면 코드가
import 한 줄만 바꾸면 되고, 다르면 화면마다 이름을 갈아끼우는 일이 얹힌다.

- [ ] **Step 2: 시맨틱 색을 쓴다**

`lib/core/theme/v2/app_colors.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:runiverse/core/theme/v2/app_palette.dart';

/// 새 디자인의 시맨틱 색 — "이 자리는 무슨 색인가".
///
/// ## ⚠️ 시안이 정해 주지 않은 값이 있다
///
/// 시안에는 원색 시트(`162:4905`)만 있고 "이 색이 배경"이라는 지정이 없다.
/// 아래 값은 **중립 램프에서 규칙으로 뽑은 것**이다.
///
/// - 어두운 테마는 램프를 **깊은 쪽부터** 쓴다 — 배경 950, 면 900, 떠 있는 것 800
/// - 밝은 테마는 **뒤집는다** — 배경은 흰색, 면 50, 떠 있는 것 100
/// - 글자는 배경과 **반대 끝**에서 시작해 한 단계씩 흐려진다
///
/// 규칙이라 일관되지만 **디자이너가 정한 값은 아니다.** 확인받기 전에는
/// 임시로 본다.
///
/// ## 필드 이름은 기존 `AppColors` 와 같다
///
/// 화면을 옮길 때 import 한 줄만 바꾸면 되도록 맞췄다. 이름을 고치면
/// 화면마다 그 일이 얹힌다.
@immutable
class AppColorsV2 extends ThemeExtension<AppColorsV2> {
  const AppColorsV2({
    required this.bgBase,
    required this.bgSurface,
    required this.bgElevated,
    required this.bgScrim,
    required this.borderDefault,
    required this.borderStrong,
    required this.textPrimary,
    required this.textSecondary,
    required this.textTertiary,
    required this.textDisabled,
    required this.textOnPrimary,
    required this.primary,
    required this.primaryHover,
    required this.primaryMuted,
    required this.success,
    required this.warning,
    required this.error,
    required this.info,
    required this.matchWaiting,
    required this.matchConfirmed,
    required this.matchFailed,
  });

  final Color bgBase;
  final Color bgSurface;
  final Color bgElevated;
  final Color bgScrim;
  final Color borderDefault;
  final Color borderStrong;
  final Color textPrimary;
  final Color textSecondary;
  final Color textTertiary;
  final Color textDisabled;
  final Color textOnPrimary;
  final Color primary;
  final Color primaryHover;
  final Color primaryMuted;
  final Color success;
  final Color warning;
  final Color error;
  final Color info;
  final Color matchWaiting;
  final Color matchConfirmed;
  final Color matchFailed;

  /// 시안이 보여주는 쪽. 모든 화면 시안이 어두운 배경이다.
  static const dark = AppColorsV2(
    bgBase: AppPaletteV2.neutral950,
    bgSurface: AppPaletteV2.neutral900,
    bgElevated: AppPaletteV2.neutral800,
    bgScrim: Color(0x990A0A0A),
    borderDefault: AppPaletteV2.neutral800,
    borderStrong: AppPaletteV2.neutral700,
    textPrimary: AppPaletteV2.neutral50,
    textSecondary: AppPaletteV2.neutral300,
    textTertiary: AppPaletteV2.neutral400,
    textDisabled: AppPaletteV2.neutral600,
    textOnPrimary: AppPaletteV2.neutral50,
    primary: AppPaletteV2.brand,
    primaryHover: Color(0xFF7CB5FF),
    primaryMuted: AppPaletteV2.brandDeep,
    // 상태색은 러닝 색 10군에서 성격이 맞는 것을 빌린다. 시안이 상태색을
    // 따로 정의하지 않아서다.
    success: Color(0xFF33D17A),
    warning: Color(0xFFFFD36B),
    error: Color(0xFFFF5B5B),
    info: AppPaletteV2.brand,
    matchWaiting: Color(0xFFFFD36B),
    matchConfirmed: Color(0xFF33D17A),
    matchFailed: Color(0xFFFF5B5B),
  );

  /// 램프를 뒤집은 쪽. **시안에 없다** — 규칙으로 만든 것이다.
  static const light = AppColorsV2(
    bgBase: Color(0xFFFFFFFF),
    bgSurface: AppPaletteV2.neutral50,
    bgElevated: AppPaletteV2.neutral100,
    bgScrim: Color(0x66171717),
    borderDefault: AppPaletteV2.neutral200,
    borderStrong: AppPaletteV2.neutral300,
    textPrimary: AppPaletteV2.label,
    textSecondary: AppPaletteV2.neutral600,
    textTertiary: AppPaletteV2.neutral500,
    textDisabled: AppPaletteV2.neutral400,
    textOnPrimary: Color(0xFFFFFFFF),
    primary: AppPaletteV2.brand,
    primaryHover: Color(0xFF1556B8),
    primaryMuted: Color(0xFF7CB5FF),
    success: Color(0xFF237A4A),
    warning: Color(0xFFB98A2F),
    error: Color(0xFFB83C3C),
    info: Color(0xFF1556B8),
    matchWaiting: Color(0xFFB98A2F),
    matchConfirmed: Color(0xFF237A4A),
    matchFailed: Color(0xFFB83C3C),
  );

  @override
  AppColorsV2 copyWith({
    Color? bgBase,
    Color? bgSurface,
    Color? bgElevated,
    Color? bgScrim,
    Color? borderDefault,
    Color? borderStrong,
    Color? textPrimary,
    Color? textSecondary,
    Color? textTertiary,
    Color? textDisabled,
    Color? textOnPrimary,
    Color? primary,
    Color? primaryHover,
    Color? primaryMuted,
    Color? success,
    Color? warning,
    Color? error,
    Color? info,
    Color? matchWaiting,
    Color? matchConfirmed,
    Color? matchFailed,
  }) => AppColorsV2(
    bgBase: bgBase ?? this.bgBase,
    bgSurface: bgSurface ?? this.bgSurface,
    bgElevated: bgElevated ?? this.bgElevated,
    bgScrim: bgScrim ?? this.bgScrim,
    borderDefault: borderDefault ?? this.borderDefault,
    borderStrong: borderStrong ?? this.borderStrong,
    textPrimary: textPrimary ?? this.textPrimary,
    textSecondary: textSecondary ?? this.textSecondary,
    textTertiary: textTertiary ?? this.textTertiary,
    textDisabled: textDisabled ?? this.textDisabled,
    textOnPrimary: textOnPrimary ?? this.textOnPrimary,
    primary: primary ?? this.primary,
    primaryHover: primaryHover ?? this.primaryHover,
    primaryMuted: primaryMuted ?? this.primaryMuted,
    success: success ?? this.success,
    warning: warning ?? this.warning,
    error: error ?? this.error,
    info: info ?? this.info,
    matchWaiting: matchWaiting ?? this.matchWaiting,
    matchConfirmed: matchConfirmed ?? this.matchConfirmed,
    matchFailed: matchFailed ?? this.matchFailed,
  );

  @override
  AppColorsV2 lerp(covariant AppColorsV2? other, double t) {
    if (other == null) return this;
    Color c(Color a, Color b) => Color.lerp(a, b, t)!;
    return AppColorsV2(
      bgBase: c(bgBase, other.bgBase),
      bgSurface: c(bgSurface, other.bgSurface),
      bgElevated: c(bgElevated, other.bgElevated),
      bgScrim: c(bgScrim, other.bgScrim),
      borderDefault: c(borderDefault, other.borderDefault),
      borderStrong: c(borderStrong, other.borderStrong),
      textPrimary: c(textPrimary, other.textPrimary),
      textSecondary: c(textSecondary, other.textSecondary),
      textTertiary: c(textTertiary, other.textTertiary),
      textDisabled: c(textDisabled, other.textDisabled),
      textOnPrimary: c(textOnPrimary, other.textOnPrimary),
      primary: c(primary, other.primary),
      primaryHover: c(primaryHover, other.primaryHover),
      primaryMuted: c(primaryMuted, other.primaryMuted),
      success: c(success, other.success),
      warning: c(warning, other.warning),
      error: c(error, other.error),
      info: c(info, other.info),
      matchWaiting: c(matchWaiting, other.matchWaiting),
      matchConfirmed: c(matchConfirmed, other.matchConfirmed),
      matchFailed: c(matchFailed, other.matchFailed),
    );
  }
}

extension AppColorsV2Of on BuildContext {
  /// 새 디자인으로 옮긴 화면이 쓴다. 기존 화면은 `appColors` 를 그대로 쓴다.
  AppColorsV2 get appColorsV2 {
    final colors = Theme.of(this).extension<AppColorsV2>();
    assert(colors != null, 'AppColorsV2 를 ThemeData 에 넣지 않았다');
    return colors!;
  }
}
```

⚠️ **`app_theme.dart` 에 등록하는 것은 파일럿 작업(Task 5)에서 한다.** 여기서
등록하면 아직 아무도 안 쓰는 확장이 모든 화면의 테마에 실린다.

- [ ] **Step 3: 실패하는 테스트를 쓴다**

`test/v2_app_colors_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:runiverse/core/theme/v2/app_colors.dart';

/// 새 시맨틱 색 — **두 테마가 다 살아 있는가.**
void main() {
  test('⚠️ 다크와 라이트가 실제로 다르다', () {
    // 한쪽을 복사해 두고 값을 안 바꾸면 라이트 테마에서 글자가 안 보인다.
    expect(AppColorsV2.dark.bgBase, isNot(AppColorsV2.light.bgBase));
    expect(AppColorsV2.dark.textPrimary, isNot(AppColorsV2.light.textPrimary));
  });

  test('⚠️ 글자와 배경이 같은 색이 아니다', () {
    // 램프에서 규칙으로 뽑다가 한 칸 어긋나면 글자가 배경에 묻힌다.
    for (final c in [AppColorsV2.dark, AppColorsV2.light]) {
      expect(c.textPrimary, isNot(c.bgBase));
      expect(c.textSecondary, isNot(c.bgBase));
      expect(c.textOnPrimary, isNot(c.primary));
    }
  });

  test('lerp 는 양 끝을 그대로 돌려준다', () {
    expect(
      AppColorsV2.dark.lerp(AppColorsV2.light, 0).bgBase,
      AppColorsV2.dark.bgBase,
    );
    expect(
      AppColorsV2.dark.lerp(AppColorsV2.light, 1).bgBase,
      AppColorsV2.light.bgBase,
    );
  });
}
```

- [ ] **Step 4: 테스트를 돌린다**

```powershell
.\.fvm\flutter_sdk\bin\flutter.bat test test/v2_app_colors_test.dart
```

Expected: 3개 통과.

- [ ] **Step 5: 전체 검증과 커밋**

```powershell
.\.fvm\flutter_sdk\bin\dart.bat format lib test
.\.fvm\flutter_sdk\bin\flutter.bat analyze
.\.fvm\flutter_sdk\bin\flutter.bat test
```

Expected: analyze `No issues found!`, **920개 통과**(917 + 3).

커밋 메시지:

```
📍 Feat: 새 디자인의 시맨틱 색을 세운다

앞에서 만든 것은 이름 붙은 물감이다. "이 자리는 무슨 색인가"를 테마별로
정하는 층이 따로 필요하다.

시안에는 시맨틱 정의가 없어서 중립 램프에서 규칙으로 뽑았다 — 어두운
쪽은 램프의 깊은 끝부터, 밝은 쪽은 뒤집어서, 글자는 배경의 반대 끝부터.
일관되지만 디자이너가 정한 값은 아니다. 확인 전까지는 임시다.

필드 이름은 기존 AppColors 와 같게 뒀다. 화면을 옮길 때 import 한 줄만
바꾸면 되도록 하려는 것이다.
```

---

### Task 4: 타이포·간격·반경 토큰을 세운다

시안 `160:4574` `Typography` 가 **Heading 01–09 + Body 01–22, 31개**를 정의한다.

⚠️ **간격·반경 정의 시트는 시안에 없다.** 그래서 `v2` 가 기존 값을 **그대로 재수출**한다. 이것이 없으면 옮긴 화면이 `v2/app_colors` 와 `tokens/app_spacing` 을 함께 import 하게 되고, 세대 혼용 테스트가 그것을 막는다.

**Files:**
- Create: `lib/core/theme/v2/app_typography.dart`
- Create: `lib/core/theme/v2/app_spacing.dart`
- Create: `lib/core/theme/v2/app_radius.dart`
- Test: `test/v2_typography_test.dart`

**Interfaces:**
- Consumes: Task 1 의 글꼴 패밀리 `SUIT`
- Produces:
  - `AppTypographyV2.heading01`…`heading09`, `.body01`…`.body22` — 전부 `TextStyle`
  - `AppSpacingV2` · `AppRadiusV2` — 기존 값과 같은 이름·같은 값

- [ ] **Step 1: 타이포 토큰을 쓴다**

`lib/core/theme/v2/app_typography.dart`:

```dart
import 'package:flutter/painting.dart';

/// 새 디자인의 글자 — 시안 `160:4574` `Typography`.
///
/// ## 이름을 시안 그대로 쓴다
///
/// `heading01` `body07` 처럼 의미가 없는 이름이다. 뜻을 담은 이름
/// (`제목` `본문`)으로 바꾸면 **시안과 대조할 수 없다** — 디자이너가 "Body 07"
/// 이라고 말할 때 코드에서 그것을 찾지 못한다. 31개를 다 쓰지는 않겠지만,
/// 쓰지 않는 것을 지우는 것보다 이름이 어긋나는 쪽이 비싸다.
///
/// ## 행간은 배수, 자간은 비율이다
///
/// 시안이 `150%` `-2%` 로 적는다. Flutter 의 [TextStyle.height] 는 배수라
/// 그대로 1.5 가 되고, [TextStyle.letterSpacing] 은 **논리 픽셀**이라
/// 글자 크기를 곱해야 한다. `_t` 가 그것을 한다.
///
/// ## 러닝 수치에는 이걸 그대로 쓰지 않는다
///
/// 초당 여러 번 갱신되는 숫자는 `FontFeature.tabularFigures()` 를 얹어야
/// 자릿수가 흔들리지 않는다(CLAUDE.md). 화면에서 `copyWith` 로 더한다.
abstract final class AppTypographyV2 {
  static const _family = 'SUIT';

  /// [tracking] 은 시안의 퍼센트다 — `-2%` 면 `-0.02`.
  static TextStyle _t(double size, FontWeight weight, double height,
          [double tracking = 0]) =>
      TextStyle(
        fontFamily: _family,
        fontSize: size,
        fontWeight: weight,
        height: height,
        letterSpacing: size * tracking,
      );

  static final heading01 = _t(60, FontWeight.w700, 1.24);
  static final heading02 = _t(32, FontWeight.w600, 1.24);
  static final heading03 = _t(28, FontWeight.w600, 1.50);
  static final heading04 = _t(26, FontWeight.w800, 1.50);
  static final heading05 = _t(24, FontWeight.w600, 1.24);
  static final heading06 = _t(18, FontWeight.w600, 1.50);
  static final heading07 = _t(16, FontWeight.w600, 1.50);
  static final heading08 = _t(14, FontWeight.w600, 1.50);
  static final heading09 = _t(14, FontWeight.w500, 1.24);

  static final body01 = _t(24, FontWeight.w500, 1.24, -0.02);
  static final body02 = _t(20, FontWeight.w600, 1.24);
  static final body03 = _t(20, FontWeight.w600, 1.24, -0.02);
  static final body04 = _t(18, FontWeight.w500, 1.24, -0.02);
  static final body05 = _t(16, FontWeight.w600, 1.50);
  static final body06 = _t(16, FontWeight.w500, 1.50);
  static final body07 = _t(16, FontWeight.w400, 1.50);
  static final body08 = _t(16, FontWeight.w600, 1.50, -0.02);
  static final body09 = _t(16, FontWeight.w400, 1.50, -0.02);
  static final body10 = _t(14, FontWeight.w600, 1.50);
  static final body11 = _t(14, FontWeight.w500, 1.50);
  static final body12 = _t(14, FontWeight.w400, 1.50);
  static final body13 = _t(14, FontWeight.w500, 1.24);
  static final body14 = _t(14, FontWeight.w400, 1.50, -0.02);
  static final body15 = _t(13, FontWeight.w400, 1.50);
  static final body16 = _t(13, FontWeight.w500, 1.24);
  static final body17 = _t(13, FontWeight.w400, 1.24);
  static final body18 = _t(12, FontWeight.w400, 1.24);
  static final body19 = _t(12, FontWeight.w500, 1.50, -0.02);
  static final body20 = _t(12, FontWeight.w400, 1.50, -0.02);
  static final body21 = _t(12, FontWeight.w500, 1.24, -0.02);
  static final body22 = _t(12, FontWeight.w400, 1.24, -0.02);
}
```

- [ ] **Step 2: 간격·반경을 재수출한다**

시안에 정의 시트가 없으므로 값을 만들어내지 않고 기존 것을 가리킨다.

`lib/core/theme/v2/app_spacing.dart`:

```dart
export 'package:runiverse/core/theme/tokens/app_spacing.dart';
```

`lib/core/theme/v2/app_radius.dart`:

```dart
export 'package:runiverse/core/theme/tokens/app_radius.dart';
```

⚠️ **이 두 파일은 비어 보이지만 이유가 있다.** 시안에는 간격·반경 정의 시트가
없다(파운데이션 프레임은 `Typography` 와 `Color` 둘뿐이다). 값을 지어내는 대신
기존 것을 그대로 쓰되, **화면이 `v2` 만 import 하게** 해서 세대 혼용 테스트를
통과시킨다. 시안이 다른 값을 요구하는 화면이 나오면 그때 이 파일에 실제 값을
넣는다 — 그 시점에 화면 코드는 한 줄도 안 바뀐다.

- [ ] **Step 3: 실패하는 테스트를 쓴다**

`test/v2_typography_test.dart`:

```dart
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:runiverse/core/theme/v2/app_typography.dart';

/// 새 타이포 토큰 — **시안의 수치가 그대로 들어왔는가.**
void main() {
  test('⚠️ 자간은 퍼센트가 아니라 픽셀로 들어간다', () {
    // 시안의 `-2%` 를 그대로 -0.02 로 넣으면 24px 글자에서 자간이
    // 0.02px 이 되어 **사실상 0** 이다. 눈으로는 안 보이고 시안과만 어긋난다.
    expect(AppTypographyV2.body01.letterSpacing, closeTo(24 * -0.02, 0.0001));
    expect(AppTypographyV2.body22.letterSpacing, closeTo(12 * -0.02, 0.0001));
  });

  test('자간이 0인 스타일은 0이다', () {
    expect(AppTypographyV2.heading01.letterSpacing, 0);
  });

  test('행간은 배수다', () {
    expect(AppTypographyV2.heading03.height, 1.50);
    expect(AppTypographyV2.heading05.height, 1.24);
  });

  test('⚠️ 모든 스타일이 SUIT 를 쓴다', () {
    // 하나라도 빠지면 그 자리만 시스템 글꼴로 그려진다.
    final styles = <TextStyle>[
      AppTypographyV2.heading01,
      AppTypographyV2.heading04,
      AppTypographyV2.heading09,
      AppTypographyV2.body01,
      AppTypographyV2.body12,
      AppTypographyV2.body22,
    ];

    for (final style in styles) {
      expect(style.fontFamily, 'SUIT');
    }
  });
}
```

- [ ] **Step 4: 테스트를 돌린다**

```powershell
.\.fvm\flutter_sdk\bin\flutter.bat test test/v2_typography_test.dart
```

Expected: 4개 통과.

- [ ] **Step 5: 전체 검증과 커밋**

```powershell
.\.fvm\flutter_sdk\bin\dart.bat format lib test
.\.fvm\flutter_sdk\bin\flutter.bat analyze
.\.fvm\flutter_sdk\bin\flutter.bat test
```

Expected: analyze `No issues found!`, **924개 통과**(920 + 4).

```bash
git add lib/core/theme/v2 test/v2_typography_test.dart
git commit -F - <<'EOF'
📍 Feat: 새 디자인의 글자·간격을 v2 토큰으로 세운다

시안 `160:4574` 의 Heading 01–09 · Body 01–22 를 그대로 옮긴다.
이름도 시안 그대로 둔다 — 뜻을 담은 이름으로 바꾸면 디자이너가
"Body 07" 이라 말할 때 코드에서 찾지 못한다.

시안의 자간은 퍼센트인데 Flutter 는 픽셀이라 글자 크기를 곱한다.
그대로 넣으면 24px 글자의 자간이 0.02px 이 되어 사실상 0이고,
눈으로는 안 보이고 시안과만 어긋난다.

간격·반경은 시안에 정의 시트가 없어 기존 값을 재수출한다. 화면이
v2 만 import 하게 해서 세대 혼용 테스트를 통과시키는 것이 목적이다.
EOF
```

---

### Task 4.5: 디자인 아이콘을 들인다

⚠️ **계획을 쓸 때 몰랐던 작업이다.** 사용자가 알려준 디자인 소스 폴더
저장소 밖 `design_system/runiverse_design_product/runiverse/icon` 에
**자체 아이콘 SVG 33개**(24×24, 합 141KB)가 있다. 시안의 하단 탭 넷
(`Home`·`Book`·`Photo`·`Profile`)이 바로 이것들이다.

CLAUDE.md 는 "아이콘은 Lucide 만 쓴다"고 되어 있다. **사용자가 `flutter_svg`
추가를 승인했다**(2026-09-27). 교체가 끝나면 Lucide 를 빼는 규칙으로 정리한다.

**Files:**
- Modify: `pubspec.yaml` (`flutter_svg` 의존성 + `assets:` 절)
- Create: `assets/icons/` (SVG 33개)
- Create: `lib/core/widgets/v2/app_icon.dart`
- Test: `test/v2_app_icon_test.dart`

**Interfaces:**
- Consumes: Task 3 의 `AppColorsV2`
- Produces: `AppIcon` 위젯과 `AppIcons` 이름 목록 — 옮긴 화면이 쓴다

- [ ] **Step 1: 패키지를 더한다**

```powershell
.\.fvmlutter_sdkinlutter.bat pub add flutter_svg
```

- [ ] **Step 2: SVG 를 복사하고 `assets:` 에 등록한다**

`pubspec.yaml` 의 `flutter:` 절에 `assets: - assets/icons/` 를 더한다.
지금은 `assets:` 절 자체가 없다(주석만 있다).

- [ ] **Step 3: `AppIcon` 위젯을 만든다**

색을 `AppColorsV2` 에서 받아 `ColorFilter` 로 입힌다. 크기 기본 24.

- [ ] **Step 4: 33개가 다 로드되는지 테스트한다**

파일 존재와 이름 목록 일치를 본다. **없는 이름을 부르면 런타임에야 빈
자리로 나타나므로** 테스트로 잡는다.

- [ ] **Step 5: 검증과 커밋**

---

### Task 5: 화면 하나를 옮겨 본다 — 매칭 대기방

**`match_room_page` 를 고른 이유**는 셋이다. 전용 테스트 파일이 있어(`match_room_page_test.dart`, 16개 중 구조 결합 6건) **깨지는 수를 잴 수 있고**, 하단 탭이 없어 탭 4개 결정과 얽히지 않으며, 시안(`158:3415` `매칭 완료 / 세션 로비 페이지`)이 명확하다.

**Files:**
- Modify: `lib/features/matching/presentation/match_room_page.dart`
- Modify: `test/match_room_page_test.dart`
- Create: `lib/core/widgets/v2/` (필요해지면. 미리 만들지 않는다)

**Interfaces:**
- Consumes: Task 2·3·4 의 `AppPaletteV2` `AppColorsV2` `AppTypographyV2` `AppSpacingV2` `AppRadiusV2`
- Produces: 이 화면이 처음 만든 `widgets/v2` 부품들 — 다음 화면이 재사용한다

- [ ] **Step 1: 지금 상태를 기록한다**

```powershell
.\.fvm\flutter_sdk\bin\flutter.bat test test/match_room_page_test.dart
```

Expected: 16개 통과. **이 숫자를 적어 둔다** — Task 6 이 쓴다.

- [ ] **Step 2: 시안을 읽는다**

`figma-design-to-code` 스킬을 먼저 불러온 뒤:

```
get_design_context(fileKey: "MpJxkA7fPj6MJs5uL07CVb", nodeId: "158:3415",
                   clientFrameworks: "flutter", clientLanguages: "dart",
                   skillNames: "figma-design-to-code")
```

돌아오는 React/Tailwind 코드는 **참고자료다.** 그대로 옮기지 않는다. 이 화면이
이미 쓰는 위젯과 provider 를 그대로 두고 **겉모습만** 바꾼다.

시안이 보여주는 것: `매칭완료` · `러닝 시작까지 00:04:10` · `19:00 시작예정` ·
`시작 시간 / 목표 거리 / 참여자` · 하단 주 버튼.

- [ ] **Step 3: 화면의 토큰 import 를 v2 로 통째로 바꾼다**

`match_room_page.dart` 상단에서 `core/theme/tokens/` · `core/theme/extensions/`
를 가리키는 import 를 **전부** `core/theme/v2/` 로 바꾼다.

⚠️ **한 줄이라도 남기면 세대 혼용 테스트가 막는다.** 그게 이 테스트의 일이다.

`context.appColors` 를 쓰던 자리는 `AppPaletteV2` 의 색으로 바꾸되, **다크·라이트
두 테마를 모두 정의한다**(CLAUDE.md). 시안은 어두운 배경 하나만 주므로 밝은 쪽은
중립 램프를 뒤집어 만든다.

- [ ] **Step 4: 테스트를 돌려 몇 개가 깨지는지 센다**

```powershell
.\.fvm\flutter_sdk\bin\flutter.bat test test/match_room_page_test.dart
```

⚠️ **여기서 나온 숫자가 이 작업의 산출물이다.** 0개일 수도 있고 6개일 수도 있다.
어느 쪽이든 적어 둔다 — Task 6 이 나머지 18개 화면의 방식을 그것으로 정한다.

- [ ] **Step 5: 깨진 것을 고친다**

스펙 5절 `고칠 때 참고표` 를 쓴다.

| 깨진 것 | 옮길 곳 |
|---|---|
| `find.widgetWithText(AppButton, '시작')` | `find.text('시작')` |
| `tester.widget<AppButton>(…).onPressed` 가 `null` 인가 | 탭해 보고 아무 일도 안 일어나는지 |
| `find.byType(TextField)` 로 n 번째 입력 | `ValueKey` 로 찾는다 |
| `findsNWidgets(3)` | 각 항목이 있는지 |

⚠️ **고친 뒤에도 실패할 수 있어야 한다.** 화면 동작을 일부러 하나 부수고 그
테스트가 빨개지는지 본다. 확인 후 되돌린다. `profile_edit_page_test` 에서 한 것과
같은 절차다.

- [ ] **Step 6: 화면 클래스 단정은 건드리지 않는다**

```powershell
Select-String -Path test/match_room_page_test.dart -Pattern "find.byType\(MatchRoomPage\)"
```

라우팅을 보는 단정이고 화면 클래스 이름은 그대로다. **고칠 이유가 없다.**

- [ ] **Step 7: 전체 검증**

```powershell
.\.fvm\flutter_sdk\bin\dart.bat format lib test
.\.fvm\flutter_sdk\bin\flutter.bat analyze
.\.fvm\flutter_sdk\bin\flutter.bat test
```

Expected: analyze `No issues found!`, **924개 통과**.

- [ ] **Step 8: ⚠️ 에뮬레이터로 눈으로 본다**

테스트는 글꼴을 검증하지 못한다(위젯 테스트는 Ahem 으로 그린다). **여기가 SUIT 가
실제로 실렸는지 확인하는 유일한 자리다.**

```powershell
adb devices
.\.fvm\flutter_sdk\bin\flutter.bat run --dart-define-from-file=config/dev.json
```

확인할 것 넷:

1. 글자가 SUIT 로 보이는가 (시스템 글꼴과 다른가)
2. **다크·라이트 두 테마**에서 다 읽히는가
3. 시안과 색·간격이 맞는가
4. 매칭 대기방의 동작(카운트다운·참여자 목록·입장)이 그대로인가

- [ ] **Step 9: 커밋**

```bash
git add lib/features/matching/presentation/match_room_page.dart test/match_room_page_test.dart lib/core/widgets/v2
git commit -F - <<'EOF'
🎨 Style: 매칭 대기방을 새 디자인으로 옮긴다

화면 20개 중 첫 번째다. 절차 자체를 검증하는 것이 목적이라, 전용
테스트 파일이 있어 깨지는 수를 잴 수 있고 하단 탭과 얽히지 않은
화면을 골랐다.

토큰 import 를 v2 로 통째로 바꿨다. 한 줄이라도 남으면 세대 혼용
테스트가 막는다.

깨진 단정은 이 커밋 안에서 고쳤고, 고친 뒤 화면을 일부러 부수어
여전히 빨개지는 것을 확인했다.
EOF
```

---

### Task 6: 잰 것을 적고 나머지 순서를 정한다

**Files:**
- Modify: `docs/specs/2026-09-25-ui-redesign-workspace-design.md`

**Interfaces:**
- Consumes: Task 5 Step 4 의 "깨진 테스트 수", Task 5 Step 9 의 `widgets/v2` 목록
- Produces: 없음 (문서). 다음 계획이 이것을 근거로 화면 순서를 정한다

- [ ] **Step 1: 스펙 8절을 채운다**

`## 8. 아직 안 정한 것` 을 아래로 **교체**한다. 대괄호 안은 Task 5 에서 실제로 잰
값으로 채운다 — 추정하지 않는다.

```markdown
## 8. Figma 와 대응

파일 `MpJxkA7fPj6MJs5uL07CVb` (`runiverse_final2`), 화면은 전부 `149:791` 아래.

| 시안 | 노드 | 우리 화면 |
|---|---|---|
| 스플래시 페이지 | `158:2695` | `splash_page` |
| 온보딩 페이지(1) | `158:2699` | `onboarding_intro_page` |
| 회원가입 페이지(1) | `158:2720` | `sign_up_page` |
| 프로필 등록 페이지(2) | `158:2758` | `profile_setup_page` |
| 약관동의 페이지(3) | `158:2804` | `terms_agreement_page` |
| 로그인 페이지 | `158:2913` | `sign_in_page` |
| 메인페이지 · 대기 · 실패 · 완료 | `158:2848` `2951` `3029` `3102` | `home_page` + `home_hero` |
| 매칭등록 페이지 | `158:3181` | `match_register_page` |
| 매칭 완료 / 세션 로비 | `158:3415` | `match_room_page` |
| 출발 대기실 페이지 | `158:3453` | `match_countdown_page` |
| 실시간 기록페이지 | `158:3493` | `run_session_page` |
| 내 GPS 페이지 | `158:3545` | `run_session_page` 의 지도 탭 |
| 파티원 비교 페이지 | `158:4233` | `run_session_page` 의 파티 탭 |
| 러닝 종료 요약 페이지 | `158:3764` | `run_summary_page` |
| 종료 후 대시보드 | `158:3602` | `run_summary_page` 확장 |
| 기록 페이지 | `158:3793` `194:659` | `record_page` |
| 프로필 페이지+컬러도감 | `158:3905` | `profile_page` |
| 프로필 페이지+뱃지도감 | `158:4143` | `profile_page` 변형 |
| 파운데이션 `Typography` | `160:4574` | `theme/v2/app_typography` |
| 파운데이션 `Color` | `162:4905` | `theme/v2/app_palette` · `run_palette` |

### 시안에만 있는 것 (4)

`친구 목록` `친구초대 페이지` `컬러리빌 > 뱃지 획득` `도감 상세`.
**화면만 껍데기로** 만들고 데이터는 붙이지 않는다.

### 우리에만 있는 것 (6)

`profile_edit_page` `record_detail_page` `settings_page`
`password_change_page` `run_prepare_page`(위치 권한·GPS 대기) `ComingSoonPage`.
**새 토큰만 입혀 유지**한다.

### ⚠️ 시안이 요구하는데 우리에게 없는 데이터

- **케이던스(spm)** — `실시간 기록` 과 `파티원 비교` 가 `172 spm` 을 보여준다. 지금 수집하지 않는다
- **칼로리(kcal)** — `실시간 기록` 이 `214 kcal` 를 보여준다
- **뱃지** — `종료 후 대시보드` 가 `새로운 뱃지 2개` 를 보여준다

화면을 옮길 때 **없는 값을 지어내지 않는다.** 그 자리를 비우거나 항목을 빼고,
백엔드에 요청할 것을 따로 적는다.

## 9. 파일럿에서 잰 것

`match_room_page` 를 옮겼다(2026-09-26).

- 테스트 16개 중 **[N]개가 깨졌다**. 스펙 1절의 상한(구조 결합 6건) 대비 **[비율]**
- 고친 방식: [실제로 쓴 것]
- 새로 만든 `widgets/v2` 부품: [목록, 없으면 "없음"]
- PR 규모: [파일 수 / 줄 수]

**판단:** [깨진 수가 적으면 이대로. 20개씩 깨지면 5절을 다시 본다]

## 10. 아직 안 정한 것

- **나머지 18개 화면의 순서** — 파일럿이 만든 `widgets/v2` 를 가장 많이 쓰는
  화면부터 간다. `AppButton` 을 19개 중 15개 화면이 쓰므로 그것이 기준이다
- **`RunHue.companionship` 의 이름** — 우리는 `동행`, 시안은 `동맹`
```

- [ ] **Step 2: 검증**

```powershell
.\.fvm\flutter_sdk\bin\flutter.bat analyze
.\.fvm\flutter_sdk\bin\flutter.bat test
```

Expected: analyze `No issues found!`, 924개 통과.

- [ ] **Step 3: 커밋**

```bash
git add docs/specs/2026-09-25-ui-redesign-workspace-design.md
git commit -m "📝 Docs: Figma 대응표와 파일럿 실측을 적는다"
```

- [ ] **Step 4: PR 을 연다**

```bash
git push -u origin feat/ui-redesign-foundation
gh pr create --repo SWM-TeamBruteForce/runiverse-frontend \
  --base dev --head jihwanjo-98:feat/ui-redesign-foundation \
  --title "📍 Feat: 새 디자인의 토큰을 세우고 화면 하나를 옮긴다"
```

본문은 `.github/pull_request_template.md` 의 여섯 절을 채운다.

**💬 리뷰 포인트에 반드시 적을 것 — CLAUDE.md 수정안 둘:**

> 이번 작업으로 CLAUDE.md 의 규칙 둘이 사실과 어긋납니다. **파일은 고치지
> 않았습니다.** 팀 확인 후 별도 PR 로 올리겠습니다.
>
> **1. 하단 탭 5개 → 4개**
> 현재: *"하단 탭 5개는 홈 / 기록 / 피드 / 대회일정 / 프로필이다."*
> 제안: *"하단 탭 4개는 홈 / 기록 / 기록카드 / 프로필이다. 기록카드는 그때 뛴
> 경험을 회고·아카이빙하는 탭이고, 화면은 `ComingSoonPage` 다. `대회일정` 은
> 탭에서 뺀다."*
> 근거: 시안 `158:2899` 의 탭이 넷이다.
>
> **2. "친구" 금지 해제**
> 현재: *"UI 텍스트는 한국어. '친구'라는 말은 쓰지 않는다 (요청→수락 모델)."*
> 제안: *"UI 텍스트는 한국어."* — 뒷문장을 지운다.
> 근거: 시안이 `친구랑 뛰기` · `친구 목록` · `친구초대` 로 쓴다.
>
> ⚠️ 2번은 제품 모델이 바뀐 것인지 시안의 임시 문구인지 제가 판단할 수 없습니다.
> 기획 확인이 필요합니다.

- [ ] **Step 5: base 확인**

```bash
gh pr view --repo SWM-TeamBruteForce/runiverse-frontend --json baseRefName -q .baseRefName
```

Expected: `dev`.

---

## 이 계획이 다루지 않는 것

**나머지 18개 화면.** 순서를 파일럿 결과로 정하기로 스펙이 이미 정했고, 여기서
18개를 미리 적으면 전부 같은 모양의 빈 작업이 된다. Task 6 이 순서를 정하면
**세 번째 계획**을 쓴다.

같이 미루는 것:

- **하단 탭 5→4 구현** — CLAUDE.md 수정이 승인된 뒤에 한다. `AppShell` 과 라우팅,
  `홈`·`기록`·`프로필` 세 화면이 한꺼번에 얽힌다
- **시안에만 있는 화면 4개의 껍데기** — 라우팅이 먼저 정리돼야 한다
- **케이던스·칼로리·뱃지** 백엔드 요청 — 그 값을 쓰는 화면을 옮길 때 정리한다
- **마무리 정리**(스펙 7절) — 마지막 화면을 옮긴 뒤 `v2/` 를 본래 자리로 올리고,
  그때 `test/theme_generation_test.dart` 도 역할이 끝나 같이 지운다
