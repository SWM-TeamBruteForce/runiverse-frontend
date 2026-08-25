# 키·시크릿 관리 설계

2026-08-25 · 대상 `core/config` · `config/*.json` · `.gitignore` · `.claude/`

이 문서는 **무엇을 왜 그렇게 정했는지**만 적는다.

---

## 0. 전제 — 앱에 넣은 값은 숨길 수 없다

APK를 뜯으면 `--dart-define`이든 `.env`든 난독화를 했든 **꺼낼 수 있다.**
그래서 목표를 "숨긴다"가 아니라 둘로 나눈다.

1. **저장소와 대화에 평문으로 남기지 않는다** — 이건 완전히 막을 수 있다
2. **앱에 들어가도 되는 값만 넣는다** — 나머지는 서버에서만 다룬다

---

## 1. 키의 종류를 먼저 가른다

| 종류 | 앱에 넣나 | 어디에 두나 |
|---|---|---|
| 네이버 지도 Client ID | **넣는다** | `config/*.json` → `--dart-define-from-file` |
| 카카오 네이티브 앱 키 | **넣는다** | 위와 같음 + Gradle 프로퍼티(2-3) |
| Access·Refresh Token | 실행 중 저장 | `flutter_secure_storage` (이미 그렇게 함) |
| OAuth Client Secret | **금지** | 백엔드 환경변수 |
| NCP·AWS Secret Key | **금지** | 서버 또는 CI Secret |
| DB 비밀번호 · JWT 서명키 | **금지** | 백엔드에서만 |

앞의 둘은 SDK가 앱에서 직접 쓰므로 넣을 수밖에 없다. 대신 **콘솔에서 패키지명으로
묶어** 다른 앱이 훔쳐 써도 인증이 통과하지 않게 한다.

> ⚠️ `ncp_iam_...`로 시작하는 IAM Access Key는 지도 Client ID와 **다른 값**이다.
> Secret Key와 짝을 이루면 계정 리소스를 제어할 수 있어 앱에 넣으면 안 된다.

---

## 2. 결정

### 2-1. 명령줄이 가장 큰 구멍이었다

`.gitignore`도 파일 권한도 아니었다. **키를 매번 `--dart-define`으로 적어야 해서**
셸 히스토리·프로세스 목록·작업 기록에 평문으로 남았다. 실제로 그렇게 새어 나갔다.

```
config/dev.json          실제 키. 커밋하지 않는다
config/dev.example.json  빈 값. 팀원이 복사해서 채운다
```

```bash
fvm flutter run --dart-define-from-file=config/dev.json
```

이 방식도 APK 안의 값을 감추지는 못한다. **막는 것은 "저장소와 기록에 남는 경로"** 하나다.

### 2-2. 릴리스에서만 멈춘다

개발 중에 키가 없는 것은 흔하고, 그때는 그 기능만 빠진 채 나머지를 돌리는 편이 낫다.
지도가 없어도 러닝은 돌아간다.

**배포본에 키가 빠진 것은 사고다.** 조용히 넘어가면 지도가 안 뜨는 앱이 스토어에
올라가고 원인은 리뷰로 알게 된다. `kReleaseMode`면 기동하자마자 `StateError`로 멈춰
빌드 파이프라인이 잡게 한다.

```dart
void _requireInRelease(bool present, String name) {
  if (kReleaseMode && !present) throw StateError('$name이 없습니다...');
}
```

### 2-3. 카카오 키는 두 경로로 들어간다

`--dart-define`은 Dart 코드만 본다. **매니페스트의 리다이렉트 스킴은 읽지 못한다** —
`kakao<앱키>` 형식이라 Gradle 프로퍼티로 한 번 더 넘겨야 한다.

```bash
fvm flutter build apk --dart-define-from-file=config/prod.json \
                      -PKAKAO_NATIVE_APP_KEY=...
```

⚠️ **`--dart-define-from-file` 하나로 끝나지 않는 유일한 키다.** 두 값이 어긋나면
로그인 창은 뜨는데 돌아오지 못한다.

### 2-4. AI가 키 파일을 읽지 못하게 막는다

`.gitignore`는 커밋을 막을 뿐 **읽기를 막지 않는다.** 코딩 에이전트는 저장소 파일을
읽을 수 있으므로 권한으로도 차단한다.

`.claude/settings.local.json`

```json
{ "permissions": { "deny": [
  "Read(./config/dev.json)", "Read(./config/prod.json)",
  "Read(./.env)", "Read(./.env.*)",
  "Read(./android/key.properties)", "Read(./android/app/*.jks)"
] } }
```

> ⚠️ **팀 전체에 공유되지 않는다.** `.gitignore`가 `.claude/`를 통째로 무시하고 있어
> (팀 저장소에 개인 설정을 섞지 않기로 한 결정) 이 규칙은 각자 기기에만 적용된다.
> **새로 합류하는 사람은 직접 넣어야 한다.** 이 문서가 그 안내다.

작업을 시킬 때도 값을 부르지 않는 편이 낫다 —
"`NAVER_MAP_CLIENT_ID`가 이미 설정돼 있다고 가정하고 구현해줘".

---

## 3. 아직 안 한 것 — 개발·운영 키 분리

지금은 **패키지명이 하나**이고 개발·운영이 같은 Client ID를 쓴다.
개발 중 실수로 호출이 튀면 운영 사용량이 함께 깎인다.

### 하려면 이렇게 한다

```kotlin
// android/app/build.gradle.kts
buildTypes {
    debug { applicationIdSuffix = ".debug" }
}
```

| | 패키지명 | Client ID |
|---|---|---|
| 개발 | `com.swmaestro.runiverse.debug` | 별도 발급 · 한도 낮게 |
| 운영 | `com.swmaestro.runiverse` | 별도 발급 · 로컬에서 쓰지 않음 |

### 왜 미뤘나

패키지명을 나누면 **함께 손봐야 하는 것이 넷**이다.

1. 네이버 콘솔에 두 패키지 등록
2. **카카오 리다이렉트 스킴** — 패키지에 묶여 있어 개발 빌드 로그인이 깨진다
3. 서명 키 — 콘솔이 패키지명과 함께 검증한다
4. 기존 에뮬레이터·기기의 앱이 다른 앱으로 취급되어 다시 깔린다

배포가 가까워질 때 한 번에 하는 편이 안전하다. **그전까지는 운영 키가 개발 기기에
들어가 있다는 것을 알고 쓴다.**

---

## 4. 이미 노출된 값

| 값 | 상태 | 할 일 |
|---|---|---|
| NCP IAM Access Key | 작업 기록에 평문 | **재발급 권장** — 계정 제어권이 걸린 값이다 |
| 네이버 지도 Client ID | 작업 기록에 평문 | 패키지명 제한이 있어 위험은 낮다. 불안하면 재발급 |
| 카카오 네이티브 앱 키 | 이전 작업의 명령줄에 평문 | 같음 |

`config/*.json`으로 옮긴 뒤부터는 새로 새어 나갈 경로가 없다.

---

## 5. 하지 않기로 한 것

| | 이유 |
|---|---|
| 난독화로 키 감추기 | APK에서 추출된다. 시간만 든다 |
| `flutter_dotenv` | `.env`가 assets에 들어가 **더 쉽게** 열린다 |
| 키를 서버에서 받아오기 | 지도 SDK는 초기화 시점에 키가 필요하다. 받아오는 통로 자체도 인증이 필요해 문제가 되돌아온다 |
