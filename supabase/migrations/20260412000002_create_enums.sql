-- Organization/Team/Project member roles
CREATE TYPE org_role AS ENUM ('owner', 'admin', 'member');
CREATE TYPE team_role AS ENUM ('lead', 'member');
CREATE TYPE project_role AS ENUM ('lead', 'member', 'viewer');

-- Task
CREATE TYPE task_status AS ENUM ('todo', 'in_progress', 'review', 'done');
CREATE TYPE task_priority AS ENUM ('low', 'medium', 'high', 'urgent');
CREATE TYPE task_assignee_role AS ENUM ('owner', 'contributor', 'reviewer');

-- Meeting
CREATE TYPE meeting_status AS ENUM ('planned', 'recording', 'processed');
CREATE TYPE attendance_status AS ENUM ('invited', 'attended', 'absent');

-- Project
CREATE TYPE project_status AS ENUM ('planning', 'active', 'on_hold', 'done');

-- Knowledge
CREATE TYPE knowledge_source AS ENUM ('uploaded', 'meeting', 'auto_generated');
CREATE TYPE chunk_source_type AS ENUM ('document', 'meeting_minutes', 'transcript', 'task', 'decision');

-- Agent
CREATE TYPE agent_message_role AS ENUM ('user', 'assistant', 'system', 'tool');
CREATE TYPE agent_scope AS ENUM ('user', 'project');
CREATE TYPE reflection_type AS ENUM ('status_summary', 'blocker', 'pattern', 'preference');
