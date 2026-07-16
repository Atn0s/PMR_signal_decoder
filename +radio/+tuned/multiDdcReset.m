function state = multiDdcReset(state)
%MULTIDDCRESET Reuse one constructed matrix DDC for a new live epoch.
reset(state.converter);
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
