function runAll()
%RUNALL Lightweight MATLAB regression entry point.
root = fileparts(fileparts(mfilename('fullpath')));
addpath(root);

assert(common.detectSampleRate('data/dmr_1_78125.rawiq') == 78125);
assert(common.detectSampleRate('data/synthesized_wideband_2.5MHz.rawiq') == 2500000);
assert(isequal(radio.normalizeProtocolNames({'dmr', 'P25', 'dpmr', 'tetra'}), {'DMR', 'P25', 'dPMR', 'TETRA'}));
specs = radio.protocolRegistry();
tetraSpec = specs(strcmp({specs.name}, 'TETRA'));
assert(strcmp(tetraSpec.scanMode, 'windowed_iq'));
assert(tetraSpec.targetSampleRateHz == 72000);
assert(~tetraSpec.supportsBlindSearch);
[defaultBlind, explicitDefaultBlind] = radio.resolveScanProtocols({}, 'BlindSearch', true);
assert(~explicitDefaultBlind && ~any(strcmp(defaultBlind, 'TETRA')));
[defaultFreq, explicitDefaultFreq] = radio.resolveScanProtocols({}, 'FreqList', 0);
assert(~explicitDefaultFreq && any(strcmp(defaultFreq, 'TETRA')));
assert(numel(radio.deduplicatePdus(makeP25SemanticDuplicates())) == 1);
assert(numel(radio.deduplicatePdus(makeDpmrSemanticDuplicates())) == 1);
syntheticNid = false(64, 1);
syntheticNid(1:16) = [intToBits(hex2dec('293'), 12), intToBits(5, 4)];
synthetic = p25.decodeNid(syntheticNid);
assert(~synthetic.valid_bch && ~synthetic.corrected);

tests.runNxdn96();

cfg = tetra.config();
seqs = tetra.trainingSequences();
defs = tetra.dmoBurstDefinitions(seqs, cfg);
dsbDef = defs(strcmp({defs.name}, 'DSB_sync'));
dnb2Def = defs(strcmp({defs.name}, 'DNB_normal_2'));
dsbBkn1 = encodeSchS(makeSchSType1(1, 6));
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
assert(dmo.schSDecodedCount >= 1);
idxDsb = find(strcmp({dmo.bursts.burstType}, 'DSB') & [dmo.bursts.slotStartBit] == 1, 1);
assert(~isempty(idxDsb) && dmo.bursts(idxDsb).frameNumber == 6 && dmo.bursts(idxDsb).slotNumber == 1);
validMask = true(size(bits));
dnbSlotStart = cfg.slotBits + 1;
validMask(dnbSlotStart + dnb2Def.bkn2StartBit - 1:dnbSlotStart + dnb2Def.bkn2EndBit - 1) = false;
dmoMasked = tetra.inferDmoBursts(bits, training, seqs, cfg, validMask);
maskedBlocks = dmoMasked.payloadBlocks;
idxMaskedBkn2 = find([maskedBlocks.slotStartBit] == dnbSlotStart & strcmp({maskedBlocks.blockName}, 'BKN2'), 1);
assert(~isempty(idxMaskedBkn2) && maskedBlocks(idxMaskedBkn2).validRatio == 0);

schSType1 = makeSchSType1(3, 12);
schSBlock = encodeSchS(schSType1);
schS = tetra.decodeSchS(schSBlock, cfg);
assert(schS.ok);
assert(schS.slotNumber == 3);
assert(schS.frameNumber == 12);
assert(schS.pdu.isDmacSync);

sample = fullfile(pybackend.defaultPythonRoot(), 'data', 'dmr_1_78125.rawiq');
if exist(sample, 'file') == 2
    pdus = radio.scanFile(sample, 'ProtocolNames', {'dmr'}, ...
        'PipelineBackend', 'matlab', 'DecoderBackend', 'matlab');
    rawPdus = radio.scanFile(sample, 'ProtocolNames', {'dmr'}, ...
        'PipelineBackend', 'matlab', 'DecoderBackend', 'matlab', ...
        'Deduplicate', false);
    assert(isstruct(pdus));
    assert(numel(rawPdus) >= numel(pdus));
    tmpJson = [tempname, '.json'];
    radio.writeJson(pdus, tmpJson);
    assert(~contains(fileread(tmpJson), 'raw_bits'));
    radio.writeJson(pdus, tmpJson, 'IncludeRawBits', true);
    assert(contains(fileread(tmpJson), 'raw_bits'));
    delete(tmpJson);
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

