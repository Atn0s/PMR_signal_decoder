function writer = sharedIqRingMarkTerminal(writer, stopped)
%SHAREDIQRINGMARKTERMINAL Publish that no more IQ will be committed.
if nargin < 2, stopped = false; end
writer.mapping.Data.writerStopped = uint32(logical(stopped));
writer.mapping.Data.terminal = uint32(1);
end
