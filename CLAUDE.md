# PLOW Backend — 데이터 모델 가이드

> PLOW의 백엔드 데이터 모델 정의. 이 문서는 백엔드 개발 시 스키마·관계·핵심 설계 결정의 단일 진실 출처(SSOT) 역할을 함. 전체 ERD 다이어그램은 상위 폴더의 `pm-agent-erd.md` 참고.

## 기술 스택 & 통신 구조

- **DB/BaaS**: Supabase (PostgreSQL + pgvector + Auth + Storage + Realtime + RLS)
- **AI 서버**: plow_ai — Python FastAPI
- **LLM**: Claude API (Haiku 4.5 / Sonnet 4.6 / Opus 4.6)
- **STT**: Whisper 또는 Deepgram
- **Embedding**: OpenAI text-embedding-3-small

```
plow_fe (Electron) ──supabase-js──→ Supabase (Auth, CRUD, Realtime, Storage)
                    ──REST API────→ plow_ai (FastAPI) ──asyncpg──→ PostgreSQL 직접 연결
```

**통신 규칙:**
- plow_fe → Supabase: `supabase-js` SDK로 CRUD, Auth, Realtime 구독. 별도 API 서버 불필요
- plow_ai → DB: `asyncpg`로 PostgreSQL 직접 연결 (벡터 검색, 트랜잭션, 복잡한 파이프라인). supabase-py는 사용하지 않고 asyncpg로 통일
- 권한 격리: Supabase RLS (프론트), `service_role` key는 plow_ai 서버에만

**LLM 모델 배치:**

| 모델 | 용도 |
|---|---|
| Haiku 4.5 | 화자 분류, Task 태깅, 키워드 추출 등 가볍고 반복적인 작업 |
| Sonnet 4.6 | 회의록 요약, Decision 추출, Agenda summary 생성, Agent 챗, Task/assignee 추천 (메인 모델) |
| Opus 4.6 | AgentReflection 생성 등 프로젝트 전체 맥락 종합이 필요한 작업 (저빈도) |

## 핵심 설계 결정 (반드시 숙지)

1. **Subtask는 별도 테이블이 아님** — `Task.parent_task_id`로 self-reference. `NULL`이면 top-level task, 값이 있으면 subtask.
2. **Task assignee는 다대다** — `TaskAssignee` 매핑 테이블 사용. `role` 필드(owner/contributor/reviewer)로 역할 구분.
3. **Calendar는 Task + Meeting UNION** — 별도 `CalendarEvent` 테이블 **없음**. 모든 일정은 Task 또는 Meeting으로 저장되고, 캘린더 화면은 두 테이블을 UNION으로 조회. Task는 `project_id`와 `team_id`를 둘 다 nullable FK로 가지며, CHECK constraint로 "둘 중 하나만 set 또는 둘 다 NULL(개인)" 보장.
4. **회의에서 생성된 task는 추적 가능** — `Task.source_meeting_id`로 원본 회의 연결.
5. **벡터 데이터는 통합 인덱싱** — 모든 텍스트성 콘텐츠(document, meeting_minutes, transcript, task, decision)를 단일 `KnowledgeChunk` 테이블에 저장하고 `source_type`으로 구분.
6. **DB**: Supabase managed PostgreSQL + pgvector. plow_fe는 supabase-js, plow_ai는 asyncpg로 접근.

## 도메인 계층

```
Organization → Team → Project → Task → Subtask(=Task with parent_task_id)
                                   ↓
                              TaskAssignee (다대다)
```

Group이라는 중간 단위는 **존재하지 않음**. 사람은 Project에 속하고, 작업 단위(Task)에 직접 할당됨.

## 엔티티 정의

### 조직/사람

#### User
- `id` (uuid, PK)
- `email` (unique) — 로그인 ID
- `password_hash` — bcrypt/argon2로 해시. 절대 평문 저장 금지. 보안 강화 시 별도 `UserCredential` 테이블로 분리 가능
- `first_name` — 성
- `last_name` — 이름
- `nickname` — 표시명/멘션용. 유니크는 아님 (동일 닉네임 허용)
- `job_title` — 직책 (예: "Front-end Developer"). **권한 role과 다른 개념** — 권한 role은 OrganizationMember/TeamMember/ProjectMember에 있는 enum이고, 이건 자유 텍스트 직책
- `language` — UI 언어 (기본 `ko`)
- `notification_settings` (jsonb)
- `created_at`

