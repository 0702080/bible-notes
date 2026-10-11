# CLAUDE.md — 말씀 묵상 노트 프로젝트 안내 (Claude Code용)

이 폴더는 GitHub Pages로 배포하는 정적 웹앱 세 개입니다. 사용자는 한국어로 소통하며, 답변과 화면 글자는 모두 한국어로 씁니다.

## 구성
- `index.html` — 말씀 묵상 노트 (HTML, CSS, JS가 한 파일에 모두 들어 있음, 빌드 도구 없음)
- `pilsa/index.html` — 요한복음 필사 진도표
- `pilsa/print-progress-sheet.pdf` — 인쇄용 진도표
- `tongdok/index.html` — 성경 통독표 (66권 1189장 체크, 두 사람 진도 비교)
  - 저장 키는 `bible-tongdok-v1`. 다른 앱과 겹치지 않게 따로 씁니다.
  - 비교는 서버 없이 합니다. 1189장을 비트로 눌러 담아 base64 코드로 만들고
    링크(`#f=...`)로 주고받습니다. 불러온 친구 진도는 보기 전용이라
    내 체크를 덮어쓰지 않습니다.
  - 권 이름과 장 수만 쓰고 성경 본문은 담지 않습니다.
- `manifest.json`, `icon-192.png`, `icon-512.png` — 홈 화면에 추가하면 주소창 없이 전체 화면으로 열리게 함 (브라우저 전체 화면 API는 안내 문구가 떠서 쓰지 않음 — 사용자가 주소창이 보이는 쪽을 고름)
- `.nojekyll` — GitHub Pages가 파일을 그대로 쓰게 하는 표시

## 꼭 지킬 것
- **한 파일 구조 유지**: CSS와 JS는 `index.html` 안에 둡니다. 외부 라이브러리나 빌드 단계를 추가하지 않습니다.
- **모바일 우선**: 안드로이드 갤럭시에서 주로 씁니다. 화면 폭 360~430px에서 버튼이 줄바꿈되지 않는지 확인합니다.
- **검정 테마**: 색은 `:root`의 변수(`--violet`, `--orange`, `--gold`, `--green`, `--sky`, `--pink` 등)를 씁니다.
- **글꼴**: 빙그레체(Binggrae, 눈누 CDN @font-face)를 쓰고, 받기 전·PDF 저장에는 Noto Sans KR을 씁니다 (2026-10-10 사용자 요청으로 변경).
- **모든 버튼은 진동**: 전역 click 리스너가 `buzz()`를 부릅니다. 새 버튼도 `<button>`으로 만들면 자동 적용됩니다.
- **클래스 이름 충돌 주의**: `.pop`은 메뉴 팝업 클래스입니다. 애니메이션용으로 `pop`, `uagain`, `umanual`, `usave`, `ucancel` 같은 기존 클래스 이름을 다른 뜻으로 재사용하지 않습니다.
- **저장**: claude.ai 밖에서는 `localStorage`에 저장됩니다. 노트 데이터 모양은 `cleanNote()`가 정합니다. 새 필드를 추가하면 `cleanNote()`에도 넣어야 저장됩니다.
- **성경 본문 저작권**: 개역개정 본문을 앱에 통째로 넣지 않습니다. 사용자가 담은 구절만 저장합니다.

## claude.ai 전용 기능 (여기서는 꺼짐)
`window.claude.use("db" | "user" | "sample" | "downloads" | "assets")`는 claude.ai 아티팩트에서만 있습니다. 이 저장소에서는 없으므로 앱이 자동으로 이 기기 저장 모드가 되고, Claude가 필요한 기능(말씀 찾기, 추천, 문장 분석, 그림, 질문 만들기, 기억법 받기)은 숨겨집니다.
- 이 기능들을 살리려면 API 키를 `index.html`에 넣지 말고, Cloudflare Workers 같은 작은 서버를 두어 Anthropic API를 부르게 합니다. `sampleFn.json(prompt, opts)`를 그 서버 호출로 바꾸면 됩니다.

## 주요 코드 위치 (index.html 안에서 검색)
- `function cleanNote(` — 데이터 형식
- `function render(` / `function updateCard(` — 카드 그리기
- `/* ---------- 말씀 암송 ---------- */` — 암송 단계(MEMSTEPS), 도장(STAMP)
- `/* ---------- 가리기: 전체 화면 연습 ---------- */` — 단계별/전부 가리기, 음성 읽기
- `/* ---------- 질문으로 외우기` — 질문 사다리
- `/* ---------- 묵상 진도표` — 달력, 묵상 배지(MBADGE)
- `/* ---------- 가리기 연습 배지` — 암송 게임판(DBADGE, DMEDAL)
- `function renderReviewBar(` — 첫 화면의 "오늘" 카드
- `/* ---------- 백업 저장 / 불러오기` — JSON 백업

## 확인 방법
- 로컬 실행: `python -m http.server 8000` 후 http://localhost:8000
- 고친 뒤에는 브라우저 개발자 도구에서 휴대폰 화면(390px)으로 열어 오류가 없는지 봅니다.

## 배포
- `main` 브랜치에 푸시하면 GitHub Pages가 1~2분 뒤 반영합니다.
- 사용자는 항상 GitHub 주소(https://0702080.github.io/bible-notes/)에서 씁니다. 고친 뒤에는 푸시하고 그 주소에서 직접 확인합니다.
- `index.html`을 고칠 때마다 `<meta name="app-build" content="...">` 값을 바꿉니다. 열려 있는 브라우저가 예전 파일을 쓰고 있으면 이 값을 보고 한 번 새로고침합니다.
- 커밋 메시지는 한국어로 짧게 씁니다. 예: `암송 5단계를 내일 다시 외우기로 변경`
