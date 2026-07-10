function result = scanFileWindows(path, varargin)
%SCANFILEWINDOWS TETRA-only full-file multi-window DMO control scan.
p = inputParser;
p.addParameter('SampleRate', []);
p.addParameter('IqDType', 'int16');
p.addParameter('OutputDir', '');
p.addParameter('WriteOutputs', true);
p.addParameter('ShowProgress', true);
p.addParameter('MaxWindows', []);
p.addParameter('WindowSec', []);
p.addParameter('OverlapSec', []);
p.addParameter('MergeGapSec', []);
p.addParameter('PrePadSec', []);
p.addParameter('PostPadSec', []);
p.parse(varargin{:});

iq = common.readRawIq(path, 'DType', p.Results.IqDType);
fs = p.Results.SampleRate;
if isempty(fs)
    fs = common.detectSampleRate(path);
end
if isempty(fs)
    error('tetra:scanFileWindows:MissingSampleRate', ...
        'Sample rate is required; pass SampleRate or use WAV metadata.');
end

result = tetra.scanIqWindows(iq, fs, ...
    'SourcePath', path, ...
    'OutputDir', p.Results.OutputDir, ...
    'WriteOutputs', p.Results.WriteOutputs, ...
    'ShowProgress', p.Results.ShowProgress, ...
    'MaxWindows', p.Results.MaxWindows, ...
    'WindowSec', p.Results.WindowSec, ...
    'OverlapSec', p.Results.OverlapSec, ...
    'MergeGapSec', p.Results.MergeGapSec, ...
    'PrePadSec', p.Results.PrePadSec, ...
    'PostPadSec', p.Results.PostPadSec);
end