**회원가입 폼 매핑**: First Name → `first_name`, Last Name → `last_name`, Nickname → `nickname`, Role → `job_title`, Email → `email`, Password → `password_hash` (해싱 후 저장), Confirm Password → 검증만 하고 저장하지 않음.

#### Organization
- `id`, `name`, `owner_id` → User, `created_at`

#### OrganizationMember
- `org_id`, `user_id` → User
- `role` enum: `owner | admin | member`
- `permissions` (jsonb) — empowerment 매트릭스 (RBAC 확장 시 별도 테이블로 분리)
- `joined_at`

#### Team
- `id`, `org_id`, `name`, `description`

#### TeamMember
- `team_id`, `user_id`, `role`

#### Project
- `id`
- `team_id` (FK, **nullable**) — team에 속하지 않는 독립 프로젝트 허용. 개인 프로젝트, 조직 레벨 TF 등 팀 단위가 없는 경우
- `name`, `description`
- `lead_id` → User
- `status` enum: `planning | active | on_hold | done`
- `budget` (decimal, nullable) — 프로젝트 예산. 통화 단위는 Organization 설정 또는 별도 currency 컬럼으로 확장 가능
- `created_at`

**team_id nullable의 의미**: User가 어떤 TeamMember에도 속하지 않고도 Project에 참여 가능 (ProjectMember만 있어도 됨). 따라서 "team 없는 user"도 자연스럽게 허용됨.

#### ProjectMember
- `project_id`, `user_id`, `role`

### 작업

#### Task
- `id` (uuid, PK)
- `project_id` (FK → Project, **nullable**) — NULL이면 프로젝트에 속하지 않음
- `team_id` (FK → Team, **nullable**) — NULL이면 팀 직속도 아님
- `parent_task_id` (FK → Task.id, **nullable**) — subtask 표현용 self-reference
- `title`, `description`
- `status` enum: `todo | in_progress | review | done`
- `priority` enum: `low | medium | high | urgent`
- `start_date`, `due_date`
- `kanban_column_id` (FK, nullable) — 칸반 컬럼 매핑 (없으면 status enum으로 fallback)
- `created_by` (FK → User)
- `source_meeting_id` (FK → Meeting, **nullable**) — 회의에서 자동 생성된 task일 때만 채워짐
- `created_at`, `updated_at`

**Scope 규칙** (DB CHECK constraint 필수):

| `project_id` | `team_id` | 의미 |
|---|---|---|
| NULL | NULL | **개인 task/이벤트** — assignee만 존재 |
| NULL | 값 있음 | **팀 직속 task/이벤트** — 특정 프로젝트 없음 |
| 값 있음 | NULL | **프로젝트 task** — team은 `Project.team_id`로 추적 |
| 값 있음 | 값 있음 | ❌ 금지 |

```sql
ALTER TABLE task ADD CONSTRAINT task_scope_xor
    CHECK (NOT (project_id IS NOT NULL AND team_id IS NOT NULL));
```

**쿼리 패턴**:
- 프로젝트 칸반: `WHERE project_id = ? AND parent_task_id IS NULL`
- 팀 직속 task: `WHERE team_id = ? AND project_id IS NULL`
- 개인 task: `WHERE project_id IS NULL AND team_id IS NULL AND id IN (SELECT task_id FROM TaskAssignee WHERE user_id = ?)`
- Subtask 트리: recursive CTE 또는 `WHERE parent_task_id = ?`
- subtask의 due_date는 부모의 due_date를 넘지 못하도록 application-level validation 권장
- subtask의 scope(project_id/team_id)는 부모와 일치해야 함 (application 검증)

#### TaskAssignee
- `task_id` (FK)
- `user_id` (FK)
- `role` enum: `owner | contributor | reviewer`
- `assigned_by` (FK → User)
- `assigned_at`
- PK: `(task_id, user_id)` (한 사람에게 하나의 role만)

#### KanbanColumn
- `id`, `project_id`, `name`, `order`

### 캘린더

