results_dir = getenv('STERN_RESULTS_DIR');

assert(~isempty(results_dir), 'STERN_RESULTS_DIR is not defined.');

erp_mat_file = fullfile(results_dir, 'mat', 'stern_all_channel_subject_erp.mat');
direct_oz_table_file = fullfile(results_dir, 'tables', 'stern_OZ_subject_level_erp.tsv');
cluster_table_file = fullfile(results_dir, 'tables', 'stern_erp_cluster_results.tsv');

assert(isfile(erp_mat_file), 'ERP MAT file not found: %s', erp_mat_file);
assert(isfile(direct_oz_table_file), ...
    'Direct Oz ERP table not found: %s', direct_oz_table_file);
assert(isfile(cluster_table_file), ...
    'Cluster table not found: %s', cluster_table_file);

loaded = load(erp_mat_file);

erp_uv       = double(loaded.erp_uv);
times_ms     = double(loaded.times_ms(:));
scalp_labels = cellstr(string(loaded.scalp_labels));
conditions   = cellstr(string(loaded.conditions));
subjects     = cellstr(string(loaded.subjects));

n_conditions = size(erp_uv, 1);
n_subjects   = size(erp_uv, 2);
n_times      = numel(times_ms);

assert(isequal(size(erp_uv), [3 13 69 151]), ...
    'Unexpected ERP array size: %s', mat2str(size(erp_uv)));
assert(all(isfinite(erp_uv), 'all'), ...
    'ERP array contains non-finite values.');
assert(n_conditions == 3 && n_subjects == 13 && n_times == 151, ...
    'Unexpected ERP dimensions.');
assert(all(diff(times_ms) > 0), ...
    'ERP time vector is not strictly increasing.');
assert(abs(times_ms(1) + 200) < 1e-6 && ...
       abs(times_ms(end) - 1000) < 1e-6, ...
    'Unexpected ERP time range.');
assert(isequal(string(conditions(:))', ...
    ["Ignore" "Memorize" "Probe"]), ...
    'Unexpected condition order.');

table_dir = fullfile(results_dir, 'tables');
summary_dir = fullfile(results_dir, 'summaries');
if ~isfolder(table_dir), mkdir(table_dir); end
if ~isfolder(summary_dir), mkdir(summary_dir); end

fprintf('\n=== VALIDATING OZ ERP NUMERIC PROVENANCE ===\n');

oz_idx = find(strcmpi(scalp_labels, 'OZ'), 1);
assert(~isempty(oz_idx), 'OZ was not found.');

oz_values = squeeze(erp_uv(:, :, oz_idx, :));
assert(isequal(size(oz_values), [3 13 151]), ...
    'Unexpected Oz ERP size: %s', mat2str(size(oz_values)));

direct_table = readtable(direct_oz_table_file, ...
    'FileType', 'text', 'Delimiter', '\t');

required_variables = {'time_ms', 'subject', 'condition', 'amplitude_uv'};
assert(all(ismember(required_variables, ...
    direct_table.Properties.VariableNames)), ...
    'Direct Oz table is missing required columns.');

direct_oz = nan(n_conditions, n_subjects, n_times);
table_subject = string(direct_table.subject);
table_condition = string(direct_table.condition);

for c = 1:n_conditions
    for s = 1:n_subjects
        row_mask = strcmpi(table_condition, conditions{c}) & ...
                   strcmpi(table_subject, subjects{s});
        rows = direct_table(row_mask, :);

        assert(height(rows) == n_times, ...
            'Expected %d direct Oz samples for %s/%s, found %d.', ...
            n_times, conditions{c}, subjects{s}, height(rows));

        [sorted_time, order] = sort(double(rows.time_ms));
        assert(max(abs(sorted_time(:) - times_ms(:))) < 1e-6, ...
            'Direct Oz time vector mismatch for %s/%s.', ...
            conditions{c}, subjects{s});

        direct_oz(c, s, :) = reshape( ...
            double(rows.amplitude_uv(order)), 1, 1, n_times);
    end
end

assert(all(isfinite(direct_oz), 'all'), ...
    'Direct Oz reconstruction contains non-finite values.');

