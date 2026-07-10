function bits = dibitsToBits(dibits)
%DIBITSTOBITS Expand dibits to MSB-first bits.
dibits = uint8(dibits(:));
bits = false(2 * numel(dibits), 1);
bits(1:2:end) = bitget(dibits, 2) ~= 0;
bits(2:2:end) = bitget(dibits, 1) ~= 0;
end