**별도 CalendarEvent 테이블 없음.** 모든 "일정"은 `Task` 또는 `Meeting` 중 하나로 저장되고, 캘린더 UI는 두 테이블을 UNION으로 조회해서 보여줌.

**캘린더별 조회 쿼리 예시**:

```sql
-- 개인 캘린더 (user_id = :uid, 기간 :from ~ :to)
SELECT 'task' as type, t.id, t.title, t.start_date as start_at, t.due_date as end_at
FROM Task t
JOIN TaskAssignee ta ON ta.task_id = t.id
WHERE ta.user_id = :uid AND t.due_date BETWEEN :from AND :to
UNION ALL
SELECT 'meeting', m.id, m.name, m.scheduled_at,
       m.scheduled_at + (m.duration_min * INTERVAL '1 minute')
FROM Meeting m
JOIN MeetingAttendee ma ON ma.meeting_id = m.id
WHERE ma.user_id = :uid AND m.scheduled_at BETWEEN :from AND :to;

-- 프로젝트 캘린더 (project_id = :pid)
SELECT 'task' as type, t.id, t.title, t.start_date, t.due_date
FROM Task t WHERE t.project_id = :pid
UNION ALL
SELECT 'meeting', m.id, m.name, m.scheduled_at,
       m.scheduled_at + (m.duration_min * INTERVAL '1 minute')
FROM Meeting m WHERE m.project_id = :pid;

-- 팀 캘린더 (team_id = :tid) — 팀 직속 task + 팀 하위 프로젝트의 task/meeting
SELECT 'task' as type, t.id, t.title, t.start_date, t.due_date
FROM Task t
WHERE t.team_id = :tid
   OR t.project_id IN (SELECT id FROM Project WHERE team_id = :tid)
UNION ALL
SELECT 'meeting', m.id, m.name, m.scheduled_at,
       m.scheduled_at + (m.duration_min * INTERVAL '1 minute')
FROM Meeting m
WHERE m.project_id IN (SELECT id FROM Project WHERE team_id = :tid);

-- 조직 캘린더 = 조직 산하 모든 팀 캘린더의 UNION (별도 org scope 없음)
```

**예외 처리**:
- **조직 전체 이벤트 (all-hands, 워크샵)**: `Meeting`으로 모델링 (attendees에 전원 포함)
- **공휴일**: DB에 저장하지 않음. 외부 캘린더 구독(Google Calendar)으로 처리. 필요 시 추후 `Holiday` 테이블 추가
- **휴가 같은 개인 장기 일정**: 개인 task로 저장 (`project_id=NULL, team_id=NULL`)

**Task.status의 어색함**: "휴가" 같은 이벤트성 task에 `todo/doing/done`이 어색하지만 MVP에선 그대로 사용. 칸반엔 top-level task만 노출되므로 사용자 혼란 최소. 추후 `Task.kind` enum(`work | event`) 도입 검토 가능.

### 회의

#### Meeting
- `id`, `project_id`, `name`
- `scheduled_at`, `duration_min`
- `location_or_url`
- `status` enum: `planned | recording | processed`
- `created_by`, `created_at`

#### MeetingAttendee
- `meeting_id`, `user_id`
- `attendance` enum: `invited | attended | absent`

#### MeetingAgenda
- `id`, `meeting_id`, `order`
- `title` — 안건 제목 (회의 전 사용자 입력 또는 AI 추천)
- `summary` (text, nullable) — 회의 후 Agent가 transcript에서 해당 안건 관련 논의를 추출·요약. 회의 전에는 NULL
- `generated_by_ai` (bool) — title이 AI 추천인지 여부

#### MeetingMinutes
- `id`, `meeting_id` (1:1), `raw_audio_url`
- `summary` (AI 생성), `full_text`
- `processed_at`

#### TranscriptSegment
- `id`, `meeting_id`
- `speaker_id` → User (화자 분리 결과)
- `start_time`, `end_time` (float, 초 단위)
- `text`

#### MeetingDecision
- `id`, `meeting_id`
- `content`
- `decided_by` → User
- `created_at`

> Decision은 회의 처리 시 LLM이 transcript에서 추출. agent 추론에 매우 중요하므로 별도 엔티티로 관리.

### 지식베이스 (벡터)

