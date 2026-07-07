function name = flcoName(value)
%FLCONAME DMR FLCO display name.
switch double(value)
    case 0
        name = 'GroupVoiceChannelUser';
    case 3
        name = 'UnitToUnitVoiceChannelUser';
    case 4
        name = 'TalkerAliasHeader';
    case 5
        name = 'TalkerAliasBlock1';
    case 6
        name = 'TalkerAliasBlock2';
    case 7
        name = 'TalkerAliasBlock3';
    case 8
        name = 'GPSInfo';
    case 48
        name = 'TerminatorDataLinkControl';
    otherwise
        name = sprintf('UNKNOWN_0x%02X', value);
end
end

