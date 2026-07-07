function name = fidName(value)
%FIDNAME DMR Feature Set ID display name.
switch double(value)
    case 0
        name = 'StandardizedFID';
    case 128
        name = 'ReservedForFutureMFID';
    otherwise
        name = sprintf('FID_0x%02X', value);
end
end

