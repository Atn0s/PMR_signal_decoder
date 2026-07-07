function tbl = pduTable(pdus)
%PDUTABLE Convert decoded PDUs to a scan-friendly table.
pdus = radio.normalizePdus(pdus);
n = numel(pdus);
protocol = strings(n, 1);
type = strings(n, 1);
src = strings(n, 1);
dst = strings(n, 1);
flco = strings(n, 1);
foHz = nan(n, 1);
for k = 1:n
    protocol(k) = string(radio.getField(pdus(k), 'protocol', ''));
    type(k) = string(radio.getField(pdus(k), 'type', ''));
    src(k) = string(radio.getField(pdus(k), 'src', ''));
    dst(k) = string(radio.getField(pdus(k), 'dst', ''));
    flco(k) = string(radio.getField(pdus(k), 'flco', ''));
    fo = radio.getField(pdus(k), 'fo_hz', []);
    if ~isempty(fo)
        foHz(k) = double(fo);
    end
end
tbl = table(protocol, type, src, dst, flco, foHz);
end

