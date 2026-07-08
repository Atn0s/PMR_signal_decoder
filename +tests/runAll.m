function runAll()
%RUNALL Lightweight MATLAB regression entry point.
root = fileparts(fileparts(mfilename('fullpath')));
addpath(root);

assert(common.detectSampleRate('data/dmr_1_78125.rawiq') == 78125);
assert(common.detectSampleRate('data/synthesized_wideband_2.5MHz.rawiq') == 2500000);
assert(isequal(radio.normalizeProtocolNames({'dmr', 'P25', 'dpmr'}), {'DMR', 'P25', 'dPMR'}));

cfg = tetra.config();
seqs = tetra.trainingSequences();
bits = mod((1:1600).', 2) == 0;
normal2 = seqs(strcmp({seqs.name}, 'normal_2')).bits ~= 0;
syncSeq = seqs(strcmp({seqs.name}, 'sync')).bits ~= 0;
bits(245:245+numel(normal2)-1) = normal2;
bits(511+237-1:511+237+numel(syncSeq)-2) = syncSeq;
training = tetra.findTrainingSequences(bits, seqs, cfg);
slots = tetra.inferSlotCandidates(bits, training, seqs, cfg);
assert(any(strcmp({slots.candidates.trainingName}, 'normal_2') & [slots.candidates.slotStartBit] == 1));
assert(any(strcmp({slots.candidates.trainingName}, 'sync') & [slots.candidates.slotStartBit] == 511));

sample = fullfile(pybackend.defaultPythonRoot(), 'data', 'dmr_1_78125.rawiq');
if exist(sample, 'file') == 2
    pdus = radio.scanFile(sample, 'ProtocolNames', {'dmr'}, ...
        'PipelineBackend', 'matlab', 'DecoderBackend', 'matlab');
    assert(isstruct(pdus));
    fprintf('DMR sample decoded PDUs: %d\n', numel(pdus));
end

p25Sample = fullfile(pybackend.defaultPythonRoot(), 'data', 'p25_1_78125.rawiq');
if exist(p25Sample, 'file') == 2
    pdus = radio.scanFile(p25Sample, 'ProtocolNames', {'p25'}, ...
        'PipelineBackend', 'matlab', 'DecoderBackend', 'matlab');
    assert(isstruct(pdus));
    fprintf('P25 sample decoded PDUs: %d\n', numel(pdus));
end

dpmrSample = fullfile(pybackend.defaultPythonRoot(), 'data', 'dpmr_1_48000.rawiq');
if exist(dpmrSample, 'file') == 2
    pdus = radio.scanFile(dpmrSample, 'ProtocolNames', {'dpmr'}, ...
        'PipelineBackend', 'matlab', 'DecoderBackend', 'matlab');
    assert(isstruct(pdus));
    fprintf('dPMR sample decoded PDUs: %d\n', numel(pdus));
end

fprintf('MATLAB migration smoke tests passed.\n');
end
