-- Enable Supabase Realtime on chat tables so the frontend can subscribe to
-- INSERT/UPDATE events instead of polling. RLS still applies — clients only
-- receive rows they're allowed to read.

ALTER PUBLICATION supabase_realtime ADD TABLE public.chat_messages;
ALTER PUBLICATION supabase_realtime ADD TABLE public.chat_message_reactions;
ALTER PUBLICATION supabase_realtime ADD TABLE public.chat_session_members;
