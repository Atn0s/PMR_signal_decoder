function cfg = config()
%CONFIG DMR protocol defaults copied from the Python DMRConfig.
cfg = struct();
cfg.targetSampleRateHz = 48000.0;
cfg.symbolRateHz = 4800.0;
cfg.samplesPerSymbol = 10;
cfg.frontendCutoffHz = 9500.0;
cfg.frontendTaps = 151;
cfg.frontendMinSamples = 512;
cfg.frontendPsdNperseg = 4096;
cfg.nominalDeviationHz = 1944.0;
cfg.syncThresholdVoice = 0.68;
cfg.syncThresholdData = 0.55;
cfg.syncPeakDistanceSamples = 800;
cfg.voiceBurstStrideSamples = 2880;
cfg.voiceBurstCount = 6;
cfg.burstDedupWindowSamples = 50;
cfg.dedupFrequencyBucketHz = 5000.0;
end

