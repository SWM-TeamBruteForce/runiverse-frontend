# Contributing — Runiverse Frontend

협업 규칙. 구현 함정은 [`implementation-notes.md`](implementation-notes.md)를 본다.

---

## 브랜치

- 형식: **`<type>/<domain>`**
- 소문자, 단어가 여럿이면 **kebab-case(`-`)**

```text
feat/oauth-login
feat/profile-image
fix/token-refresh
refactor/running-session
docs/websocket-api
chore/project-setup
```

`main`과 `dev`에 직접 커밋·push하지 않는다. 항상 작업 브랜치를 따서 PR로 합친다.

| 브랜치 | 역할 |
|---|---|
| `main` | 출시된 상태. 릴리스할 때만 갱신 |
| `dev` | 통합 브랜치. 작업 브랜치가 모이는 곳 |

---

## 커밋 메시지

```text
<type>: <간단한 설명>

(선택)
본문
```

| Type | 설명 |
|------|------|
| 📍 Feat | 새로운 기능을 추가합니다. |
| 🔨 Fix | 버그를 수정하거나 기존 기능(UI/UX 포함)의 문제를 해결합니다. |
| 📝 Docs | 문서를 추가하거나 수정합니다. |
| 🎨 Style | 코드 포맷, 들여쓰기, 공백 등 스타일을 수정합니다. (기능 변경 없음) |
| 🤖 Refactor | 기능 변경 없이 코드 구조를 개선합니다. |
| ✅ Test | 테스트 코드를 추가하거나 수정합니다. |
| 🚚 Chore | 빌드, 설정, 라이브러리, 개발 환경 등을 변경합니다. |
| ✂️ Remove | 파일 또는 사용하지 않는 코드를 삭제합니다. |
| 🔧 Rename | 파일 또는 폴더의 이름을 변경하거나 이동합니다. |

### 예시

```text
📍 Feat: 카카오 로그인 기능 추가

🔨 Fix: JWT 만료 처리 오류 수정

🤖 Refactor: MatchingService 책임 분리

📝 Docs: WebSocket API 명세서 수정

🚚 Chore: Flutter 프로젝트 초기 세팅
```

### 규칙

- 제목은 `<type>: <간단한 설명>` 형식. 설명은 간결하고 명확하게.
- 하나의 커밋에는 **하나의 논리적인 변경 사항만** 포함한다.
- 추가 설명이 필요한 경우에만 본문(Body)을 작성한다.
- 커밋을 나눌 때 **각 커밋이 그 시점에 빌드되는지** 확인한다.
  예를 들어 `pubspec.yaml`의 `assets:`/`fonts:` 선언은 해당 파일을 추가하는 커밋과 같은 커밋에 넣는다.

---

## Pull Request

- **base는 `dev`.** GitHub가 기본 브랜치(`main`)를 base로 잡아두므로 PR을 열 때마다 확인한다.
- 올리기 전에 확인:
  ```powershell
  fvm dart format lib
  fvm flutter analyze     # 경고 0개
  fvm flutter test
  ```
- 한 PR은 파일 20개 / 500줄을 넘기지 않는다.
  프로젝트 초기 세팅처럼 생성 도구가 만든 파일이 대부분이라 불가피하면, 그 사유를 PR 본문에 적는다.
- PR 본문에는 **무엇을 왜 바꿨는지**와 **어떻게 검증했는지**를 적는다.

---

## 커밋하지 않는 것

`.env` · `*.keystore` · `*.jks` · `key.properties` · `google-services.json` · `.fvm/` 내부 · 빌드 산출물

API 키와 시크릿은 코드에 하드코딩하지 않고 `lib/core/config/`의 환경변수로만 다룬다.
소셜 로그인 시크릿은 서버 보관이 원칙이다.