#### KnowledgeDocument
- `id`, `project_id`, `name`, `file_url`, `file_type`
- `source` enum: `uploaded | meeting | auto_generated`
- `uploaded_by`, `uploaded_at`

#### KnowledgeChunk (pgvector)
- `id`
- `project_id` (denormalized — 필터링 성능)
- `source_type` enum: `document | meeting_minutes | transcript | task | decision`
- `source_id` (uuid) — source_type에 따라 다른 테이블의 id
- `chunk_text`
- `embedding` (vector)
- `metadata` (jsonb) — speaker, date, tags 등 검색 보조
- `created_at`

**임베딩 갱신 정책**:

| source_type | 트리거 |
|---|---|
| document | KnowledgeDocument INSERT 시 |
| meeting_minutes | Meeting.status = 'processed' 전환 시 |
| transcript | Meeting.status = 'processed' 전환 시 |
| task | Task INSERT/UPDATE (title 또는 description 변경 시) |
| decision | MeetingDecision INSERT 시 |

### 에이전트

**PLOW에는 두 종류의 Agent가 있음:**

#### Personal Agent (`project_id IS NULL` 인 AgentConversation)
- **Scope**: user 본인 참여 **모든** 프로젝트 + **개인 task**(`project_id=NULL, team_id=NULL`)를 cross로 봄
- **주 기능**: today's to-do 생성 (priority + due_date 정렬), 일정 요약, 개인 비서 챗
- **메모리**: `AgentReflection WHERE scope='user' AND scope_id=user_id`
- **개인 task 격리**: 개인 task는 어떤 프로젝트 `KnowledgeChunk`에도 임베딩되지 않음 → Project Agent는 못 보고 Personal Agent만 접근 가능

#### Project Agent (`project_id` 값 있는 AgentConversation)
- **Scope**: 단일 project_id로 완전 격리. 다른 프로젝트 데이터는 절대 참조 불가
- **주요 역할**:
  - **평상시**
    - Task/assignee 추천 (knowledge base + 과거 TaskAssignee 이력 기반)
    - 프로젝트 QnA ("저번 결정사항 뭐였지?", "지금 어디까지 됐지?")
    - Blocker 감지 (review 장기 정체, due_date 임박)
    - 자동 문서 생성 (system architecture, flow chart 등을 `KnowledgeDocument.source='auto_generated'`로 저장)
  - **회의 전**
    - 프로젝트 현재 상태 종합하여 agenda 초안 생성 (`MeetingAgenda.generated_by_ai=true`)
    - 참석자 추천 (project member + 과거 유사 회의 참석자 분석)
  - **회의 중** (plow_ai 파이프라인 담당)
    - 녹음 → STT → 화자 분리 → `TranscriptSegment` 생성
  - **회의 후**
    - `MeetingMinutes.summary` 생성
    - `MeetingDecision` 추출
    - Task 후보 제안 → admin 승인 시 `source_meeting_id` 채워 Task INSERT (due_date 포함)
    - 후속 회의 제안 → Meeting INSERT 제안
- **메모리**: `AgentReflection WHERE scope='project' AND scope_id=project_id`

**원칙**: 같은 사용자가 여러 프로젝트에 참여해도 Project Agent는 각 project별로 독립 인스턴스처럼 동작. project_id 스코프 누수 금지.

**대화 프라이버시 (per-user private)**: Project Agent 대화는 MVP에서 **완전히 개인별 격리**. 같은 프로젝트여도 사용자 A와 B의 대화는 서로 볼 수 없음. API는 항상 `WHERE user_id = current_user_id AND project_id = :pid` 조건으로 조회 강제. 팀 공유 대화가 필요하면 추후 `AgentConversation.visibility` enum(`private | shared_project`)을 추가할 수 있으나 현재 스키마로도 확장 가능하므로 MVP 단계에선 추가 컬럼 없이 private-only로 운영.

**공유 가치가 있는 agent 산출물**은 대화 테이블이 아닌 원본 비즈니스 테이블로 바로 저장되어 팀 전체에 자동 공유:
- 회의 요약 → `MeetingMinutes`
- 결정사항 → `MeetingDecision`
- 추천 task → admin 승인 후 `Task` (with `source_meeting_id`)
- 자동 생성 문서 → `KnowledgeDocument` (`source='auto_generated'`)

