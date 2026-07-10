function [state, assembled] = sacchAssemblerFeed(state, block, frameInfo, fsStart, cfg)
%SACCHASSEMBLERFEED Feed one CRC-valid SACCH fragment.
if nargin < 5 || isempty(cfg)
    cfg = nxdn.config();
end
assembled = [];
if ~block.ok
    state = nxdn.sacchAssemblerInit();
    return;
end
if ~frameInfo.superframe
    assembled = makeAssembly(block.layer3_bits, block.ran, frameInfo, ...
        fsStart, fsStart, false);
    return;
end
part = 4 - double(block.structure);
sameContext = state.active && isequal(state.ran, block.ran) && ...
    strcmp(state.direction, frameInfo.direction) && ...
    strcmp(state.rf_channel_type, frameInfo.rf_channel_type);
gapOk = state.active && ~isempty(state.last_sample) && ...
    abs(double(fsStart) - double(state.last_sample) - cfg.frameSamples) <= ...
    cfg.samplesPerSymbol * 2;
if part == 1
    state = nxdn.sacchAssemblerInit();
    state.active = true;
    state.next_part = 2;
    state.fragments(1, :) = block.layer3_bits;
    state.ran = block.ran;
    state.direction = frameInfo.direction;
    state.rf_channel_type = frameInfo.rf_channel_type;
    state.first_sample = fsStart;
    state.last_sample = fsStart;
    return;
end
if ~sameContext || ~gapOk || part ~= state.next_part
    state = nxdn.sacchAssemblerInit();
    return;
end
state.fragments(part, :) = block.layer3_bits;
state.next_part = part + 1;
state.last_sample = fsStart;
if part == 4
    bits = reshape(state.fragments.', [], 1).';
    assembled = makeAssembly(bits, block.ran, frameInfo, ...
        state.first_sample, fsStart, true);
    state = nxdn.sacchAssemblerInit();
end
end

function item = makeAssembly(bits, ran, frameInfo, firstSample, lastSample, superframe)
item = struct('channel', 'SACCH', 'layer3_bits', logical(bits(:).'), ...
    'ran', ran, 'direction', frameInfo.direction, ...
    'rf_channel_type', frameInfo.rf_channel_type, ...
    'first_sample', firstSample, 'last_sample', lastSample, ...
    'superframe', superframe);
end
