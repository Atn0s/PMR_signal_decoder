function line = formatPdu(pdu, foStr)
%FORMATPDU Format a TETRA DMO PDU/session for terminal output.
if nargin < 2
    foStr = '';
end
typ = char(radio.getField(pdu, 'type', ''));
prefix = sprintf('[%-18s] PROTO=TETRA', typ);
src = textValue(radio.getField(pdu, 'src', 0));
dst = textValue(radio.getField(pdu, 'dst', 0));
mni = textValue(radio.getNestedField(pdu, 'extra.mni', ''));
timing = timingText(pdu);
time = timeText(pdu);

switch typ
    case 'TETRA_DMAC_SYNC'
        line = sprintf('%s SRC=%s DST=%s MNI=%s %s MSG=%s FC=%s DCC=%s%s%s', ...
            prefix, src, dst, mni, timing, ...
            textValue(radio.getField(pdu, 'flco', '')), ...
            textValue(radio.getNestedField(pdu, 'extra.frame_countdown_text', '')), ...
            textValue(radio.getNestedField(pdu, 'extra.dcc', '')), time, foStr);
    case {'TETRA_STCH', 'TETRA_SCHF'}
        secondHalf = radio.getNestedField(pdu, 'extra.second_half_slot_stolen', []);
        if isempty(secondHalf)
            stealText = '';
        else
            stealText = sprintf(' ST2=%d', logical(secondHalf));
        end
        nullPdu = radio.getNestedField(pdu, 'extra.null_pdu', []);
        if isempty(nullPdu)
            nullText = '';
        else
            nullText = sprintf(' NULL=%d', logical(nullPdu));
        end
        line = sprintf('%s SRC=%s DST=%s MNI=%s %s LCH=%s PDU=%s MSG=%s%s%s%s%s', ...
            prefix, src, dst, mni, timing, ...
            textValue(radio.getNestedField(pdu, 'extra.logical_channel', '')), ...
            textValue(radio.getNestedField(pdu, 'extra.pdu_name', '')), ...
            textValue(radio.getField(pdu, 'flco', '')), ...
            stealText, nullText, time, foStr);
    case 'TETRA_TCH_CANDIDATE'
        line = sprintf('%s SRC=%s DST=%s MNI=%s %s LCH=TCH SCHF_ERR=%s/%s STATUS=%s%s%s', ...
            prefix, src, dst, mni, timing, ...
            textValue(radio.getNestedField(pdu, 'extra.schf_block_code_errors', '')), ...
            textValue(radio.getNestedField(pdu, 'extra.schf_tail_errors', '')), ...
            textValue(radio.getNestedField(pdu, 'extra.status', '')), time, foStr);
    case 'TETRA_SESSION'
        dur = radio.getNestedField(pdu, 'extra.duration_s', []);
        if isempty(dur) || isnan(dur)
            durText = '';
        else
            durText = sprintf(' DUR=%.3fs', double(dur));
        end
        line = sprintf('%s SRC=%s DST=%s MNI=%s STATE=%s START=%.3fs END=%.3fs%s CTRL=%s STCH=%s TCH=%s RELEASE=%s%s', ...
            prefix, src, dst, mni, ...
            textValue(radio.getNestedField(pdu, 'extra.state', '')), ...
            double(radio.getNestedField(pdu, 'extra.start_time_s', NaN)), ...
            double(radio.getNestedField(pdu, 'extra.end_time_s', NaN)), ...
            durText, ...
            textValue(radio.getNestedField(pdu, 'extra.control_event_count', 0)), ...
            textValue(radio.getNestedField(pdu, 'extra.stch_event_count', 0)), ...
            textValue(radio.getNestedField(pdu, 'extra.tch_candidate_count', 0)), ...
            textValue(radio.getNestedField(pdu, 'extra.release_message', '')), foStr);
    otherwise
        line = sprintf('%s SRC=%s DST=%s %s FLCO=%s%s%s', ...
            prefix, src, dst, timing, textValue(radio.getField(pdu, 'flco', '')), time, foStr);
end
end

function txt = timingText(pdu)
fn = radio.getNestedField(pdu, 'extra.frame_number', []);
tn = radio.getNestedField(pdu, 'extra.slot_number', []);
if isempty(fn) || isempty(tn) || any(isnan([double(fn), double(tn)]))
    txt = '';
else
    txt = sprintf('FN=%d TN=%d', double(fn), double(tn));
end
end

function txt = timeText(pdu)
t = radio.getNestedField(pdu, 'extra.start_time_s', []);
if isempty(t) || isnan(t)
    txt = '';
else
    txt = sprintf(' T=%.3fs', double(t));
end
end

function text = textValue(value)
if isempty(value)
    text = '';
elseif isnumeric(value)
    if isscalar(value)
        if isnan(value)
            text = 'n/a';
        elseif abs(value - round(value)) < eps
            text = sprintf('%.0f', value);
        else
            text = sprintf('%g', value);
        end
    else
        text = mat2str(value);
    end
elseif islogical(value)
    text = num2str(double(value));
elseif isstring(value)
    text = char(value);
elseif ischar(value)
    text = value;
else
    text = char(string(value));
end
end