max_direct_difference_uv = max(abs(direct_oz - oz_values), [], 'all');
direct_roundtrip_tolerance_uv = 1e-5;
assert(max_direct_difference_uv < direct_roundtrip_tolerance_uv, ...
    ['All-channel Oz values do not reproduce the independently exported ' ...
     'subject-level Oz table within TSV round-trip tolerance. ' ...
     'Maximum difference: %.12g uV; tolerance: %.12g uV.'], ...
    max_direct_difference_uv, direct_roundtrip_tolerance_uv);

baseline_mask = times_ms >= -200 & times_ms <= 0;
subject_baseline_uv = mean(oz_values(:, :, baseline_mask), 3);
max_abs_subject_baseline_uv = max(abs(subject_baseline_uv), [], 'all');
assert(max_abs_subject_baseline_uv < 2, ...
    'Baseline residual is unexpectedly large at Oz: %.6f uV.', ...
    max_abs_subject_baseline_uv);

oz_mean = squeeze(mean(oz_values, 2));
oz_sem  = squeeze(std(oz_values, 0, 2)) ./ sqrt(n_subjects);

assert(all(isfinite(oz_mean), 'all') && all(isfinite(oz_sem), 'all'), ...
    'Oz mean or SEM contains non-finite values.');

max_abs_subject_oz_uv = max(abs(oz_values), [], 'all');
max_abs_grand_mean_uv = max(abs(oz_mean), [], 'all');
max_adjacent_grand_change_uv = max(abs(diff(oz_mean, 1, 2)), [], 'all');

assert(max_abs_subject_oz_uv < 500, ...
    'Subject-level Oz amplitude exceeds safety threshold: %.6f uV.', ...
    max_abs_subject_oz_uv);
assert(max_abs_grand_mean_uv < 100, ...
    'Grand-average Oz amplitude exceeds safety threshold: %.6f uV.', ...
    max_abs_grand_mean_uv);
assert(max_adjacent_grand_change_uv < 50, ...
    'Grand-average Oz adjacent-sample change exceeds threshold: %.6f uV.', ...
    max_adjacent_grand_change_uv);

fprintf('DIRECT_OZ_MAX_DIFFERENCE_UV=%.12g\n', max_direct_difference_uv);
fprintf('DIRECT_OZ_ROUNDTRIP_TOLERANCE_UV=%.12g\n', direct_roundtrip_tolerance_uv);
fprintf('MAX_ABS_SUBJECT_BASELINE_UV=%.9f\n', max_abs_subject_baseline_uv);
fprintf('MAX_ABS_SUBJECT_OZ_UV=%.9f\n', max_abs_subject_oz_uv);
fprintf('MAX_ABS_GRAND_MEAN_UV=%.9f\n', max_abs_grand_mean_uv);
fprintf('MAX_ADJACENT_GRAND_CHANGE_UV=%.9f\n', max_adjacent_grand_change_uv);

fprintf('\n=== EXPORTING OZ GRAND-AVERAGE WAVEFORM TABLE ===\n');

oz_table = table( ...
    times_ms, ...
    oz_mean(1, :)', oz_sem(1, :)', ...
    oz_mean(2, :)', oz_sem(2, :)', ...
    oz_mean(3, :)', oz_sem(3, :)', ...
    'VariableNames', { ...
        'time_ms', ...
        'Ignore_mean_uv', 'Ignore_sem_uv', ...
        'Memorize_mean_uv', 'Memorize_sem_uv', ...
        'Probe_mean_uv', 'Probe_sem_uv'});

oz_table_file = fullfile(table_dir, 'stern_OZ_grand_average_erp_final.tsv');
writetable(oz_table, oz_table_file, 'FileType', 'text', 'Delimiter', '\t');

fprintf('\n=== EXPORTING REPRESENTATIVE ERP WAVEFORM TABLE ===\n');

contrast_names = { ...
    'Memorize_minus_Ignore', ...
    'Probe_minus_Memorize', ...
    'Probe_minus_Ignore'};
contrast_labels = { ...
    'Memorize - Ignore', ...
    'Probe - Memorize', ...
    'Probe - Ignore'};
