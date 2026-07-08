function b3 = blockDeinterleave(b4, a)
%BLOCKDEINTERLEAVE Invert the TETRA (K,a) block interleaver.
b4 = b4(:) ~= 0;
K = numel(b4);
b3 = false(K, 1);
for i = 1:K
    k = 1 + mod(a * i, K);
    b3(i) = b4(k);
end
end
