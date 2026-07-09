%% TETRA full-file multi-window DMO control scan
% Run this script from the MATLAB project root or click Run in MATLAB.

projectRoot = fileparts(fileparts(fileparts(mfilename('fullpath'))));
addpath(projectRoot);
startup;

TARGET_FILE = '/home/lzkj/lzkj_workspace/python_docs/DMR_demo/data/tetra_dmo_20240413_430050000_baseband.wav';
OUTPUT_DIR = fullfile(projectRoot, 'outputs', 'tetra_full_file_scan', 'interactive_latest');

result = tetra.scanFileWindows(TARGET_FILE, ...
    'OutputDir', OUTPUT_DIR, ...
    'ShowProgress', true);

fprintf('\n=== TETRA full-file scan ===\n');
fprintf('Input: %s\n', result.path);
fprintf('Output: %s\n', result.outputDir);
fprintf('Input Fs: %.0f Hz, target Fs: %.0f Hz, duration: %.3f s\n', ...
    result.inputSampleRateHz, result.targetSampleRateHz, result.durationSec);
fprintf('Windows: %d decoded windows: %d\n', ...
    result.summary.windowCount, result.summary.decodedWindowCount);
fprintf('PDUs/events: %d DMAC-SYNC=%d STCH=%d SCH/F=%d TCH candidates=%d sessions=%d\n', ...
    result.summary.pduCount, result.summary.dmacSyncCount, ...
    result.summary.stchCount, result.summary.schfCount, ...
    result.summary.tchCandidateCount, result.summary.sessionCount);
fprintf('Confirmed bursts from windows: %d DSB=%d DNB=%d\n', ...
    result.summary.confirmedBurstCount, result.summary.dsbCount, result.summary.dnbCount);

fprintf('\nFirst decoded lines:\n');
for k = 1:min(numel(result.lines), 30)
    fprintf('%s\n', result.lines{k});
end
