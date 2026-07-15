function cfg = config()
%CONFIG NXDN96 decoder defaults.
cfg = struct();
cfg.mode = 'NXDN96';
cfg.targetSampleRateHz = 48000.0;
cfg.symbolRateHz = 4800.0;
cfg.samplesPerSymbol = 10;
cfg.frameBits = 384;
cfg.frameSymbols = 192;
cfg.frameSamples = 1920;
cfg.frontendCutoffHz = 6500.0;
cfg.frontendTaps = 151;
cfg.frontendMinSamples = 512;
cfg.frontendPsdNperseg = 4096;
cfg.nominalDeviationHz = 2400.0;
cfg.syncThreshold = 0.70;
cfg.syncMinDistanceSamples = 900;
cfg.syncRefineSamples = 4;
cfg.lichMinFillBits = 7;
cfg.maxFrameCandidates = inf;
cfg.sacchMaxGapFrames = 1;
cfg.dedupFrameBucketSamples = 1920;
cfg.streamDcTimeConstantSec = 0.25;
cfg.streamFlushPaddingSec = 0.010;
end
