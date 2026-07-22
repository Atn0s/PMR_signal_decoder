function cfg = config()
%CONFIG P25 Phase 1 protocol defaults.
cfg = struct();
cfg.targetSampleRateHz = 48000.0;
cfg.symbolRateHz = 4800.0;
cfg.samplesPerSymbol = 10;
cfg.frontendCutoffHz = 9500.0;
cfg.frontendTaps = 151;
cfg.frontendMinSamples = 512;
cfg.frontendPsdNperseg = 4096;
cfg.nominalDeviationHz = 1944.0;
cfg.syncThreshold = 0.62;
cfg.syncMinDistanceSymbols = 120;
cfg.stableNacMinCount = 5;
cfg.stableNacMinRatio = 0.4;
cfg.lduSymbols = 864;
cfg.dedupFrameBucketSamples = 8640;
cfg.streamDcTimeConstantSec = 0.25;
cfg.streamFrequencyEstimateSec = 1.0;
cfg.streamFlushPaddingSec = 0.010;
cfg.streamMaxPendingInvalidFrames = 64;
end
