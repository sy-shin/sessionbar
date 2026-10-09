<p align="center">
  <img src="Assets/banner.svg" alt="sessionbar — Codex CLI sessions in the macOS menu bar" width="100%">
</p>

<p align="center">
  <img src="https://img.shields.io/badge/macOS-14%2B-111827?style=for-the-badge&logo=apple&logoColor=white" alt="macOS 14+">
  <img src="https://img.shields.io/badge/Swift-6%2B-F05138?style=for-the-badge&logo=swift&logoColor=white" alt="Swift 6+">
</p>

<p align="center"><a href="#한국어">한국어</a> · <a href="#english">English</a></p>

---

<a id="한국어"></a>

## 한국어

**sessionbar**는 여러 터미널의 Codex CLI 세션을 macOS 메뉴 막대에서 확인하는 앱입니다. 프로젝트와 세션별 상태를 보고, 최근 응답과 작업 기록을 열어 볼 수 있습니다.

### 기능

| | 기능 |
|:--:|:--|
| ◉ | **메뉴 막대 요약** — 실행 중 추정 수·활성 세션 수·확인 필요 추정 표시 |
| ⌕ | **세션 목록** — 프로젝트, 경로, 요청 요약, 마지막 활동, 터미널 정보와 검색 |
| ◷ | **세션 상세** — 최신 Codex 응답과 최근 활동을 크기 조절 창에서 확인 |
| ♫ | **알림** — 확인 필요 추정·완료·오류, 알림음, 조용한 시간대, 일시 중지, 반복 제한 |
| ▦ | **활동 기록** — 날짜별 완료·오류 작업 조회 및 기간을 지정하는 CSV 내보내기 |
| ⚙ | **설정** — 로그인 시 실행, 메뉴 표시, 보관 기간, 자동 갱신, 세션 폴더 연결, 한국어·영어 선택 |

상태는 **실행 추정 · 확인 필요 추정 · 완료 · 유휴 추정 · 오류 · 상태 불명**으로 표시합니다. 마지막 활동 시각과 상태 근거는 세션 상세에서 확인할 수 있습니다.

프로젝트 폴더를 열거나 세션 ID·재개 명령을 복사할 수 있습니다.

### 빌드 및 설치

macOS 14 이상, Swift 6 이상과 Command Line Tools 또는 Xcode가 필요합니다.

```sh
./scripts/build-app.sh --install
```

앱은 `~/Applications/sessionbar.app`에 설치됩니다. 앱을 열면 세션 목록이 표시되고, 목록 창을 닫은 뒤에도 메뉴 막대에서 사용할 수 있습니다.

앱 파일만 빌드하려면:

```sh
./scripts/build-app.sh
```

생성된 앱은 `build/sessionbar.app`입니다.

### 사용

1. 메뉴 막대의 터미널 아이콘을 눌러 열린 세션을 확인합니다.
2. 세션을 선택하면 최신 응답과 활동을 볼 수 있습니다.
3. 시계 버튼으로 날짜별 활동 기록을, 톱니바퀴 버튼으로 설정을 엽니다.

메뉴 막대는 `실행 중~ 2 · 활성 6`처럼 표시합니다. 활성 수에는 작업을 마치고 입력을 기다리는 열린 세션도 포함됩니다. 설정의 **언어**에서 시스템·한국어·영어를 선택할 수 있습니다.

세션 기록을 읽을 수 없으면 해당 세션을 상태 불명으로 표시합니다. **세션 폴더 연결…**에서 기록이 있는 폴더를 선택할 수 있습니다.

기본 화면은 **크림색 배경과 흰색 카드**입니다. 설정에서 시스템 테마를 선택할 수 있습니다.

기본 새로고침 간격은 **15초**, 완료·유휴 기록 보관 기간은 **30일**입니다. 파일이 바뀔 때도 목록을 갱신합니다.

### 검증

```sh
./scripts/swift.sh test
```

---

<a id="english"></a>

## English

**sessionbar** shows Codex CLI sessions from multiple terminals in the macOS menu bar. View each project's sessions, check their status, and open recent replies and task history.

### Features

| | Feature |
|:--:|:--|
| ◉ | **Menu bar summary** — estimated running count, active session count, and attention estimates |
| ⌕ | **Session list** — projects, paths, request summaries, last activity, terminal information, and search |
| ◷ | **Session details** — latest Codex reply and recent activity in a resizable window |
| ♫ | **Notifications** — attention estimates, completions, errors, sound, quiet hours, pause, and repeat limits |
| ▦ | **Activity history** — completed and failed tasks by date, plus CSV export for a chosen range |
| ⚙ | **Settings** — launch at login, menu display, retention, automatic refresh, session folder connections, and Korean/English language selection |

Statuses are **running estimate · attention estimate · completed · idle estimate · error · unknown**. Session details show the last activity time and the evidence behind the status.

Open the project folder or copy a session ID or resume command.

### Build and install

Requires macOS 14 or later, Swift 6 or later, and Command Line Tools or Xcode.

```sh
./scripts/build-app.sh --install
```

The app installs to `~/Applications/sessionbar.app`. Opening it shows the session list. After closing that window, the app remains available in the menu bar.

To build the app bundle without installing:

```sh
./scripts/build-app.sh
```

The output is `build/sessionbar.app`.

### Usage

1. Click the terminal icon in the menu bar to see open sessions.
2. Select a session to read its latest reply and recent activity.
3. Use the clock button for daily history and the gear button for settings.

The menu bar displays counts such as `Running~ 2 · Active 6`. The active count includes open sessions that have finished a task and are waiting for input. Choose **System**, **한국어**, or **English** in the language settings.

Sessions with unavailable records remain visible as unknown. Use **Connect session folder…** to select the folder containing their records.

The default appearance uses a **cream background and white cards**. Choose the system appearance in settings to follow macOS.

The default refresh interval is **15 seconds**, and completed and idle records are retained for **30 days**. File changes also refresh the list.

### Verification

```sh
./scripts/swift.sh test
```
