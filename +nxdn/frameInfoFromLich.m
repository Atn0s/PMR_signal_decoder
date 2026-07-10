function frame = frameInfoFromLich(lich)
%FRAMEINFOFROMLICH Interpret the seven-bit NXDN LICH value.
value = double(lich.value);
rf = bitand(bitshift(value, -5), 3);
fc = bitand(bitshift(value, -3), 3);
op = bitand(bitshift(value, -1), 3);
direction = bitand(value, 1);
rfNames = {'RCCH', 'RTCH', 'RDCH', 'RTCH_C_OR_TYPE_D'};
frame = struct();
frame.lich = value;
frame.rf_channel_code = rf;
frame.rf_channel_type = rfNames{rf + 1};
frame.functional_channel_code = fc;
frame.option = op;
frame.direction_code = direction;
if direction == 0, frame.direction = 'inbound'; else, frame.direction = 'outbound'; end
frame.functional_channel = 'UNKNOWN';
frame.sacch = false;
frame.superframe = false;
frame.half1_type = 'none';
frame.half2_type = 'none';
frame.voice_present = false;
frame.supported = true;
frame.ambiguous_type_d = rf == 3;
if rf == 0
    if direction == 1 && fc == 0
        frame.functional_channel = 'CAC_OUTBOUND';
    elseif direction == 0 && fc == 1
        frame.functional_channel = 'CAC_LONG_INBOUND';
    elseif direction == 0 && fc == 3
        frame.functional_channel = 'CAC_SHORT_INBOUND';
    else
        frame.functional_channel = 'CAC_RESERVED';
        frame.supported = false;
    end
    return;
end
switch fc
    case 0
        frame.functional_channel = 'SACCH';
        frame.sacch = true;
        frame.superframe = false;
        [frame.half1_type, frame.half2_type] = halfTypes(op);
    case 1
        if op == 0
            frame.functional_channel = 'FACCH2';
        elseif op == 3
            frame.functional_channel = 'UDCH';
        else
            frame.functional_channel = 'USC_RESERVED';
            frame.supported = false;
        end
    case 2
        frame.functional_channel = 'SACCH';
        frame.sacch = true;
        frame.superframe = true;
        [frame.half1_type, frame.half2_type] = halfTypes(op);
    case 3
        frame.functional_channel = 'SACCH_IDLE';
        frame.sacch = true;
        frame.superframe = true;
end
frame.voice_present = strcmp(frame.half1_type, 'VCH') || strcmp(frame.half2_type, 'VCH');
end

function [first, second] = halfTypes(option)
switch option
    case 0
        first = 'FACCH1'; second = 'FACCH1';
    case 1
        first = 'FACCH1'; second = 'VCH';
    case 2
        first = 'VCH'; second = 'FACCH1';
    otherwise
        first = 'VCH'; second = 'VCH';
end
end
