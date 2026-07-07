function cfg = config()
%CONFIG dPMR protocol defaults copied from Python DPMRConfig.
cfg = struct();
cfg.targetSampleRateHz = 48000.0;
cfg.symbolRateHz = 2400.0;
cfg.samplesPerSymbol = 20;
cfg.frontendCutoffHz = 3500.0;
cfg.frontendTaps = 151;
cfg.frontendMinSamples = 512;
cfg.frontendPsdNperseg = 4096;
cfg.nominalDeviationHz = 1050.0;
cfg.syncThreshold = 0.82;
cfg.syncMaxSymbolErrors = 0;
cfg.syncMinDistanceSamples = 1200;
cfg.syncDedupWindowSymbols = 3;
cfg.dedupFrameBucketSamples = 3840;
cfg.stableColorMinRepeats = 2;
end

