results_dir = getenv('STERN_RESULTS_DIR');
assert(~isempty(results_dir), 'STERN_RESULTS_DIR is not defined.');

mat_dir = fullfile(results_dir, 'mat');
table_dir = fullfile(results_dir, 'tables');
summary_dir = fullfile(results_dir, 'summaries');
if ~isfolder(table_dir), mkdir(table_dir); end
if ~isfolder(summary_dir), mkdir(summary_dir); end

tfr_file = fullfile(mat_dir, 'stern_subject_level_tfr_db.mat');
erp_file = fullfile(mat_dir, 'stern_all_channel_subject_erp.mat');
assert(isfile(tfr_file), 'Missing %s', tfr_file);
assert(isfile(erp_file), 'Missing %s', erp_file);

L = load(tfr_file);
E = load(erp_file, 'chanlocs', 'scalp_labels');

tf_db = double(L.tf_db);
freq_hz = double(L.freq_hz(:)');
time_s = double(L.time_s(:)');
labels = cellstr(string(L.labels));
conditions = cellstr(string(L.conditions));
subjects = cellstr(string(L.subjects));
chanlocs = E.chanlocs;
erp_labels = cellstr(string(E.scalp_labels));

assert(isequal(size(tf_db), [3 13 69 14 50]), 'Unexpected TFR dimensions.');
assert(all(isfinite(tf_db), 'all'), 'Non-finite TFR values.');
assert(isequal(upper(string(labels)), upper(string(erp_labels))), 'ERP/TFR channel labels differ.');
assert(numel(chanlocs) == 69, 'Unexpected channel-location count.');

condition_names = {'Memorize_minus_Ignore', 'Probe_minus_Memorize', 'Probe_minus_Ignore'};
condition_pretty = {'Memorize - Ignore', 'Probe - Memorize', 'Probe - Ignore'};
condition_pairs = [2 1; 3 2; 3 1];
stat_files = { ...
    fullfile(mat_dir, 'stern_tf_cluster_Memorize_minus_Ignore.mat'), ...
    fullfile(mat_dir, 'stern_tf_cluster_Probe_minus_Memorize.mat'), ...
    fullfile(mat_dir, 'stern_tf_cluster_Probe_minus_Ignore.mat')};

all_rep = table();
all_topo = table();
all_subject = table();
all_count = table();
all_sensor = table();
all_meta = table();

for k = 1:3
    assert(isfile(stat_files{k}), 'Missing %s', stat_files{k});
    S = load(stat_files{k});
    stat = S.stat;
    [sig_mask, pvalues, signs] = significant_union(stat, 0.05);
    assert(any(sig_mask, 'all'), 'No significant cluster for %s.', condition_names{k});
    assert(numel(pvalues) == 1, 'Expected exactly one significant cluster for %s.', condition_names{k});

    freq_idx = match_axis(freq_hz, double(stat.freq(:)'));
    time_idx = match_axis(time_s, double(stat.time(:)'));
    a = condition_pairs(k, 1);
    b = condition_pairs(k, 2);
    subject_diff = squeeze(tf_db(a, :, :, freq_idx, time_idx) - tf_db(b, :, :, freq_idx, time_idx));
    assert(isequal(size(subject_diff), [13 69 numel(stat.freq) numel(stat.time)]), 'Unexpected subject difference dimensions.');
    group_diff = squeeze(mean(subject_diff, 1, 'omitnan'));

    candidate = abs(stat.stat);
    candidate(~sig_mask) = -inf;
    [~, peak_linear] = max(candidate, [], 'all', 'linear');
    [peak_ch, peak_f, peak_t] = ind2sub(size(stat.stat), peak_linear);
    peak_channel = string(stat.label{peak_ch});
    peak_freq = double(stat.freq(peak_f));
    peak_time = double(stat.time(peak_t));
    peak_t_value = double(stat.stat(peak_linear));

    rep_values = squeeze(group_diff(peak_ch, :, :));
    rep_mask = squeeze(sig_mask(peak_ch, :, :));
    [TT, FF] = meshgrid(double(stat.time(:)'), double(stat.freq(:)'));
    rep = table( ...
        repmat(string(condition_names{k}), numel(TT), 1), ...
        repmat(string(condition_pretty{k}), numel(TT), 1), ...
        repmat(peak_channel, numel(TT), 1), ...
        FF(:), TT(:), rep_values(:), logical(rep_mask(:)), ...
        'VariableNames', {'contrast','contrast_pretty','channel','frequency_hz','time_s','difference_db','in_corrected_cluster'});
    all_rep = [all_rep; rep]; %#ok<AGROW>

    topo_values = squeeze(group_diff(:, peak_f, peak_t));
    topo_mask = squeeze(sig_mask(:, peak_f, peak_t));
    theta = nan(69,1); radius = nan(69,1);
    for ch = 1:69
        if isfield(chanlocs, 'theta') && ~isempty(chanlocs(ch).theta), theta(ch) = double(chanlocs(ch).theta); end
        if isfield(chanlocs, 'radius') && ~isempty(chanlocs(ch).radius), radius(ch) = double(chanlocs(ch).radius); end
    end
    assert(all(isfinite(theta)) && all(isfinite(radius)), 'Non-finite theta/radius channel coordinates.');
    topo = table( ...
        repmat(string(condition_names{k}), 69, 1), ...
        repmat(string(condition_pretty{k}), 69, 1), ...
        string(labels(:)), theta, radius, topo_values(:), logical(topo_mask(:)), ...
        'VariableNames', {'contrast','contrast_pretty','channel','theta_deg','radius','difference_db_at_peak','in_corrected_cluster_at_peak'});
    all_topo = [all_topo; topo]; %#ok<AGROW>

    cluster_subject = nan(13,1);
    for s = 1:13
        x = squeeze(subject_diff(s,:,:,:));
        cluster_subject(s) = mean(x(sig_mask), 'omitnan');
    end
    subj = table( ...
        repmat(string(condition_names{k}), 13, 1), ...
        string(subjects(:)), cluster_subject, ...
        'VariableNames', {'contrast','subject','cluster_mean_difference_db'});
    all_subject = [all_subject; subj]; %#ok<AGROW>

    count = squeeze(sum(sig_mask, 1));
    sensor = squeeze(mean(group_diff, 1, 'omitnan'));
    cnt = table( ...
        repmat(string(condition_names{k}), numel(TT), 1), FF(:), TT(:), double(count(:)), ...
        'VariableNames', {'contrast','frequency_hz','time_s','cluster_member_channel_count'});
    sen = table( ...
        repmat(string(condition_names{k}), numel(TT), 1), FF(:), TT(:), sensor(:), ...
        'VariableNames', {'contrast','frequency_hz','time_s','sensor_average_difference_db'});
    all_count = [all_count; cnt]; %#ok<AGROW>
    all_sensor = [all_sensor; sen]; %#ok<AGROW>

    p_numeric = double(pvalues(1));
    if p_numeric == 0
        p_display = "<0.000122";
    else
        p_display = string(sprintf('%.6f', p_numeric));
    end
    meta = table( ...
        string(condition_names{k}), string(condition_pretty{k}), string(signs(1)), p_numeric, p_display, ...
        peak_channel, peak_freq, peak_time, peak_t_value, nnz(sig_mask), ...
        sum(any(sig_mask,[2 3])), 100*nnz(squeeze(any(sig_mask,1)))/numel(squeeze(any(sig_mask,1))), ...
        'VariableNames', {'contrast','contrast_pretty','cluster_sign','cluster_p','cluster_p_display','peak_channel','peak_frequency_hz','peak_time_s','peak_t','cluster_cft_samples','active_channels','ft_any_channel_fill_percent'});
    all_meta = [all_meta; meta]; %#ok<AGROW>
end

writetable(all_rep, fullfile(table_dir, 'stern_tf_visualization_representative_tfr.tsv'), 'FileType','text','Delimiter','\t');
writetable(all_topo, fullfile(table_dir, 'stern_tf_visualization_peak_topographies.tsv'), 'FileType','text','Delimiter','\t');
writetable(all_subject, fullfile(table_dir, 'stern_tf_visualization_subject_cluster_values.tsv'), 'FileType','text','Delimiter','\t');
writetable(all_count, fullfile(table_dir, 'stern_tf_visualization_channel_count.tsv'), 'FileType','text','Delimiter','\t');
writetable(all_sensor, fullfile(table_dir, 'stern_tf_visualization_sensor_average_descriptive.tsv'), 'FileType','text','Delimiter','\t');
writetable(all_meta, fullfile(table_dir, 'stern_tf_visualization_metadata.tsv'), 'FileType','text','Delimiter','\t');

% Descriptive band/window sensitivity for the primary contrast only.
P = load(stat_files{1}); stat = P.stat;
freq_idx = match_axis(freq_hz, double(stat.freq(:)'));
time_idx = match_axis(time_s, double(stat.time(:)'));
subject_diff = squeeze(tf_db(2, :, :, freq_idx, time_idx) - tf_db(1, :, :, freq_idx, time_idx));
band_names = {'theta','alpha','beta'}; band_limits = [4 7; 8 12; 14 30];
window_names = {'0-0.3 s','0.3-0.8 s','0.8-1.4 s'}; window_limits = [0 0.3; 0.3 0.8; 0.8 1.4];
rows = table();
for b = 1:3
    fm = stat.freq >= band_limits(b,1) & stat.freq <= band_limits(b,2);
    for w = 1:3
        tm = stat.time >= window_limits(w,1) & stat.time <= window_limits(w,2);
        values = squeeze(mean(subject_diff(:,:,fm,tm), [2 3 4], 'omitnan'));
        r = table(string(band_names{b}), string(window_names{w}), mean(values), sum(values<0), 13, ...
            'VariableNames', {'band','window','group_mean_difference_db','subjects_memorize_lt_ignore','n_subjects'});
        rows = [rows; r]; %#ok<AGROW>
    end
end
writetable(rows, fullfile(table_dir, 'stern_tf_visualization_band_window_descriptive.tsv'), 'FileType','text','Delimiter','\t');

summary_file = fullfile(summary_dir, 'stern_tf_visualization_redesign_summary.txt');
fid = fopen(summary_file, 'w'); assert(fid ~= -1);
fprintf(fid, 'STERN TF VISUALIZATION REDESIGN EXPORT\n');
fprintf(fid, 'No TFR or permutation statistics were recomputed.\n');
fprintf(fid, 'Primary peak: CP3, 8 Hz, 0.40 s expected from validated inputs.\n');
fprintf(fid, 'Topographies are exact peak-bin snapshots, not bounding-box averages.\n');
fprintf(fid, 'Sensor-average tables are descriptive only and carry no inferential mask.\n');
fprintf(fid, 'Subject cluster means are post-selection descriptive summaries, not independent tests.\n');
fclose(fid);

fprintf('TF_VISUALIZATION_TABLE_EXPORT_PASSED\n');
fprintf('TABLE_DIR=%s\n', table_dir);
fprintf('SUMMARY=%s\n', summary_file);

function idx = match_axis(full_axis, target_axis)
idx = zeros(1,numel(target_axis));
for i = 1:numel(target_axis)
    [d,j] = min(abs(full_axis-target_axis(i)));
    assert(d < 1e-9, 'Axis matching failed.');
    idx(i)=j;
end
end

function [mask,pvalues,signs] = significant_union(stat,alpha)
mask = false(size(stat.stat)); pvalues=[]; signs=strings(0,1);
if isfield(stat,'posclusters') && ~isempty(stat.posclusters)
    for i=1:numel(stat.posclusters)
        p=stat.posclusters(i).prob;
        if p<alpha, mask=mask|(stat.posclusterslabelmat==i); pvalues(end+1,1)=p; signs(end+1,1)="positive"; end %#ok<AGROW>
    end
end
if isfield(stat,'negclusters') && ~isempty(stat.negclusters)
    for i=1:numel(stat.negclusters)
        p=stat.negclusters(i).prob;
        if p<alpha, mask=mask|(stat.negclusterslabelmat==i); pvalues(end+1,1)=p; signs(end+1,1)="negative"; end %#ok<AGROW>
    end
end
end
