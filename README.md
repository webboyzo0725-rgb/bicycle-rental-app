# 자전거 대여 관리 시스템

Next.js + Supabase로 만든 모바일 대응 웹앱입니다. 일반 사용자와 관리자 화면이 하나의 프로젝트에 포함되어 있습니다.

## 포함 기능

- 학번/이름 로그인 및 24시간 세션
- 대여 가능 자전거 조회와 대여
- 현재 대여 상태 및 자전거 비밀번호 확인
- 목적지 변경
- 카메라 QR 스캔 반납
- 반납 시 고장 신고, 별도 고장 신고
- 개인 이용/고장 기록
- 관리자 현황판, 학생 제한/해제, 자전거 상태 관리
- 전체 대여 기록 및 누적 고장 기록

## 1. Supabase 설정

1. Supabase 새 프로젝트를 만듭니다.
2. `supabase/database.sql` 전체를 SQL Editor에서 실행합니다.
3. Project Settings의 API 메뉴에서 Project URL과 Publishable Key(또는 anon key)를 복사합니다.

## 2. 환경 변수

`.env.example`을 `.env.local`로 복사하고 값을 입력합니다.

```env
NEXT_PUBLIC_SUPABASE_URL=https://프로젝트.supabase.co
NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY=키
```

## 3. 실행

Node.js 20 이상을 권장합니다.

```bash
npm install
npm run dev
```

브라우저에서 `http://localhost:3000`으로 접속합니다.

테스트 계정:

- 학생: `20240001` / `홍길동`
- 관리자: `admin001` / `관리자`

## 4. Vercel 배포

1. 이 폴더를 GitHub 저장소에 업로드합니다.
2. Vercel에서 저장소를 Import합니다.
3. Environment Variables에 두 Supabase 값을 등록합니다.
4. Deploy를 누릅니다.

QR 카메라는 HTTPS 환경 또는 localhost에서 정상 작동합니다. Vercel 배포 주소는 HTTPS가 자동 적용됩니다.

## 주의

현재 로그인은 학교 과제/시연에 맞춘 `학번 + 이름` 방식입니다. 실제 운영에서는 비밀번호, PIN 또는 Supabase Auth 방식으로 강화하는 것을 권장합니다.


## 최종 DB 구성

이 통합본은 `maintenance_records` 테이블과 정비 관련 RPC를 사용하지 않습니다. 고장 이력은 `fault_records`에 누적되며, 자전거 현재 상태는 `available`, `rented`, `fault`만 사용합니다. 새 Supabase 프로젝트에서는 `supabase/database.sql` 하나만 실행하세요.

## v3 변경사항
- 일반 사용자의 고장 신고는 QR 반납 과정에서만 가능합니다.
- 사용자 하단 네비게이션은 홈, 이용 내역, 고장 신고 내역으로 분리했습니다.
- 반납 시 고장 여부는 미리 선택되지 않으며 사용자가 직접 선택해야 합니다.
- 관리자 현황에서 미처리 고장을 제거하고 총 자전거 수를 추가했습니다.
- 모바일 화면에서는 사용자 네비게이션이 하단 고정형으로 표시됩니다.

## v4 변경사항
- 사용자 자전거 비밀번호 조회 기능을 안정화했습니다.
- 시연용 `10초` 대여 시간을 추가했습니다.
- 기존 Supabase 프로젝트는 `supabase/update_v4.sql`만 실행하세요.
- 새 Supabase 프로젝트는 `supabase/database.sql`만 실행하세요.

## v4.1 비밀번호 표시 수정

비밀번호 확인 시 공통 새로고침 로직 때문에 홈 컴포넌트가 잠시 해제되어 조회 결과가 화면에 표시되지 않던 문제를 수정했습니다. 비밀번호 조회는 별도 RPC로 호출하며 조회 중에는 버튼에 `확인 중...`이 표시됩니다.

## v5 연체 처리 변경

- 연체 횟수는 반납할 때가 아니라 `expected_return_at`을 지난 뒤 Cron이 대여 상태를 `overdue`로 바꾸는 순간 증가합니다.
- Supabase Cron이 10초마다 `refresh_overdue_status()`를 실행합니다.
- 이미 운영 중인 DB에는 `supabase/update_v5.sql`만 실행합니다.
- 새 DB에는 `supabase/database.sql`만 실행합니다.
