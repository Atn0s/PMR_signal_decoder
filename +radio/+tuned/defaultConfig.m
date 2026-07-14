function cfg = defaultConfig()
%DEFAULTCONFIG Known-carrier wideband-to-baseband transition settings.
cfg = struct();
cfg.outputSampleRateHz = 120000;
cfg.channelBandwidthHz = 40000;
cfg.stopbandFrequencyHz = 55000;
cfg.passbandRippleDb = 0.1;
cfg.stopbandAttenuationDb = 80;
cfg.chunkDurationSec = 0.010;
cfg.filterFlushSec = 0.010;
end
