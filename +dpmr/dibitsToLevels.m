function levels = dibitsToLevels(dibits)
%DIBITSTOLEVELS Map dPMR dibit symbols 0..3 to nominal levels.
c = dpmr.constants();
idx = double(dibits(:)) + 1;
levels = c.dibitLevels(idx).';
end

