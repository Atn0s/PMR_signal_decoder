function [pdus, diagnostics, frequencyOffsetHz, timingState] = ...
        fakeHealthRecoveryDecoder(protocol, snapshot)
%FAKEHEALTHRECOVERYDECODER Drop evidence for two windows, then recover.
if snapshot.sourceSampleEnd < uint64(500) || ...
        snapshot.sourceSampleEnd >= uint64(700)
    [pdus, diagnostics, frequencyOffsetHz, timingState] = ...
        tests.fakeLockedDecoder(protocol, snapshot);
else
    pdus = struct([]);
    diagnostics = struct();
    frequencyOffsetHz = 0;
    timingState = struct();
end
end