contrast_pairs = [2 1; 3 2; 3 1];
stat_files = { ...
    'stern_erp_cluster_Memorize_minus_Ignore.mat', ...
    'stern_erp_cluster_Probe_minus_Memorize.mat', ...
    'stern_erp_cluster_Probe_minus_Ignore.mat'};

contrast_col = strings(0, 1);
contrast_label_col = strings(0, 1);
channel_col = strings(0, 1);
selection_col = strings(0, 1);
selected_time_col = zeros(0, 1);
condition_col = strings(0, 1);
time_col = zeros(0, 1);
mean_col = zeros(0, 1);
sem_col = zeros(0, 1);

for k = 1:3
    stat_path = fullfile(results_dir, 'mat', stat_files{k});
    assert(isfile(stat_path), 'Statistical MAT file not found: %s', stat_path);

    stat_loaded = load(stat_path);
    stat = stat_loaded.stat;

    significant_mask = false(size(stat.stat));
    if isfield(stat, 'mask')
        significant_mask = logical(stat.mask);
    end

    if any(significant_mask, 'all')
        candidate = abs(stat.stat);
        candidate(~significant_mask) = -inf;
        [~, linear_index] = max(candidate, [], 'all', 'linear');
        selection_label = 'peak inside corrected cluster';
    else
        [~, linear_index] = max(abs(stat.stat), [], 'all', 'linear');
        selection_label = 'largest uncorrected absolute t';
    end

    [channel_index, time_index] = ind2sub(size(stat.stat), linear_index);
    channel_label = string(stat.label{channel_index});
    selected_time_ms = double(stat.time(time_index)) * 1000;

    source_channel_index = find(strcmpi(scalp_labels, channel_label), 1);
    assert(~isempty(source_channel_index), ...
        'Could not resolve representative channel %s.', channel_label);

    pair = contrast_pairs(k, :);

    for j = 1:2
        condition_index = pair(j);
        values = squeeze(erp_uv(condition_index, :, source_channel_index, :));

        assert(isequal(size(values), [13 151]), ...
            'Unexpected representative waveform size.');
        assert(all(isfinite(values), 'all'), ...
            'Representative waveform contains non-finite values.');

        waveform_mean = mean(values, 1);
        waveform_sem = std(values, 0, 1) ./ sqrt(n_subjects);
        assert(all(isfinite(waveform_mean)) && all(isfinite(waveform_sem)), ...
            'Representative mean or SEM contains non-finite values.');

        n = n_times;
        contrast_col(end+1:end+n, 1) = repmat(string(contrast_names{k}), n, 1);
        contrast_label_col(end+1:end+n, 1) = repmat(string(contrast_labels{k}), n, 1);
        channel_col(end+1:end+n, 1) = repmat(channel_label, n, 1);
        selection_col(end+1:end+n, 1) = repmat(string(selection_label), n, 1);
        selected_time_col(end+1:end+n, 1) = selected_time_ms;
        condition_col(end+1:end+n, 1) = repmat(string(conditions{condition_index}), n, 1);
        time_col(end+1:end+n, 1) = times_ms;
        mean_col(end+1:end+n, 1) = waveform_mean(:);
        sem_col(end+1:end+n, 1) = waveform_sem(:);
    end
end

representative_table = table( ...
    contrast_col, contrast_label_col, channel_col, selection_col, ...
    selected_time_col, condition_col, time_col, mean_col, sem_col, ...
    'VariableNames', { ...
        'contrast', 'contrast_label', 'channel', 'selection', ...
        'selected_time_ms', 'condition', 'time_ms', 'mean_uv', 'sem_uv'});

assert(height(representative_table) == 3 * 2 * 151, ...
    'Unexpected representative table height: %d', height(representative_table));

representative_table_file = fullfile( ...
    table_dir, 'stern_erp_representative_waveforms_final.tsv');
writetable(representative_table, representative_table_file, ...
    'FileType', 'text', 'Delimiter', '\t');

fprintf('\n=== CREATING FINAL CLUSTER TABLE ===\n');

