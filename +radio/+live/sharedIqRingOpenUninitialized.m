function mapping = sharedIqRingOpenUninitialized(descriptor)
%SHAREDIQRINGOPENUNINITIALIZED Map a newly allocated ring before its header.
[format, ~] = radio.live.sharedIqRingLayout(descriptor);
mapping = memmapfile(descriptor.path, ...
    'Writable', true, 'Format', format, 'Repeat', 1);
end
