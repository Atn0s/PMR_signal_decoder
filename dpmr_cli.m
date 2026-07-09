%% dPMR scanner entry
% Edit TARGET_FILE, then click Run in MATLAB.

TARGET_FILE = '/home/lzkj/lzkj_workspace/python_docs/DMR_demo/data/dpmr_1_48000.rawiq';
SAMPLE_RATE = [];
FREQ_LIST = [];
BLIND_SEARCH = false;
SHOW_FIGURE = true;
IQ_DTYPE = 'int16';
DEDUPLICATE = true;

%% Run
projectRoot = fileparts(mfilename('fullpath'));
addpath(projectRoot);
startup;

result = viz.analyzeFile(TARGET_FILE, ...
    'ProtocolNames', {'dpmr'}, ...
    'SampleRate', SAMPLE_RATE, ...
    'IqDType', IQ_DTYPE, ...
    'FreqList', FREQ_LIST, ...
    'BlindSearch', BLIND_SEARCH, ...
    'PipelineBackend', 'matlab', ...
    'DecoderBackend', 'matlab', ...
    'Deduplicate', DEDUPLICATE, ...
    'CreateFigure', SHOW_FIGURE);

pdus = result.pdus;
fprintf('\n=== dPMR: %s ===\n', TARGET_FILE);
fprintf('Decoded PDUs: %d\n', numel(pdus));
for k = 1:numel(result.lines)
    fprintf('%s\n', result.lines{k});
end
