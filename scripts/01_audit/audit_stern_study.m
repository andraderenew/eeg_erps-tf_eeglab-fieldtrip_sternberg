eeglab_dir = getenv('EEGLAB_DIR');
data_root  = getenv('STERN_DATA_ROOT');
output_dir = getenv('STERN_AUDIT_DIR');

assert(isfile(fullfile(eeglab_dir, 'eeglab.m')), ...
    'EEGLAB not found: %s', eeglab_dir);
assert(isfolder(data_root), ...
    'STERN data root not found: %s', data_root);

if ~isfolder(output_dir)
    mkdir(output_dir);
end

cd(eeglab_dir);
eeglab nogui;

subjects = arrayfun(@(x) sprintf('S%02d', x), 1:13, 'UniformOutput', false);
conditions = {'Ignore', 'Memorize', 'Probe'};

dataset_tsv = fullfile(output_dir, 'stern_dataset_inventory.tsv');
event_tsv   = fullfile(output_dir, 'stern_event_inventory.tsv');
epoch_tsv   = fullfile(output_dir, 'stern_epoch_event_patterns.tsv');
summary_txt = fullfile(output_dir, 'stern_audit_summary.txt');

fid_ds = fopen(dataset_tsv, 'w');
fid_ev = fopen(event_tsv, 'w');
fid_ep = fopen(epoch_tsv, 'w');
assert(fid_ds ~= -1 && fid_ev ~= -1 && fid_ep ~= -1, ...
    'Could not create one or more audit output files.');

fprintf(fid_ds, ['subject\tcondition\tfile\tchannels\tsamples_per_epoch\ttrials\t' ...
    'sampling_rate_hz\txmin_s\txmax_s\tevents\thas_ica\tn_ica_components\t' ...
    'finite_fraction\tmean_uv\tstd_uv\trms_uv\tmax_abs_uv\n']);

fprintf(fid_ev, 'subject\tcondition\tevent_type\tcount\n');
fprintf(fid_ep, 'subject\tcondition\tepoch\tordered_event_types\tordered_event_latencies_ms\n');

n_datasets = 0;
n_missing = 0;
total_trials = 0;
total_events = 0;
all_channels = [];
all_srates = [];
all_pnts = [];
all_xmin = [];
all_xmax = [];

for s = 1:numel(subjects)
    subject = subjects{s};

    for c = 1:numel(conditions)
        condition = conditions{c};
        set_file = fullfile(data_root, subject, [condition '.set']);

        if ~isfile(set_file)
            warning('Missing dataset: %s', set_file);
            n_missing = n_missing + 1;
            continue;
        end

        fprintf('\n=== AUDITING %s %s ===\n', subject, condition);

        EEG = pop_loadset('filename', [condition '.set'], ...
                          'filepath', fullfile(data_root, subject));
        EEG = eeg_checkset(EEG);

        n_datasets = n_datasets + 1;
        total_trials = total_trials + EEG.trials;
        total_events = total_events + numel(EEG.event);

        all_channels(end+1) = EEG.nbchan; %#ok<SAGROW>
        all_srates(end+1) = EEG.srate; %#ok<SAGROW>
        all_pnts(end+1) = EEG.pnts; %#ok<SAGROW>
        all_xmin(end+1) = EEG.xmin; %#ok<SAGROW>
        all_xmax(end+1) = EEG.xmax; %#ok<SAGROW>

        has_ica = ~isempty(EEG.icaweights);
        if has_ica
            n_ica = size(EEG.icaweights, 1);
        else
            n_ica = 0;
        end

        values = double(EEG.data(:));
        finite_mask = isfinite(values);
        finite_fraction = mean(finite_mask);

        if any(finite_mask)
            finite_values = values(finite_mask);
            mean_uv = mean(finite_values);
            std_uv = std(finite_values);
            rms_uv = sqrt(mean(finite_values .^ 2));
            max_abs_uv = max(abs(finite_values));
        else
            mean_uv = NaN;
            std_uv = NaN;
            rms_uv = NaN;
            max_abs_uv = NaN;
        end

        fprintf(fid_ds, ...
            '%s\t%s\t%s\t%d\t%d\t%d\t%.6f\t%.6f\t%.6f\t%d\t%d\t%d\t%.12f\t%.9f\t%.9f\t%.9f\t%.9f\n', ...
            subject, condition, set_file, EEG.nbchan, EEG.pnts, EEG.trials, ...
            EEG.srate, EEG.xmin, EEG.xmax, numel(EEG.event), ...
            has_ica, n_ica, finite_fraction, mean_uv, std_uv, rms_uv, max_abs_uv);

        event_types = cell(1, numel(EEG.event));
        for e = 1:numel(EEG.event)
            event_types{e} = normalize_event_type(EEG.event(e).type);
        end

        [unique_types, ~, group_index] = unique(event_types);
        for u = 1:numel(unique_types)
            fprintf(fid_ev, '%s\t%s\t%s\t%d\n', ...
                subject, condition, unique_types{u}, sum(group_index == u));
        end

        for ep = 1:EEG.trials
            types = {};
            latencies = [];

            if isfield(EEG.epoch, 'eventtype')
                raw_types = EEG.epoch(ep).eventtype;
                if ~iscell(raw_types)
                    raw_types = {raw_types};
                end
                types = cellfun(@normalize_event_type, raw_types, 'UniformOutput', false);
            end

            if isfield(EEG.epoch, 'eventlatency')
                raw_latencies = EEG.epoch(ep).eventlatency;
                if ~iscell(raw_latencies)
                    raw_latencies = {raw_latencies};
                end
                latencies = nan(1, numel(raw_latencies));
                for k = 1:numel(raw_latencies)
                    value = raw_latencies{k};
                    if isnumeric(value) && isscalar(value)
                        latencies(k) = double(value);
                    elseif ischar(value) || isstring(value)
                        latencies(k) = str2double(value);
                    end
                end
            end

            n_pair = min(numel(types), numel(latencies));
            if n_pair > 0
                types = types(1:n_pair);
                latencies = latencies(1:n_pair);
                [latencies, order] = sort(latencies);
                types = types(order);
            end

            type_text = join_for_tsv(types, '|');
            latency_text = join_numeric_for_tsv(latencies, '|');

            fprintf(fid_ep, '%s\t%s\t%d\t%s\t%s\n', ...
                subject, condition, ep, type_text, latency_text);
        end

        clear EEG values finite_values finite_mask;
    end
