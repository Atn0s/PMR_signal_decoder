function cfg = defaultConfig()
%DEFAULTCONFIG Initial configuration for the streaming scanner pipeline.
cfg = struct();
cfg.chunkDurationSec = 0.100;
cfg.ringBufferSec = 8.0;
cfg.preTriggerSec = 0.5;
cfg.lockedSuspectWindows = 3;
cfg.lockedLostWindows = 6;

cfg.activity = struct();
cfg.activity.initialNoiseFloorDb = -60.0;
cfg.activity.onMarginDb = 10.0;
cfg.activity.offMarginDb = 6.0;
cfg.activity.minOnSec = 0.050;
cfg.activity.offHangSec = 0.300;
cfg.activity.noiseUpdateAlpha = 0.05;
cfg.activity.minPowerDb = -160.0;
end
