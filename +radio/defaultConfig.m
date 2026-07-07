function cfg = defaultConfig()
%DEFAULTCONFIG Shared offline radio pipeline defaults.
cfg = struct();
cfg.targetSampleRateHz = 48000.0;
cfg.sampleRateToleranceHz = 1.0;
cfg.psdPeakThresholdDb = 15.0;
cfg.psdNperseg = 4096;
cfg.psdPeakMinDistanceBins = 20;
end