#### AgentConversation
- `id`
- `user_id` — **대화를 시작한 사람**. Project Agent 대화여도 agent 자체가 아닌 "누가 이 agent와 대화 중인지"를 가리킴
- `project_id` (nullable)
  - `NULL` → Personal Agent 대화 (cross-project 비서)
  - 값 있음 → Project Agent 대화 (해당 project로 스코프 격리)
- `title`, `created_at`

**user_id와 project_id의 관계**: 두 필드는 서로 다른 차원.
- `project_id`: agent가 어느 프로젝트 컨텍스트로 작동하는지 (RAG 필터, 권한 스코프)
- `user_id`: 그 컨텍스트로 누구와 대화 중인지 (발화자, 권한 주체)

같은 프로젝트에 여러 유저가 각자 대화를 시작하면 conversation row가 user별로 분리됨. 권한 체크는 `ProjectMember(project_id, user_id)` 존재 여부로.

#### AgentMessage
- `id`, `conversation_id`
- `role` enum: `user | assistant | system | tool`
- `content`, `tokens_used`, `created_at`

**role 값별 의미** (LLM API 메시지 프로토콜 기준):

| role | 의미 | 저장 내용 예시 |
|---|---|---|
| `user` | 사람의 입력 | "이번 주 내 task 정리해줘" |
| `assistant` | LLM(에이전트) 응답 | "이번 주 완료 task 3개, 진행 중 5개입니다..." |
| `system` | LLM에게 주는 **지시문/페르소나/컨텍스트**. 사람에게는 안 보이지만 LLM이 대화 시작 시 읽는 규칙 | "당신은 Project X의 전담 에이전트입니다. 현재 상태: [status_summary]. 활성 블로커: [blocker]. 사용 가능 도구: create_task, ..." |
| `tool` | LLM이 호출한 function/tool의 **실행 결과** | "create_task({...}) → Task #456 생성됨" |

- `system`은 보통 대화 맨 앞에 1개만 있음. 프로젝트 상태가 바뀌면 새 system 메시지로 rebuild 또는 append.
- `tool`은 function calling을 사용할 때 LLM ↔ 시스템 간 이중 왕복을 기록 (LLM이 tool 호출을 요청 → 시스템이 실행 → 결과를 `tool` 메시지로 LLM에 돌려줌).

#### AgentReflection
- `id`
- `scope` enum: `user | project`
- `scope_id`
- `reflection_type` enum: `status_summary | blocker | pattern | preference`
- `content`
- `embedding` (vector)
- `importance` (float, 0~1)
- `valid_from` (timestamp)
- `created_at`

**reflection_type 상세**:

| type | 의미 | 내용 예시 | 주입 시점 | 생성 주기 |
|---|---|---|---|---|
| `status_summary` | 프로젝트/사용자의 현재 상태 요약 | "Project X는 디자인 90% 완료, 백엔드 API 설계 중. 이번 주 목표는 인증 MVP." | 모든 대화 시작 시 system prompt에 주입 | 매일 자정 + 회의 처리 직후 |
| `blocker` | 진행을 막고 있는 것 | "Task #123 'API 명세 확정'이 4일째 review 상태. 담당: A, 리뷰어: B" | 회의 agenda 생성 시, 사용자가 "뭐 막혀있어?" 질문 시 | Task status 모니터링 cron, due_date 임박 감지 |
| `pattern` | 반복 관찰된 팀/프로젝트의 행동 경향 | "이 팀은 월요일 회의가 평균 90분으로 가장 김", "금요일 task 완료율 +40%" | Agent가 제안할 때 근거로 사용 | 주간 cron |
| `preference` | 사용자 개인의 취향/습관 | "사용자 A는 오전 task 생성 선호, 회의는 오후 2시 이후", "불렛보다 문장형 답변 선호" | Personal Agent 대답 시, agenda/일정 추천 시 | 대화 이력 주기적 분석 |

**왜 네 타입으로 분리:**
- 각 타입이 **retrieval 시점과 주입 위치가 다름** (status_summary는 항상, blocker는 즉시 알림, pattern은 배경지식, preference는 개인화)
- Importance 가중치 정책이 타입별로 다름 (blocker는 최신만, pattern은 오래 유지)
- 타입 없이 단일 텍스트로 저장하면 "이 reflection을 언제 어디에 쓸지" 판단이 어려워짐

