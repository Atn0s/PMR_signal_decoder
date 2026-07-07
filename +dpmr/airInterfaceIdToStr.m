function text = airInterfaceIdToStr(aiId)
%AIRINTERFACEIDTOSTR Convert dPMR air interface ID to display text.
weights = [1464100, 146410, 14641, 1331, 121, 11, 1];
value = double(aiId);
chars = strings(1, numel(weights));
for k = 1:numel(weights)
    digit = floor(value / weights(k));
    value = mod(value, weights(k));
    if digit == 10
        chars(k) = "*";
    else
        chars(k) = string(digit);
    end
end
text = char(strjoin(chars, ''));
end

