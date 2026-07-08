function b4 = blockInterleave(b3, a)
%BLOCKINTERLEAVE Apply the TETRA (K,a) block interleaver.
b3 = b3(:) ~= 0;
K = numel(b3);
b4 = false(K, 1);
for i = 1:K
    k = 1 + mod(a * i, K);
    b4(k) = b3(i);
end
end
