function [pdus, diagnostics, frequencyOffsetHz, timingState] = ...
        fakeHealthLossDecoder(protocol, snapshot)
%FAKEHEALTHLOSSDECODER Lose strong evidence permanently at sample 500.
if snapshot.sourceSampleEnd < uint64(500)
    [pdus, diagnostics, frequencyOffsetHz, timingState] = ...
        tests.fakeLockedDecoder(protocol, snapshot);
else
    pdus = struct([]);
    diagnostics = struct();
    frequencyOffsetHz = 0;
    timingState = struct();
end
end