cluster_table = readtable(cluster_table_file, 'FileType', 'text', 'Delimiter', '\t');
exact_permutations = 8192;
across_contrast_alpha = 0.05 / 3;
p_display = strings(height(cluster_table), 1);

for i = 1:height(cluster_table)
    if cluster_table.pvalue(i) == 0
        p_display(i) = sprintf('< %.6f', 1 / exact_permutations);
    else
        p_display(i) = sprintf('%.6f', cluster_table.pvalue(i));
    end
end

cluster_table.pvalue_display = p_display;
cluster_table.significant_within_contrast_0_05 = cluster_table.pvalue < 0.05;
cluster_table.significant_across_three_contrasts_0_016667 = ...
    cluster_table.pvalue < across_contrast_alpha;

final_cluster_table_file = fullfile(table_dir, 'stern_erp_cluster_results_final.tsv');
writetable(cluster_table, final_cluster_table_file, ...
    'FileType', 'text', 'Delimiter', '\t');

fprintf('\n=== WRITING ERP FINALIZATION SUMMARY ===\n');

summary_file = fullfile(summary_dir, 'stern_erp_finalization_summary.txt');
fid = fopen(summary_file, 'w');
assert(fid ~= -1, 'Could not create finalization summary: %s', summary_file);

fprintf(fid, '=== STERN ERP FINALIZATION SUMMARY ===\n');
fprintf(fid, 'Subjects: %d\n', n_subjects);
fprintf(fid, 'Conditions: %s\n', strjoin(conditions, ', '));
fprintf(fid, 'Scalp EEG channels: 69\n');
fprintf(fid, 'ERP array: %s\n', mat2str(size(erp_uv)));
fprintf(fid, 'Non-finite values: 0\n');
fprintf(fid, 'Direct Oz table maximum difference: %.12g uV\n', max_direct_difference_uv);
fprintf(fid, 'Direct Oz TSV round-trip tolerance: %.12g uV\n', direct_roundtrip_tolerance_uv);
fprintf(fid, 'Maximum absolute subject baseline residual: %.9f uV\n', max_abs_subject_baseline_uv);
fprintf(fid, 'Maximum absolute subject-level Oz amplitude: %.9f uV\n', max_abs_subject_oz_uv);
fprintf(fid, 'Maximum absolute Oz grand mean: %.9f uV\n', max_abs_grand_mean_uv);
fprintf(fid, 'Maximum adjacent grand-mean change: %.9f uV\n', max_adjacent_grand_change_uv);
fprintf(fid, 'Exact within-subject permutations: %d\n', exact_permutations);
fprintf(fid, 'Minimum reportable non-zero exact probability: %.9f\n', 1 / exact_permutations);
fprintf(fid, 'Additional conservative alpha across 3 contrasts: %.9f\n', across_contrast_alpha);
fprintf(fid, '\nFinal waveform rendering:\n');
fprintf(fid, ['MATLAB validates the ERP arrays and exports complete TSV waveform tables. ' ...
    'Final PNG and SVG figures are rendered from those tables by ' ...
    'render_stern_erp_figures.py using Matplotlib.\n']);
fprintf(fid, 'No final ERP waveform figure is rendered by MATLAB.\n');
fprintf(fid, '\nPrimary event-matched contrast:\n');
fprintf(fid, ['Memorize - Ignore: positive cluster 440-552 ms, p=0.015869; ' ...
    'negative cluster 632-760 ms, p=0.000366.\n']);
fprintf(fid, '\nFinal outputs:\n');
fprintf(fid, 'Oz grand-average table: %s\n', oz_table_file);
fprintf(fid, 'Representative waveform table: %s\n', representative_table_file);
fprintf(fid, 'Cluster table: %s\n', final_cluster_table_file);
fclose(fid);

fprintf('\n=== ERP WAVEFORM TABLE EXPORT PASSED ===\n');
fprintf('OZ_TABLE=%s\n', oz_table_file);
fprintf('REPRESENTATIVE_TABLE=%s\n', representative_table_file);
fprintf('FINAL_CLUSTER_TABLE=%s\n', final_cluster_table_file);
fprintf('SUMMARY=%s\n', summary_file);
