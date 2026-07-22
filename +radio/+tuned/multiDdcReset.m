function state = multiDdcReset(state)
%MULTIDDCRESET Clear one live epoch before the next retarget operation.
% multiDdcRetarget resets the converter once, immediately before reuse.
state.pendingIq = complex(zeros(0, 1));
state.pendingSourceSampleStart = uint64(0);
state.expectedInputSample = [];
state.nextOutputSample = uint64(0);
state.nextSequenceNumber = uint64(0);
state.continuityGeneration = state.continuityGeneration + uint64(1);
state.inputSamplesReceived = uint64(0);
state.inputSamplesConverted = uint64(0);
state.outputSamplesProduced = uint64(0);
state.feedCount = uint64(0);
state.mixerPhases = complex(ones(1, state.capacity));
end
