function session = sessionInit()
%SESSIONINIT Create dPMR CCH ID assembler state.
session = struct('dst', '', 'src', '', 'records', containers.Map('KeyType', 'double', 'ValueType', 'any'));
end

