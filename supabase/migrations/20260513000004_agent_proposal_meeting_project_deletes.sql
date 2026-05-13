-- Two more destructive proposal kinds. Same pattern as task_deletes.
--
-- meeting_deletes:  cascade removes meeting_agendas / attendees / decisions
--                   / minutes / transcript_segments / invites. Source-meeting
--                   FK on tasks is SET NULL so tasks survive.
--
-- project_deletes:  HEAVY. Cascade chain removes ALL of: tasks (+subtasks
--                   +assignees), meetings (+all meeting children), kanban
--                   columns, members, knowledge_documents +chunks, related
--                   agent_conversations and agent_proposals.
--                   The propose handler must surface the impact counts.

ALTER TYPE agent_proposal_kind ADD VALUE IF NOT EXISTS 'meeting_deletes';
ALTER TYPE agent_proposal_kind ADD VALUE IF NOT EXISTS 'project_deletes';