**Reflection 생성 트리거**:
- 회의 처리 직후 (해당 project)
- Task status 대량 변경 시
- 매일 자정 cron (active project 전체)
- 사용자가 명시적으로 요청 시

오래된 reflection은 삭제하지 않고 `importance`를 낮춰 retrieval 시 weight down.

## Agent 메모리 4계층 (백엔드 구현 관점)

| Layer | 저장소 | 조회 방법 |
|---|---|---|
| Working | `AgentMessage` | conversation_id로 직전 N개 SELECT |
| Episodic | 비즈니스 RDB 테이블 | SQL JOIN (Meeting, Decision, Task 등) |
| Semantic | `KnowledgeChunk` | pgvector cosine similarity + project_id 필터 |
| Reflective | `AgentReflection` | scope/scope_id + reflection_type 필터, importance 정렬 |

## Agent 컨텍스트 조립 흐름 (예시: "내일 회의 안건 만들어줘")

```
1. Identity 확인
   - user_id, project_id 추출
   - ProjectMember 권한 체크
2. Episodic 조회
   - 최근 5개 MeetingMinutes (project_id 필터)
   - 미해결 Task (status != done)
   - 최근 MeetingDecision 10개
3. Semantic 조회 (Vector)
   - "회의 안건 + 프로젝트 현재 상태"로 임베딩
   - top-K KnowledgeChunk, project_id 필터
   - source_type 가중치: decision > meeting_minutes > document > task
4. Reflective 조회
   - 최신 status_summary, 활성 blocker
5. Working memory
   - 같은 conversation의 직전 메시지 N개
6. LLM 호출
   - System: 역할 + project context summary (from reflection)
   - Tools: create_meeting, suggest_agenda, ...
   - Context: episodic + semantic chunks
```

## API 설계 원칙 (권장)

- 모든 endpoint는 `user_id` + (필요 시) `project_id` 기반 권한 체크 미들웨어 통과
- Multi-tenant 격리: 모든 SELECT는 `WHERE org_id = ?` 또는 동등한 스코프 필터 강제
- 변경 작업은 트랜잭션으로 묶고, 변경 후 관련 KnowledgeChunk 임베딩 비동기 업데이트 (job queue)
- 회의 처리는 별도 워커(plow_ai)에 위임. Meeting.status 전환을 통해 진행 상태 추적

## 마이그레이션 시 고려사항

- `parent_task_id` self-reference는 cascade 삭제 정책 결정 필요 (recommend: ON DELETE CASCADE)
- `KnowledgeChunk`는 source 삭제 시 함께 정리 (또는 nightly cleanup job)
- `Task.source_meeting_id`는 ON DELETE SET NULL (회의가 삭제돼도 task는 보존)
- 인덱스 권장:
  - `Task(project_id, parent_task_id)` — 칸반 쿼리
  - `Task(project_id, status)` — 진행 상황 집계
  - `TaskAssignee(user_id)` — 개인 to-do 조회
  - `KnowledgeChunk(project_id, source_type)` — RAG 필터링
  - `KnowledgeChunk` HNSW 인덱스 on `embedding` — 벡터 검색

## 결정 완료 항목

- **인증/인가**: Supabase Auth (JWT 기반, RLS로 row-level 권한 제어)
- **파일 스토리지**: Supabase Storage (S3-compatible, 회의 녹음·Knowledge Base 원본·프로필 이미지)
- **DB**: Supabase managed PostgreSQL + pgvector
- **AI 서버 ↔ DB 통신**: asyncpg 직접 연결 (supabase-py 미사용)
- **LLM**: Claude API (Haiku/Sonnet/Opus 작업별 분배)

## TBD / 결정 필요 항목

- Empowerment 권한 매트릭스를 JSON 필드로 둘지 RBAC 테이블로 분리할지
- STT 구체 선택: Whisper API vs Deepgram (비용·정확도·한국어 성능 비교 필요)

## 관련 문서

- `../pm-agent-erd.md` — Mermaid ERD + 상세 설계 문서
- `../CLAUDE.md` — 프로젝트 전체 개요
