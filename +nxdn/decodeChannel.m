function [decoded, info] = decodeChannel(bits, rows, depth, puncture, motherLength)
%DECODECHANNEL Deinterleave, depuncture, and Viterbi-decode a channel block.
deinterleaved = nxdn.blockDeinterleave(bits, rows, depth);
coded = nxdn.depuncture(deinterleaved, puncture, motherLength);
[decoded, vit] = nxdn.viterbiDecodeK5(coded);
info = struct('deinterleaved_bits', deinterleaved(:).', ...
    'coded_bits', coded(:).', 'viterbi', vit);
end
