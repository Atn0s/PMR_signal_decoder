function [y, up, down] = resampleTo(x, sourceFs, targetFs)
%RESAMPLETO Polyphase rational resampling helper.
up = round(targetFs);
down = round(sourceFs);
g = gcd(up, down);
up = up / g;
down = down / g;

if up == down
    y = x(:);
    return;
end

if exist('resample', 'file') ~= 2
    error('common:resampleTo:MissingToolbox', ...
        'resample() is required for sample-rate conversion.');
end
y = resample(x(:), up, down);
end
