function runAll()
%RUNALL Lightweight MATLAB regression entry point.
root = fileparts(fileparts(mfilename('fullpath')));
addpath(root);

assert(common.detectSampleRate('data/dmr_1_78125.rawiq') == 78125);
assert(common.detectSampleRate('data/synthesized_wideband_2.5MHz.rawiq') == 2500000);
assert(isequal(radio.normalizeProtocolNames({'dmr', 'P25', 'dpmr'}), {'DMR', 'P25', 'dPMR'}));

cfg = tetra.config();
seqs = tetra.trainingSequences();
defs = tetra.dmoBurstDefinitions(seqs, cfg);
dsbDef = defs(strcmp({defs.name}, 'DSB_sync'));
dnb2Def = defs(strcmp({defs.name}, 'DNB_normal_2'));
dsbBkn1 = mod((1:120).', 2) ~= 0;
dsbBkn2 = mod((1:216).', 3) == 0;
dnbBkn1 = mod((1:216).', 4) == 0;
dnbBkn2 = mod((1:216).', 5) == 0;
bits = [ ...
    buildDmoSlot(dsbDef, dsbBkn1, dsbBkn2); ...
    buildDmoSlot(dnb2Def, dnbBkn1, dnbBkn2)];
training = tetra.findTrainingSequences(bits, seqs, cfg);
dmo = tetra.inferDmoBursts(bits, training, seqs, cfg);
assert(any(strcmp({dmo.bursts.burstType}, 'DSB') & [dmo.bursts.slotStartBit] == 1));
assert(any(strcmp({dmo.bursts.burstType}, 'DNB') & ...
    strcmp({dmo.bursts.trainingName}, 'normal_2') & [dmo.bursts.slotStartBit] == cfg.slotBits + 1));
assert(dmo.payloadBlockCount >= 4);
blocks = dmo.payloadBlocks;
idxDsbBkn1 = find([blocks.slotStartBit] == 1 & strcmp({blocks.blockName}, 'BKN1'), 1);
idxDnbBkn2 = find([blocks.slotStartBit] == cfg.slotBits + 1 & strcmp({blocks.blockName}, 'BKN2'), 1);
assert(~isempty(idxDsbBkn1) && isequal(blocks(idxDsbBkn1).bits, dsbBkn1));
assert(~isempty(idxDnbBkn2) && isequal(blocks(idxDnbBkn2).bits, dnbBkn2));

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

function slot = buildDmoSlot(def, bkn1, bkn2)
slot = false(def.slotBits, 1);
slot(def.preambleStartBit:def.preambleEndBit) = def.preambleBits;
if def.frequencyStartBit > 0
    slot(def.frequencyStartBit:def.frequencyEndBit) = def.frequencyBits;
end
slot(def.trainingStartBit:def.trainingEndBit) = def.trainingBits;
slot(def.tailStartBit:def.tailEndBit) = def.tailBits;
slot(def.bkn1StartBit:def.bkn1EndBit) = bkn1(:) ~= 0;
slot(def.bkn2StartBit:def.bkn2EndBit) = bkn2(:) ~= 0;
end
