<div align="center">

# ⌘ sessionbar

### Codex CLI sessions in the macOS menu bar.

**Codex CLI sessions · status · recent activity.**

![macOS](https://img.shields.io/badge/macOS-14%2B-111827?style=for-the-badge&logo=apple&logoColor=white)
![Swift](https://img.shields.io/badge/Swift-5.9%2B-F05138?style=for-the-badge&logo=swift&logoColor=white)

[한국어](#한국어) · [English](#english)

</div>

---

<a id="한국어"></a>

## 🇰🇷 한국어

**sessionbar**는 여러 터미널에서 실행한 Codex CLI 세션을 macOS 메뉴 막대 한곳에서 확인하는 네이티브 앱입니다.

### ✨ 기능

- 메뉴 막대에서 세션 수와 상태를 빠르게 확인
- 프로젝트 경로, 세션 제목, 마지막 활동 시각 확인
- 실행 추정·유휴 추정·완료·상태 불명 표시
- 작업 완료·오류 알림, 조용한 시간대 및 1시간 일시 중지
- 최근 활동과 최신 Codex 응답을 별도 크기 조절 창에서 확인
- 완료·유휴 세션 보관 기간과 자동 새로고침 간격 설정
- 프로젝트 폴더 열기, 세션 ID 및 재개 명령 복사
- 기본 15초 간격 자동 새로고침 및 수동 새로고침

### 🛠️ 빌드

macOS 14 이상과 Swift 5.9 이상이 필요합니다.

```sh
swift build
```

---

<a id="english"></a>

## 🇺🇸 English

**sessionbar** is a native macOS menu bar app for viewing Codex CLI sessions running across multiple terminals.

### ✨ Features

- Check session counts and status from the menu bar
- View project paths, session titles, and last activity
- Show running estimates, idle estimates, completed sessions, errors, and unknown status
- Configure completion and error notifications, quiet hours, and a one hour pause
- Open recent activity and the latest Codex response in a resizable window
- Set retention for completed and idle sessions, and choose the refresh interval
- Open the project folder, or copy the session ID and resume command
- Refresh every 15 seconds by default or on demand

### 🛠️ Build

Requires macOS 14 or later and Swift 5.9 or later.

```sh
swift build
```

