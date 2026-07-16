function [pdus, diagnostics, frequencyOffsetHz, timingState] = ...
        fakeEmptyLockedDecoder(~, ~)
%FAKEEMPTYLOCKEDDECODER Deterministic no-PDU decoder for flow-control tests.
pdus = struct([]);
diagnostics = struct();
frequencyOffsetHz = 0;
timingState = struct();
end
