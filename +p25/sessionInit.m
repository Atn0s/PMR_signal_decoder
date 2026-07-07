function session = sessionInit()
%SESSIONINIT Create P25 call session state.
session = struct('active', false, 'nac', [], 'src', 0, 'dst', 0, ...
    'is_group', false, 'first_fs', [], 'ldu_count', 0);
end

