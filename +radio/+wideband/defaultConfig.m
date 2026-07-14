function cfg = defaultConfig()
%DEFAULTCONFIG Initial settings for the streaming wideband front end.
cfg = struct();
cfg.chunkDurationSec = 0.010;

cfg.channelizer = struct();
cfg.channelizer.numChannels = 1024;
cfg.channelizer.oversampleFactor = 2;
cfg.channelizer.tapsPerChannel = 8;
cfg.channelizer.prototypeCutoffBins = 0.60;
cfg.channelizer.frameBlockSize = 64;

cfg.detector = struct();
cfg.detector.onMarginDb = 10.0;
cfg.detector.offMarginDb = 6.0;
cfg.detector.minPowerDb = -160.0;
cfg.detector.finePsdThresholdDb = 8.0;
cfg.detector.fineFftLength = 512;
cfg.detector.channelSmoothingHz = 4800.0;
cfg.detector.candidateMinSpacingHz = 5000.0;
cfg.detector.duplicateMergeHz = 2500.0;
cfg.detector.maxCandidatesPerBatch = inf;

cfg.tracker = struct();
cfg.tracker.minOnSec = 0.030;
% Keep routing alive slightly longer than the 300 ms RF Epoch off-hang so
% the narrowband controller receives the Chunk that closes its Epoch.
cfg.tracker.offHangSec = 0.350;
cfg.tracker.matchToleranceHz = 2500.0;
cfg.tracker.frequencyAlpha = 0.25;
cfg.tracker.frequencyEventThresholdHz = 100.0;

cfg.extractor = struct();
cfg.extractor.lowpassCutoffHz = 18000.0;
cfg.extractor.lowpassTaps = 129;

cfg.stream = radio.stream.defaultConfig();
end
