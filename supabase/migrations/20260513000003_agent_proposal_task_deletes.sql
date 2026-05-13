-- Destructive proposal kind: task_deletes (agent proposes to delete one
-- or more existing tasks). Apply path issues a single DELETE; FK cascades
-- handle task_assignees + child subtasks (intentional per CLAUDE.md).

ALTER TYPE agent_proposal_kind ADD VALUE IF NOT EXISTS 'task_deletes';
