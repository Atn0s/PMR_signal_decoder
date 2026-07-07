function scale = defaultIqScale(dtype)
%DEFAULTIQSCALE Return the signed full-scale divisor for an IQ dtype.
if nargin < 1 || isempty(dtype)
    dtype = 'int16';
end

name = lower(char(dtype));
switch name
    case {'int8', 'integer*1'}
        scale = 128.0;
    case {'int16', 'integer*2'}
        scale = 32768.0;
    case {'int32', 'integer*4'}
        scale = 2147483648.0;
    case {'single', 'float32', 'double', 'float64'}
        scale = 1.0;
    otherwise
        error('common:defaultIqScale:UnsupportedDType', ...
            'Unsupported IQ dtype: %s', name);
end
end

