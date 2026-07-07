function q = shellQuote(value)
%SHELLQUOTE Quote one command-line token for POSIX shells.
s = char(value);
s = strrep(s, '\', '\\');
s = strrep(s, '"', '\"');
q = ['"' s '"'];
end

