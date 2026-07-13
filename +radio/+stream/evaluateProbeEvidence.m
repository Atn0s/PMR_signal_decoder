function verdict = evaluateProbeEvidence(protocol, pdus, diagnostics)
%EVALUATEPROBEEVIDENCE Apply protocol-specific strong-confirmation rules.
if nargin < 2 || isempty(pdus), pdus = struct([]); end
if nargin < 3 || isempty(diagnostics), diagnostics = struct(); end
protocol = radio.normalizeProtocolNames({protocol});
protocol = protocol{1};

verdict = struct( ...
    'status', 'no_evidence', ...
    'confidence', 0.0, ...
    'evidenceClass', '', ...
    'evidence', struct('pduCount', numel(pdus)), ...
    'reason', 'no_strong_protocol_evidence');

switch protocol
    case 'DMR'
        [strongCount, weakCount, evidenceClass] = dmrEvidence(pdus);
        verdict.evidence.strongCount = strongCount;
        verdict.evidence.weakCount = weakCount;
        if strongCount > 0
            verdict = confirm(verdict, 0.99, evidenceClass);
        elseif weakCount > 0
            verdict = candidate(verdict, 0.45, 'sync_or_csbk_only', ...
                'dmr_sync_without_strong_lc_validation');
        end

    case 'P25'
        validCount = countLogicalExtra(pdus, 'valid_bch');
        verdict.evidence.validBchNidCount = validCount;
        if validCount > 0
            verdict = confirm(verdict, 0.99, 'bch_valid_nid');
        end

    case 'dPMR'
        [crcCount, hammingCount] = dpmrEvidence(pdus);
        verdict.evidence.crcValidCchCount = crcCount;
        verdict.evidence.hammingValidCchCount = hammingCount;
        if crcCount > 0
            verdict = confirm(verdict, 0.99, 'crc_valid_cch');
        elseif hammingCount >= 2
            verdict = confirm(verdict, 0.90, 'repeated_hamming_valid_cch');
        elseif hammingCount == 1
            verdict = candidate(verdict, 0.60, 'single_hamming_valid_cch', ...
                'dpmr_weak_cch_requires_repeat');
        end

    case 'NXDN'
        blockCount = fieldOr(diagnostics, 'validChannelBlockCount', 0);
        lichCount = radio.getNestedField(diagnostics, 'quality.lich_ok_count', 0);
        verdict.evidence.validChannelBlockCount = blockCount;
        verdict.evidence.lichOkCount = lichCount;
        if blockCount > 0 && lichCount > 0
            verdict = confirm(verdict, 0.99, 'crc_valid_channel_block');
        elseif lichCount > 0
            verdict = candidate(verdict, 0.50, 'valid_lich_only', ...
                'nxdn_lich_without_crc_valid_channel_block');
        end

    case 'TETRA'
        types = pduTypes(pdus);
        strongMask = ismember(types, ...
            {'TETRA_DMAC_SYNC', 'TETRA_STCH', 'TETRA_SCHF'});
        strongCount = nnz(strongMask);
        trainingGood = radio.getNestedField(diagnostics, 'training.goodCount', 0);
        verdict.evidence.validControlPduCount = strongCount;
        verdict.evidence.goodTrainingCount = trainingGood;
        if strongCount > 0
            verdict = confirm(verdict, 0.99, 'fec_valid_dmo_control_block');
        elseif trainingGood > 0
            verdict = candidate(verdict, 0.45, 'training_sequence_only', ...
                'tetra_training_without_fec_valid_control_block');
        end
end
end

function [strongCount, weakCount, evidenceClass] = dmrEvidence(pdus)
rsCount = 0;
lateEntryCount = 0;
weakCount = 0;
for k = 1:numel(pdus)
    type = char(pdus(k).type);
    if any(strcmp(type, {'LC_HEADER', 'TERMINATOR'})) && ...
            radio.getNestedField(pdus(k), 'extra.fec.rs_12_9_4_ok', false)
        rsCount = rsCount + 1;
    elseif strcmp(type, 'LATE_ENTRY') && ...
            radio.getNestedField(pdus(k), 'extra.cs5_ok', false)
        lateEntryCount = lateEntryCount + 1;
    elseif strcmp(type, 'CSBK') || startsWith(type, 'DMR_')
        weakCount = weakCount + 1;
    end
end
strongCount = rsCount + lateEntryCount;
if rsCount > 0
    evidenceClass = 'rs_valid_full_link_control';
else
    evidenceClass = 'cs5_valid_late_entry_lc';
end
end

function count = countLogicalExtra(pdus, name)
count = 0;
for k = 1:numel(pdus)
    count = count + double(logical(radio.getNestedField( ...
        pdus(k), ['extra.', name], false)));
end
end

function [crcCount, hammingCount] = dpmrEvidence(pdus)
crcCount = 0;
hammingCount = 0;
for k = 1:numel(pdus)
    records = radio.getNestedField(pdus(k), 'extra.cch', struct([]));
    for n = 1:numel(records)
        crcCount = crcCount + double(logical(fieldOr(records(n), 'crc_ok', false)));
        hammingCount = hammingCount + ...
            double(logical(fieldOr(records(n), 'hamming_ok', false)));
    end
end
end

function types = pduTypes(pdus)
if isempty(pdus)
    types = {};
else
    types = arrayfun(@(p) char(p.type), pdus, 'UniformOutput', false);
end
end

function verdict = confirm(verdict, confidence, evidenceClass)
verdict.status = 'confirmed';
verdict.confidence = confidence;
verdict.evidenceClass = evidenceClass;
verdict.reason = '';
end

function verdict = candidate(verdict, confidence, evidenceClass, reason)
verdict.status = 'candidate';
verdict.confidence = confidence;
verdict.evidenceClass = evidenceClass;
verdict.reason = reason;
end

function value = fieldOr(s, name, fallback)
if isstruct(s) && isfield(s, name)
    value = s.(name);
else
    value = fallback;
end
end
