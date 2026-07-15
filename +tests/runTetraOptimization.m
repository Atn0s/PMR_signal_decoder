function runTetraOptimization()
%RUNTETRAOPTIMIZATION Guard vectorized training search against naive XOR.
cfg = tetra.config();
seqs = tetra.trainingSequences();
savedRng = rng;
rng(7719);
bits = rand(6000, 1) > 0.5;
insertAt = [211, 1307, 2501, 3907, 5203];
for k = 1:numel(seqs)
    L = seqs(k).length;
    bits(insertAt(k):insertAt(k)+L-1) = seqs(k).bits;
end
rng(savedRng);
report = tetra.findTrainingSequences(bits, seqs, cfg);
for k = 1:numel(seqs)
    seqBits = seqs(k).bits(:) ~= 0;
    L = numel(seqBits);
    errors = zeros(numel(bits) - L + 1, 1);
    for pos = 1:numel(errors)
        errors(pos) = nnz(bits(pos:pos+L-1) ~= seqBits);
    end
    [bestErrors, bestOffset] = min(errors);
    assert(report.items(k).bestErrors == bestErrors);
    assert(report.items(k).bestOffset == bestOffset);
    assert(report.items(k).bestErrors == 0);
end
fprintf('TETRA vectorized training-search regression tests passed.\n');
end
