function layouts = slotLayouts(seqs, cfg)
%SLOTLAYOUTS First-pass centered training-sequence slot hypotheses.
%
% Offsets are 1-based bit positions within a 510-bit TETRA slot. This first
% pass treats each known training sequence as centered in the slot, which is
% enough to turn sequence hits into inspectable slot candidates.
if nargin < 2 || isempty(cfg)
    cfg = tetra.config();
end

layouts = repmat(struct( ...
    'trainingName', '', ...
    'trainingLength', 0, ...
    'trainingStartBit', 0, ...
    'burstClass', '', ...
    'description', ''), 0, 1);

for k = 1:numel(seqs)
    name = char(seqs(k).name);
    L = seqs(k).length;
    startBit = floor((cfg.slotBits - L) / 2) + 1;
    [burstClass, description] = classifyTraining(name);
    layouts(end+1, 1) = struct( ... %#ok<AGROW>
        'trainingName', name, ...
        'trainingLength', L, ...
        'trainingStartBit', startBit, ...
        'burstClass', burstClass, ...
        'description', description);
end
end

function [burstClass, description] = classifyTraining(name)
switch lower(char(name))
    case 'normal_1'
        burstClass = 'DNB';
        description = 'Normal downlink burst candidate, TCH/SCH-F without stealing flag';
    case 'normal_2'
        burstClass = 'DNB';
        description = 'Normal downlink burst candidate, stealing/STCH indication candidate';
    case 'normal_3'
        burstClass = 'DNB';
        description = 'Normal downlink burst candidate, supplementary downlink sequence';
    case 'extended'
        burstClass = 'extended';
        description = 'Extended control burst candidate';
    case 'sync'
        burstClass = 'DSB';
        description = 'Downlink synchronization burst candidate';
    otherwise
        burstClass = 'unknown';
        description = 'Unknown centered training sequence candidate';
end
end
