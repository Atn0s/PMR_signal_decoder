function cfg = defaultConfig()
%DEFAULTCONFIG Shared offline radio pipeline defaults.
cfg = struct();
cfg.targetSampleRateHz = 48000.0;
cfg.sampleRateToleranceHz = 1.0;
cfg.psdPeakThresholdDb = 15.0;
cfg.psdNperseg = 4096;
cfg.psdPeakMinDistanceBins = 20;
% Blind search must detect occupied radio channels, not individual FSK
% spectral lines.  A 4.8 kHz energy window groups modulation lobes while
% retaining separate candidates at the standard 6.25 kHz channel spacing.
cfg.psdChannelSmoothingHz = 4800.0;
cfg.psdCandidateMinSpacingHz = 5000.0;
cfg.psdMaxCandidates = inf;
end
