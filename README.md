# Runiverse Frontend

> 멀리 떨어져 있어도 함께 달리는 원격 동반 러닝 플랫폼, **Runiverse**의 모바일 앱입니다.

같은 시간에 서로 다른 장소에서 함께 달립니다. 안드로이드를 먼저 내고 iOS는 이후에 출시합니다.
서버는 [runiverse-backend](https://github.com/SWM-TeamBruteForce/runiverse-backend)입니다.

## 기술 스택

| 분류 | 사용 기술 |
|---|---|
| Language / Framework | Dart 3.12, Flutter 3.44.8 (fvm으로 고정) |
| State | Riverpod 3 |
| Routing | go_router |
| Network | dio, web_socket_channel |
| Storage | flutter_secure_storage, sqflite |
| Auth | 이메일, 카카오, 구글, 애플 |
| Location / Sensor | flutter_naver_map, geolocator, pedometer |
| Observability | Firebase Analytics, Crashlytics |
| Test | flutter_test, integration_test |
| CI/CD | GitHub Actions → Play 내부 테스트 / TestFlight |

## 프로젝트 구조

```text
runiverse-frontend
├── lib
│   ├── app         # 앱 진입 · go_router 설정
│   ├── core        # 기능 무관 공통 (network · storage · theme · strings · config)
│   └── features    # 기능별 폴더 (data / domain / presentation)
├── test            # 위젯 · 단위 테스트
├── integration_test # 기기에서 도는 테스트 (GPS · SQLite 같은 플랫폼 채널)
├── config          # 환경별 설정 (커밋하지 않는다)
└── docs            # 설계 · 컨벤션 문서
```

의존 방향은 **`presentation → domain ← data`** 한 방향입니다. `presentation`은 `data`를 import하지 않고,
`domain`은 순수 Dart만 씁니다. 다른 feature의 화면·위젯은 import하지 않고, 공유가 필요하면 `core/widgets/`로 올립니다.

## 시작하기

Flutter SDK는 [fvm](https://fvm.app)으로 고정합니다. **전역 `flutter` 명령을 쓰지 않습니다** —
`.fvmrc`에 적힌 버전과 다른 SDK로 빌드하면 CI와 결과가 갈립니다.

```bash
dart pub global activate fvm   # fvm이 없다면
fvm install                    # .fvmrc의 버전을 받는다
fvm flutter pub get

fvm flutter run --dart-define-from-file=config/dev.json
```

```bash
fvm flutter analyze   # 경고 0개를 유지한다
fvm flutter test
fvm dart format lib test
```

> **`config/dev.json`이 없으면 앱이 시작하자마자 멈춥니다.** 서버 주소와 지도·로그인 키가 여기서 오고,
> 없으면 HTTP 클라이언트를 만들지 못한 채 스플래시에 머뭅니다.
> `config/dev.example.json`을 복사해 값을 채우세요. `config/*.json`은 커밋 대상이 아닙니다.

기본 flavor는 `dev`(`com.runiverse.app.dev`)입니다. 운영 빌드만 `--flavor prod`를 붙입니다 —
자세한 절차는 [release.md](docs/release.md)에 있습니다.

## 브랜치 전략 · 배포

| 브랜치 | 역할 | 동작 |
|---|---|---|
| `<type>/<domain>` | 기능 개발 | `dev`로 PR을 열어 리뷰 후 머지 |
| `dev` | 통합 | Actions에서 **Dev Release**를 돌리면 dev 앱을 Play 내부 테스트·TestFlight에 올린다 |
| `main` | 운영 | `dev`에서 온 PR만 허용. 머지되면 analyze·test 후 운영 앱을 빌드해 업로드(**Prod Release**) |

- 브랜치는 하루를 넘기지 않습니다. PR을 연 날 머지하고, 리뷰가 걸리면 그동안 `dev`를 따라잡습니다.
- `main`·`dev`에 직접 커밋·push하지 않습니다. **PR의 base는 `dev`입니다** — GitHub가 `main`을 기본으로 잡아 두니 열 때마다 확인합니다.
- `main` PR은 같은 레포의 `dev` 브랜치에서 온 것만 통과합니다(Main Branch Guard).
- 두 앱 모두 **스토어에 손으로 올리지 않습니다.** 손으로 올린 번호를 CI가 따라잡을 때까지 업로드가 거절됩니다.
- 스토어 **공개**는 자동화하지 않았습니다. Play 프로덕션 승급과 iOS 심사 제출·출시는 사람이 합니다.

## 문서

| 문서 | 내용 |
|---|---|
| [CONTRIBUTING.md](docs/CONTRIBUTING.md) | 커밋 · 브랜치 · PR 규칙 |
| [implementation-notes.md](docs/implementation-notes.md) | 구현 함정 · 문서 정본 규칙 |
| [release.md](docs/release.md) | flavor · 서명 · 빌드 · 배포 절차 |
| [specs/](docs/specs) | 기능별 설계 문서 |
| [plans/](docs/plans) | 구현 계획 |

기획·디자인 원본(IA · 기능명세 · 와이어프레임 · 디자인 시스템)은 이 저장소 밖에 있습니다.
화면은 **와이어프레임 최종본과 Figma 두 가지를 근거로** 만듭니다.

## 팀원

| <img src="https://github.com/jihwanjo-98.png" width="120"> | <img src="https://github.com/KimDwDev.png" width="120"> | <img src="https://github.com/zxc88kr.png" width="120"> |
|:---:|:---:|:---:|
| **조지환** | **김동완** | **박찬** |
| [@jihwanjo-98](https://github.com/jihwanjo-98) | [@KimDwDev](https://github.com/KimDwDev) | [@zxc88kr](https://github.com/zxc88kr) |
| AI / Frontend | Backend | Backend |
