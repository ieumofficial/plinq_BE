-- Meeting
CREATE TABLE public.meetings (
    id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    project_id      uuid NOT NULL REFERENCES public.projects(id) ON DELETE CASCADE,
    name            text NOT NULL,
    scheduled_at    timestamptz NOT NULL,
    duration_min    int NOT NULL DEFAULT 60,
    location_or_url text,
    status          meeting_status NOT NULL DEFAULT 'planned',
    created_by      uuid NOT NULL REFERENCES public.users(id) ON DELETE RESTRICT,
    created_at      timestamptz NOT NULL DEFAULT now()
);

-- Task.source_meeting_id FK 추가 (이제 meetings 테이블이 있으므로)
ALTER TABLE public.tasks
    ADD CONSTRAINT fk_tasks_source_meeting
    FOREIGN KEY (source_meeting_id) REFERENCES public.meetings(id) ON DELETE SET NULL;

-- MeetingAttendee
CREATE TABLE public.meeting_attendees (
    meeting_id  uuid NOT NULL REFERENCES public.meetings(id) ON DELETE CASCADE,
    user_id     uuid NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
    attendance  attendance_status NOT NULL DEFAULT 'invited',
    PRIMARY KEY (meeting_id, user_id)
);

-- MeetingAgenda
CREATE TABLE public.meeting_agendas (
    id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    meeting_id      uuid NOT NULL REFERENCES public.meetings(id) ON DELETE CASCADE,
    "order"         int NOT NULL DEFAULT 0,
    title           text NOT NULL,
    summary         text, -- 회의 후 Agent가 transcript에서 추출한 요약
    generated_by_ai boolean NOT NULL DEFAULT false
);

-- MeetingMinutes (1:1 with Meeting)
CREATE TABLE public.meeting_minutes (
    id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    meeting_id      uuid NOT NULL UNIQUE REFERENCES public.meetings(id) ON DELETE CASCADE,
    raw_audio_url   text,
    summary         text,
    full_text       text,
    processed_at    timestamptz
);

-- TranscriptSegment
CREATE TABLE public.transcript_segments (
    id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    meeting_id  uuid NOT NULL REFERENCES public.meetings(id) ON DELETE CASCADE,
    speaker_id  uuid REFERENCES public.users(id) ON DELETE SET NULL,
    start_time  real NOT NULL,
    end_time    real NOT NULL,
    text        text NOT NULL
);

CREATE INDEX idx_transcript_segments_meeting ON public.transcript_segments(meeting_id, start_time);

-- MeetingDecision
CREATE TABLE public.meeting_decisions (
    id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    meeting_id  uuid NOT NULL REFERENCES public.meetings(id) ON DELETE CASCADE,
    content     text NOT NULL,
    decided_by  uuid REFERENCES public.users(id) ON DELETE SET NULL,
    created_at  timestamptz NOT NULL DEFAULT now()
);