tetraSample = fullfile(pybackend.defaultPythonRoot(), 'data', 'tetra_dmo_20240413_430050000_baseband.wav');
if exist(tetraSample, 'file') == 2
    pdus = radio.scanFile(tetraSample, 'ProtocolNames', {'tetra'}, ...
        'PipelineBackend', 'matlab', 'DecoderBackend', 'matlab');
    assert(isstruct(pdus));
    assert(any(strcmp({pdus.type}, 'TETRA_DMAC_SYNC')));
    assert(any(strcmp({pdus.type}, 'TETRA_SESSION')));
    tetraEvents = pdus(startsWith({pdus.type}, 'TETRA_') & ~strcmp({pdus.type}, 'TETRA_SESSION'));
    assert(isfield(tetraEvents(1).extra, 'valid_transition_ratio'));
    ratios = arrayfun(@(p) radio.getNestedField(p, 'extra.valid_transition_ratio', NaN), tetraEvents);
    assert(any(ratios > 0.7));
    iq = common.readRawIq(tetraSample);
    fs = common.detectSampleRate(tetraSample);
    cropStart = max(1, round(5.0 * fs));
    cropEnd = min(numel(iq), round(7.6 * fs));
    crop = iq(cropStart:cropEnd);
    result = tetra.scanIqWindows(crop, fs, 'ShowProgress', false, ...
        'WriteOutputs', false, 'MaxWindows', 1);
    assert(isstruct(result) && isfield(result, 'pdus') && ~isempty(result.pdus));
    defaultFreqPdus = radio.scanIq(crop, fs, 'FreqList', 0);
    assert(any(strcmp({defaultFreqPdus.protocol}, 'TETRA')));
    didError = false;
    try
        radio.scanIq(crop, fs, 'ProtocolNames', {'tetra'}, 'BlindSearch', true);
    catch ME
        didError = strcmp(ME.identifier, 'radio:scanIq:TetraBlindSearchUnsupported');
    end
    assert(didError);
    fprintf('TETRA sample decoded PDUs/events: %d\n', numel(pdus));
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

function bits = makeSchSType1(slotNumber, frameNumber)
bits = [ ...
    intToBits(13, 4), ... % EN 300 396-3 DMO AI
    intToBits(0, 2), ...  % DMAC-SYNC
    intToBits(0, 2), ...  % direct MS-MS
    0, 0, ...             % reserved conditional bits
    intToBits(0, 2), ...  % channel A, normal mode
    intToBits(slotNumber - 1, 2), ...
    intToBits(frameNumber, 5), ...
    intToBits(0, 2), ...  % DM-1 no AI encryption
    zeros(1, 39)] ~= 0;
bits = bits(:);
end

function b5 = encodeSchS(type1Bits)
parity = tetra.dmoBlockCodeParity(type1Bits);
type2 = [type1Bits(:) ~= 0; parity; false(4, 1)];
type3 = rcpcEncodeRate23(type2);
type4 = tetra.blockInterleave(type3, 11);
b5 = xor(type4, tetra.scramblingSequence(120));
end

function encoded = rcpcEncodeRate23(type2)
type2 = type2(:) ~= 0;
mother = false(numel(type2) * 4, 1);
state = 0;
for k = 1:numel(type2)
    [out, state] = motherOutputs(state, type2(k));
    mother(4*k-3:4*k) = out(:);
end
p = [1 2 5];
encoded = false(numel(type2) * 3 / 2, 1);
for j = 1:numel(encoded)
    coeff = p(1 + mod(j - 1, numel(p)));
    motherIdx = 8 * floor((j - 1) / numel(p)) + coeff;
    encoded(j) = mother(motherIdx);
end
end

function [out, nextState] = motherOutputs(state, inputBit)
prev = bitget(uint8(state), 4:-1:1) ~= 0;
u = inputBit ~= 0;
out = [ ...
    xor(xor(u, prev(1)), prev(4)), ...
    xor(xor(u, prev(2)), xor(prev(3), prev(4))), ...
    xor(xor(u, prev(1)), xor(prev(2), prev(4))), ...
    xor(xor(u, prev(1)), xor(prev(3), prev(4)))];
nextBits = [u, prev(1:3)];
nextState = double(nextBits) * [8; 4; 2; 1];
end

function bits = intToBits(value, width)
bits = false(1, width);
for k = 1:width
    bits(k) = bitget(uint32(value), width - k + 1) ~= 0;
end
end

function pdus = makeP25SemanticDuplicates()
extra = struct('nac', 659, 'fs_start', 1000, 'lco', 0, 'mfid', 0, ...
    'call_type', 'group', 'lc_info', 1024, 'tgid', 1);
pdus(1) = makePdu('P25', 'P25_LDU1', 1, 1, 0, 'LDU1', '', extra);
extra.fs_start = 250000;
pdus(2) = makePdu('P25', 'P25_LDU1', 1, 1, 0, 'LDU1', '', extra);
end

function pdus = makeDpmrSemanticDuplicates()
cch = struct('frame_number', 1, 'id_half', 1407, ...
    'communication_mode', 0, 'comms_format', 1, 'emergency_priority', 0);
extra = struct('color_code', 2, 'sync_type', 'FS2', 'fs_start', 1000, 'cch', cch);
pdus(1) = makePdu('dPMR', 'DPMR_VOICE', '', '', 0, 'VOICE', '', extra);
extra.fs_start = 250000;
pdus(2) = makePdu('dPMR', 'DPMR_VOICE', '', '', 0, 'VOICE', '', extra);
end

function pdu = makePdu(protocol, typeName, src, dst, ts, flco, fid, extra)
pdu = struct('protocol', protocol, 'type', typeName, 'src', src, 'dst', dst, ...
    'ts', ts, 'flco', flco, 'fid', fid, 'extra', extra, 'raw_bits', []);
end
