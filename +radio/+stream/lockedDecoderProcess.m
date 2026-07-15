function [state, output] = lockedDecoderProcess(state, buffer)
%LOCKEDDECODERPROCESS Compatibility wrapper for incremental locked decode.
input = radio.stream.lockedDecoderPrepareInput(state, buffer);
[state, output] = radio.stream.lockedDecoderProcessChunk(state, input);
end