end

fclose(fid_ds);
fclose(fid_ev);
fclose(fid_ep);

fid = fopen(summary_txt, 'w');
assert(fid ~= -1, 'Could not create summary file.');

fprintf(fid, '=== STERN FULL AUDIT SUMMARY ===\n');
fprintf(fid, 'Data root: %s\n', data_root);
fprintf(fid, 'Datasets audited: %d\n', n_datasets);
fprintf(fid, 'Datasets missing: %d\n', n_missing);
fprintf(fid, 'Total trials: %d\n', total_trials);
fprintf(fid, 'Total events: %d\n', total_events);

if ~isempty(all_channels)
    fprintf(fid, 'Unique channel counts: %s\n', mat2str(unique(all_channels)));
    fprintf(fid, 'Unique sampling rates: %s\n', mat2str(unique(all_srates)));
    fprintf(fid, 'Unique samples per epoch: %s\n', mat2str(unique(all_pnts)));
    fprintf(fid, 'Unique epoch start times: %s\n', mat2str(unique(all_xmin)));
    fprintf(fid, 'Unique epoch end times: %s\n', mat2str(unique(all_xmax)));
end

fprintf(fid, '\nOutput files:\n');
fprintf(fid, '- %s\n', dataset_tsv);
fprintf(fid, '- %s\n', event_tsv);
fprintf(fid, '- %s\n', epoch_tsv);
fclose(fid);

fprintf('\n=== STERN FULL AUDIT PASSED ===\n');
fprintf('DATASETS_AUDITED=%d\n', n_datasets);
fprintf('DATASETS_MISSING=%d\n', n_missing);
fprintf('TOTAL_TRIALS=%d\n', total_trials);
fprintf('TOTAL_EVENTS=%d\n', total_events);
fprintf('SUMMARY=%s\n', summary_txt);
fprintf('DATASET_TABLE=%s\n', dataset_tsv);
fprintf('EVENT_TABLE=%s\n', event_tsv);
fprintf('EPOCH_TABLE=%s\n', epoch_tsv);

function text = normalize_event_type(value)
    if isnumeric(value)
        text = num2str(value);
    elseif isstring(value)
        text = char(value);
    elseif ischar(value)
        text = value;
    else
        text = class(value);
    end

    text = strrep(text, sprintf('\t'), ' ');
    text = strrep(text, sprintf('\n'), ' ');
    text = strtrim(text);

    if isempty(text)
        text = '<EMPTY>';
    end
end

function text = join_for_tsv(values, delimiter)
    if isempty(values)
        text = '';
        return;
    end
    text = strjoin(values, delimiter);
end

function text = join_numeric_for_tsv(values, delimiter)
    if isempty(values)
        text = '';
        return;
    end

    parts = cell(1, numel(values));
    for i = 1:numel(values)
        if isnan(values(i))
            parts{i} = 'NaN';
        else
            parts{i} = sprintf('%.6f', values(i));
        end
    end
    text = strjoin(parts, delimiter);
end
