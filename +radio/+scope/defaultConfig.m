function cfg = defaultConfig()
%DEFAULTCONFIG Settings for the live spectrum and waterfall engine.
cfg = struct();
cfg.nfft = 65536;
cfg.updateIntervalSec = 0.100;
cfg.averageAlpha = 0.25;
cfg.maxWaterfallRows = 200;
cfg.maxDisplayBins = 4096;
end
