function sharedIqRingDelete(descriptor)
%SHAREDIQRINGDELETE Remove a no-longer-referenced ring backing file.
if isempty(descriptor) || ~isstruct(descriptor) || ...
        ~isfield(descriptor, 'path')
    return;
end
if exist(descriptor.path, 'file') == 2
    try, delete(descriptor.path); catch, end
end
end
