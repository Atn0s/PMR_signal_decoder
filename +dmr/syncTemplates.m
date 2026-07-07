function templates = syncTemplates()
%SYNCTEMPLATES DMR sync templates as nominal 4FSK levels.
templates = struct();
templates.BS_VOICE = hexToSymbols('755FD7DF75F7');
templates.MS_VOICE = hexToSymbols('7F7D5DD57DFD');
templates.DATA_BS = hexToSymbols('DFF57D75DF5D');
templates.DATA_MS = hexToSymbols('D5D7F77FD757');
end

function symbols = hexToSymbols(hexStr)
bits = '';
for k = 1:numel(hexStr)
    bits = [bits dec2bin(hex2dec(hexStr(k)), 4)]; %#ok<AGROW>
end
symbols = zeros(1, numel(bits) / 2);
for k = 1:numel(symbols)
    pair = bits(2*k-1:2*k);
    switch pair
        case '01'
            symbols(k) = 3;
        case '00'
            symbols(k) = 1;
        case '10'
            symbols(k) = -1;
        otherwise
            symbols(k) = -3;
    end
end
symbols = symbols(:);
end

