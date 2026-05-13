-- New proposal kind: task_updates (status / priority / due_date / assignee
-- changes proposed by the agent against existing tasks). Items still live
-- in `agent_proposals.items` jsonb; the apply path branches on this kind.

ALTER TYPE agent_proposal_kind ADD VALUE IF NOT EXISTS 'task_updates';
