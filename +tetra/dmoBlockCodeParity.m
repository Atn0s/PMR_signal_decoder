function parity = dmoBlockCodeParity(dataBits)
%DMOBLOCKCODEPARITY Generate the 16 parity bits for the DMO block code.
%
% Implements EN 300 396-2 clause 8.2.3.2 for the (K1+16,K1) code.
dataBits = dataBits(:).' ~= 0;
K1 = numel(dataBits);

poly = [dataBits, false(1, 16)];
poly(1:16) = xor(poly(1:16), true);

gen = false(1, 17);
gen([1 5 12 17]) = true; % X^16 + X^12 + X^5 + 1
remBits = poly;
for k = 1:K1
    if remBits(k)
        remBits(k:k+16) = xor(remBits(k:k+16), gen);
    end
end

parity = xor(remBits(K1+1:K1+16), true).';
end
