%% Unified DMR/P25/dPMR/NXDN/TETRA scanner entry
% Edit the configuration block, then click Run in MATLAB.

TARGET_FILE = '/home/lzkj/lzkj_workspace/python_docs/DMR_demo/data/synthesized_wideband_2.5MHz.rawiq';

% Use {} for scan-mode defaults, or: {'dmr'}, {'p25'}, {'dpmr'}, {'nxdn'}, {'tetra'}.
% Defaults: centered/FREQ_LIST/BlindSearch include NXDN; FREQ_LIST also includes TETRA.
PROTOCOLS = {};

% Leave SAMPLE_RATE empty to infer it from names like dmr_1_78125.rawiq.
SAMPLE_RATE = [];

% Use [] for centered baseband. Use e.g. [12500 -12500] for known offsets.
FREQ_LIST = [];

% Set true for wideband/multi-channel IQ when the signal offset is unknown.
BLIND_SEARCH = true;

% Show diagnostic figure with IQ, PSD, frontend output, and decoded PDU text.
SHOW_FIGURE = true;

% Set false to keep repeated frames for debugging and golden comparison.
DEDUPLICATE = true;

% Use the native MATLAB backend. Set either value to 'python' for fallback.
PIPELINE_BACKEND = 'matlab';     % 'matlab' or 'python'
DECODER_BACKEND = 'matlab';      % 'matlab' or 'python'
IQ_DTYPE = 'int16';

%% Run
projectRoot = fileparts(mfilename('fullpath'));
addpath(projectRoot);
startup;

result = viz.analyzeFile(TARGET_FILE, ...
    'ProtocolNames', PROTOCOLS, ...
    'SampleRate', SAMPLE_RATE, ...
    'IqDType', IQ_DTYPE, ...
    'FreqList', FREQ_LIST, ...
    'BlindSearch', BLIND_SEARCH, ...
    'PipelineBackend', PIPELINE_BACKEND, ...
    'DecoderBackend', DECODER_BACKEND, ...
    'Deduplicate', DEDUPLICATE, ...
    'CreateFigure', SHOW_FIGURE);

pdus = result.pdus;
fprintf('\n=== %s ===\n', TARGET_FILE);
fprintf('Sample rate: %.0f Hz\n', result.sampleRate);
fprintf('Decoded PDUs: %d\n', numel(pdus));
for k = 1:numel(result.lines)
    fprintf('%s\n', result.lines{k});
end
