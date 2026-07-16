function sessions = sessionizePdus(pdus)
%SESSIONIZEPDUS Build DMO session summaries from time-ordered TETRA events.
state = tetra.sessionDecoderInit();
[state, sessions] = tetra.sessionDecoderFeed(state, pdus);
[state, finalSessions] = tetra.sessionDecoderFinalize(state); %#ok<ASGLU>
if isempty(finalSessions), return; end
if isempty(sessions)
    sessions = finalSessions;
else
    sessions(end+1:end+numel(finalSessions)) = finalSessions;
end
sessions = radio.normalizePdus(sessions);
end
