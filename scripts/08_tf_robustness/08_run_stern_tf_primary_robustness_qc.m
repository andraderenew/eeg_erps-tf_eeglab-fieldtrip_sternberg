project_dir = getenv('STERN_PROJECT');

results_dir = fullfile(project_dir, 'results');
tfr_file = fullfile(results_dir, 'mat', 'stern_subject_level_tfr_db.mat');
stat_file = fullfile(results_dir, 'mat', ...
    'stern_tf_cluster_Memorize_minus_Ignore.mat');

figure_dir = fullfile(results_dir, 'figures');
table_dir = fullfile(results_dir, 'tables');
summary_dir = fullfile(results_dir, 'summaries');

assert(isfile(tfr_file), 'TFR file not found: %s', tfr_file);
assert(isfile(stat_file), 'TF statistics file not found: %s', stat_file);

if ~isfolder(figure_dir), mkdir(figure_dir); end
if ~isfolder(table_dir), mkdir(table_dir); end
if ~isfolder(summary_dir), mkdir(summary_dir); end

loaded = load(tfr_file);
stat_loaded = load(stat_file);

tf_db = loaded.tf_db;
freq_hz = double(loaded.freq_hz(:)');
time_s = double(loaded.time_s(:)');
labels = cellstr(string(loaded.labels));
conditions = cellstr(string(loaded.conditions));
subjects = cellstr(string(loaded.subjects));
stat = stat_loaded.stat;

assert(isequal(size(tf_db), [3 13 69 14 50]), ...
    'Unexpected TFR size: %s', mat2str(size(tf_db)));
assert(all(isfinite(tf_db), 'all'), ...
    'TFR array contains non-finite values.');

memorize_index = find(strcmpi(conditions, 'Memorize'), 1);
ignore_index = find(strcmpi(conditions, 'Ignore'), 1);

assert(~isempty(memorize_index) && ~isempty(ignore_index), ...
    'Could not resolve Memorize and Ignore.');

n_subjects = numel(subjects);

fprintf('\n=== IDENTIFYING SIGNIFICANT PRIMARY TF CLUSTER ===\n');

significant_mask = false(size(stat.stat));
cluster_pvalues = [];
cluster_signs = strings(0, 1);
cluster_indices = [];

if isfield(stat, 'posclusters') && ~isempty(stat.posclusters)
    for idx = 1:numel(stat.posclusters)
        probability = stat.posclusters(idx).prob;
        if probability < 0.05
            significant_mask = significant_mask | ...
                (stat.posclusterslabelmat == idx);
            cluster_pvalues(end+1, 1) = probability; %#ok<SAGROW>
            cluster_signs(end+1, 1) = "positive"; %#ok<SAGROW>
            cluster_indices(end+1, 1) = idx; %#ok<SAGROW>
        end
    end
end

if isfield(stat, 'negclusters') && ~isempty(stat.negclusters)
    for idx = 1:numel(stat.negclusters)
        probability = stat.negclusters(idx).prob;
        if probability < 0.05
            significant_mask = significant_mask | ...
                (stat.negclusterslabelmat == idx);
            cluster_pvalues(end+1, 1) = probability; %#ok<SAGROW>
            cluster_signs(end+1, 1) = "negative"; %#ok<SAGROW>
            cluster_indices(end+1, 1) = idx; %#ok<SAGROW>
        end
    end
end

assert(any(significant_mask, 'all'), ...
    'No corrected significant TF cluster was found.');
assert(numel(cluster_pvalues) == 1, ...
    'Expected one significant cluster, found %d.', ...
    numel(cluster_pvalues));

fprintf('SIGNIFICANT_CLUSTER_SIGN=%s\n', cluster_signs(1));
fprintf('SIGNIFICANT_CLUSTER_INDEX=%d\n', cluster_indices(1));
fprintf('SIGNIFICANT_CLUSTER_P=%.12f\n', cluster_pvalues(1));

fprintf('\n=== MATCHING STATISTICAL GRID TO TFR GRID ===\n');

freq_indices = zeros(1, numel(stat.freq));
time_indices = zeros(1, numel(stat.time));

for f = 1:numel(stat.freq)
    [difference, idx] = min(abs(freq_hz - stat.freq(f)));
    assert(difference < 1e-9, ...
        'Could not match frequency %.12f Hz.', stat.freq(f));
    freq_indices(f) = idx;
end

for t = 1:numel(stat.time)
    [difference, idx] = min(abs(time_s - stat.time(t)));
    assert(difference < 1e-9, ...
        'Could not match time %.12f s.', stat.time(t));
    time_indices(t) = idx;
end

subject_difference = squeeze( ...
    tf_db(memorize_index, :, :, freq_indices, time_indices) - ...
    tf_db(ignore_index, :, :, freq_indices, time_indices));
% subject x channel x frequency x time

assert(isequal(size(subject_difference), ...
    [13 size(stat.stat, 1) size(stat.stat, 2) size(stat.stat, 3)]), ...
    'Unexpected subject-difference size: %s', ...
    mat2str(size(subject_difference)));

fprintf('\n=== EXTRACTING SUBJECT-LEVEL CLUSTER EFFECTS ===\n');

cluster_effect_db = nan(n_subjects, 1);

for s = 1:n_subjects
    values = squeeze(subject_difference(s, :, :, :));
    cluster_effect_db(s) = mean(values(significant_mask), 'omitnan');
end

assert(all(isfinite(cluster_effect_db)), ...
    'Cluster effects contain non-finite values.');

effect_mean = mean(cluster_effect_db);
effect_sd = std(cluster_effect_db, 0);
effect_sem = effect_sd / sqrt(n_subjects);
effect_t = effect_mean / effect_sem;
effect_p = 2 * tcdf(-abs(effect_t), n_subjects - 1);
cohen_dz = effect_mean / effect_sd;
effect_median = median(cluster_effect_db);
negative_subjects = sum(cluster_effect_db < 0);
positive_subjects = sum(cluster_effect_db > 0);
zero_subjects = sum(cluster_effect_db == 0);

smaller_side = min(negative_subjects, positive_subjects);
sign_test_probability = 0;
for k = 0:smaller_side
    sign_test_probability = sign_test_probability + ...
        nchoosek(n_subjects, k) * (0.5 ^ n_subjects);
end
sign_test_probability = min(1, 2 * sign_test_probability);

leave_one_out_mean_db = nan(n_subjects, 1);
for s = 1:n_subjects
    keep = true(n_subjects, 1);
    keep(s) = false;
    leave_one_out_mean_db(s) = mean(cluster_effect_db(keep));
end

full_mean_change_when_removed_db = ...
    leave_one_out_mean_db - effect_mean;

fprintf('CLUSTER_EFFECT_MEAN_DB=%.9f\n', effect_mean);
fprintf('CLUSTER_EFFECT_SD_DB=%.9f\n', effect_sd);
fprintf('CLUSTER_EFFECT_T=%.9f\n', effect_t);
fprintf('CLUSTER_EFFECT_P=%.12f\n', effect_p);
fprintf('CLUSTER_EFFECT_COHEN_DZ=%.9f\n', cohen_dz);
fprintf('SUBJECTS_NEGATIVE=%d\n', negative_subjects);
fprintf('SUBJECTS_POSITIVE=%d\n', positive_subjects);
fprintf('SIGN_TEST_P=%.12f\n', sign_test_probability);
fprintf('LOO_MEAN_MIN_DB=%.9f\n', min(leave_one_out_mean_db));
fprintf('LOO_MEAN_MAX_DB=%.9f\n', max(leave_one_out_mean_db));

subject_table = table( ...
    string(subjects(:)), ...
    cluster_effect_db, ...
    leave_one_out_mean_db, ...
    full_mean_change_when_removed_db, ...
    'VariableNames', { ...
        'subject', ...
        'cluster_mean_Memorize_minus_Ignore_db', ...
        'mean_after_removing_subject_db', ...
        'change_in_group_mean_when_removed_db'});

subject_table_file = fullfile( ...
    table_dir, ...
    'stern_tf_primary_cluster_subject_effects.tsv');

writetable(subject_table, subject_table_file, ...
    'FileType', 'text', 'Delimiter', '\t');

fprintf('\n=== COMPUTING BAND-WINDOW SENSITIVITY ===\n');

band_names = {'theta_4_7_Hz', 'alpha_8_12_Hz', 'beta_14_30_Hz'};
band_limits = [4 7; 8 12; 14 30];

window_names = {'early_0_0.3_s', 'middle_0.3_0.8_s', 'late_0.8_1.4_s'};
window_limits = [0 0.3; 0.3 0.8; 0.8 1.4];

bw_subject = strings(0, 1);
bw_band = strings(0, 1);
bw_window = strings(0, 1);
bw_effect_db = [];

group_band_window = nan(3, 3);
negative_count_band_window = nan(3, 3);

for b = 1:3
    freq_mask = stat.freq >= band_limits(b, 1) & ...
                stat.freq <= band_limits(b, 2);

    for w = 1:3
        time_mask = stat.time >= window_limits(w, 1) & ...
                    stat.time <= window_limits(w, 2);

        values = squeeze(mean( ...
            subject_difference(:, :, freq_mask, time_mask), ...
            [2 3 4], 'omitnan'));

        group_band_window(b, w) = mean(values, 'omitnan');
        negative_count_band_window(b, w) = sum(values < 0);

        for s = 1:n_subjects
            bw_subject(end+1, 1) = string(subjects{s}); %#ok<SAGROW>
            bw_band(end+1, 1) = string(band_names{b}); %#ok<SAGROW>
            bw_window(end+1, 1) = string(window_names{w}); %#ok<SAGROW>
            bw_effect_db(end+1, 1) = values(s); %#ok<SAGROW>
        end
    end
end

band_window_table = table( ...
    bw_subject, bw_band, bw_window, bw_effect_db, ...
    'VariableNames', { ...
        'subject', ...
        'band', ...
        'window', ...
        'sensor_average_Memorize_minus_Ignore_db'});

band_window_table_file = fullfile( ...
    table_dir, ...
    'stern_tf_primary_band_window_subject_effects.tsv');

writetable(band_window_table, band_window_table_file, ...
    'FileType', 'text', 'Delimiter', '\t');

fprintf('\n=== CREATING SUBJECT EFFECT FIGURE ===\n');

subject_figure = fullfile( ...
    figure_dir, ...
    'stern_tf_primary_cluster_subject_effects.png');

fig = figure('Visible', 'off', 'Color', 'w', ...
    'Position', [100 100 1250 760]);

hold on;
plot(1:n_subjects, cluster_effect_db, 'o-', ...
    'LineWidth', 1.8, 'MarkerSize', 7);
yline(0, ':');
yline(effect_mean, '--', ...
    sprintf('Group mean %.3f dB', effect_mean), ...
    'LabelHorizontalAlignment', 'left');
xlim([0.5 n_subjects + 0.5]);
xticks(1:n_subjects);
xticklabels(subjects);
xlabel('Subject');
ylabel('Cluster-mean power difference (dB)');
title('Memorize - Ignore: subject-level effect in corrected TF cluster');
grid on;
box off;
set(gca, 'FontSize', 12);

exportgraphics(fig, subject_figure, 'Resolution', 300);
close(fig);

fprintf('\n=== CREATING SUBJECT TFR PANELS ===\n');

subject_tfr_figure = fullfile( ...
    figure_dir, ...
    'stern_tf_primary_subject_sensor_average_panels.png');

sensor_average_subject = squeeze(mean(subject_difference, 2, 'omitnan'));
panel_limit = max(abs(sensor_average_subject), [], 'all');
if panel_limit == 0
    panel_limit = 1;
end

fig = figure('Visible', 'off', 'Color', 'w', ...
    'Position', [100 100 1650 1250]);

tiledlayout(4, 4, 'TileSpacing', 'compact', 'Padding', 'compact');

for s = 1:n_subjects
    nexttile;
    imagesc(stat.time, stat.freq, ...
        squeeze(sensor_average_subject(s, :, :)));
    set(gca, 'YDir', 'normal');
    clim([-panel_limit panel_limit]);
    xline(0, '--', 'Color', [0 0 0], ...
        'HandleVisibility', 'off');
    title(subjects{s});
    xlabel('Time (s)');
    ylabel('Hz');
end

nexttile;
imagesc(stat.time, stat.freq, ...
    squeeze(mean(sensor_average_subject, 1, 'omitnan')));
set(gca, 'YDir', 'normal');
clim([-panel_limit panel_limit]);
xline(0, '--', 'Color', [0 0 0], ...
    'HandleVisibility', 'off');
title('Group mean');
xlabel('Time (s)');
ylabel('Hz');
colorbar;

sgtitle('Memorize - Ignore sensor-average TFR by subject');

exportgraphics(fig, subject_tfr_figure, 'Resolution', 300);
close(fig);

fprintf('\n=== CREATING BAND-WINDOW ROBUSTNESS FIGURE ===\n');

band_window_figure = fullfile( ...
    figure_dir, ...
    'stern_tf_primary_band_window_robustness.png');

fig = figure('Visible', 'off', 'Color', 'w', ...
    'Position', [100 100 1350 650]);

tiledlayout(1, 2, 'TileSpacing', 'compact', 'Padding', 'compact');

nexttile;
imagesc(group_band_window);
set(gca, 'YDir', 'normal');
xticks(1:3);
xticklabels({'0-0.3 s', '0.3-0.8 s', '0.8-1.4 s'});
yticks(1:3);
yticklabels({'theta', 'alpha', 'beta'});
xlabel('Post-stimulus window');
ylabel('Frequency band');
title('Group mean difference (dB)');
colorbar;

nexttile;
imagesc(negative_count_band_window, [0 n_subjects]);
set(gca, 'YDir', 'normal');
xticks(1:3);
xticklabels({'0-0.3 s', '0.3-0.8 s', '0.8-1.4 s'});
yticks(1:3);
yticklabels({'theta', 'alpha', 'beta'});
xlabel('Post-stimulus window');
ylabel('Frequency band');
title('Subjects with Memorize < Ignore');
colorbar;

sgtitle('Primary TF contrast robustness across bands and time windows');

exportgraphics(fig, band_window_figure, 'Resolution', 300);
close(fig);

fprintf('\n=== WRITING ROBUSTNESS SUMMARY ===\n');

summary_file = fullfile( ...
    summary_dir, ...
    'stern_tf_primary_robustness_qc_summary.txt');

fid = fopen(summary_file, 'w');
assert(fid ~= -1, 'Could not create summary: %s', summary_file);

fprintf(fid, '=== STERN PRIMARY TF ROBUSTNESS QC SUMMARY ===\n');
fprintf(fid, 'Contrast: Memorize - Ignore\n');
fprintf(fid, 'Corrected significant clusters: 1\n');
fprintf(fid, 'Cluster sign: %s\n', cluster_signs(1));
fprintf(fid, 'Cluster corrected p: %.12f\n', cluster_pvalues(1));
fprintf(fid, 'Cluster time extent: %.3f to %.3f s\n', ...
    min(stat.time(any(significant_mask, [1 2]))), ...
    max(stat.time(any(significant_mask, [1 2]))));
fprintf(fid, 'Cluster frequency extent: %.3f to %.3f Hz\n', ...
    min(stat.freq(any(significant_mask, [1 3]))), ...
    max(stat.freq(any(significant_mask, [1 3]))));
fprintf(fid, 'Cluster channels: %d of %d\n', ...
    sum(any(significant_mask, [2 3])), numel(labels));
fprintf(fid, 'Cluster samples: %d\n', nnz(significant_mask));
fprintf(fid, '\nSubject-level cluster mean:\n');
fprintf(fid, 'Mean: %.9f dB\n', effect_mean);
fprintf(fid, 'SD: %.9f dB\n', effect_sd);
fprintf(fid, 'Median: %.9f dB\n', effect_median);
fprintf(fid, 't(12): %.9f\n', effect_t);
fprintf(fid, 'Parametric paired-effect p: %.12f\n', effect_p);
fprintf(fid, 'Cohen dz: %.9f\n', cohen_dz);
fprintf(fid, 'Subjects negative: %d\n', negative_subjects);
fprintf(fid, 'Subjects positive: %d\n', positive_subjects);
fprintf(fid, 'Subjects zero: %d\n', zero_subjects);
fprintf(fid, 'Exact two-sided sign-test p: %.12f\n', ...
    sign_test_probability);
fprintf(fid, '\nLeave-one-subject-out group means:\n');
fprintf(fid, 'Minimum: %.9f dB\n', min(leave_one_out_mean_db));
fprintf(fid, 'Maximum: %.9f dB\n', max(leave_one_out_mean_db));
fprintf(fid, 'Maximum absolute mean change: %.9f dB\n', ...
    max(abs(full_mean_change_when_removed_db)));
fprintf(fid, '\nOutputs:\n');
fprintf(fid, 'Subject table: %s\n', subject_table_file);
fprintf(fid, 'Band/window table: %s\n', band_window_table_file);
fprintf(fid, 'Subject effect figure: %s\n', subject_figure);
fprintf(fid, 'Subject TFR panels: %s\n', subject_tfr_figure);
fprintf(fid, 'Band/window figure: %s\n', band_window_figure);
fprintf(fid, '\nInterpretation rule:\n');
fprintf(fid, ...
    ['This QC tests whether the corrected cluster is broadly consistent ' ...
     'across subjects and descriptive subregions. It does not replace the ' ...
     'cluster-permutation inference.\n']);

fclose(fid);

fprintf('\n=== STERN PRIMARY TF ROBUSTNESS QC PASSED ===\n');
fprintf('SUBJECT_TABLE=%s\n', subject_table_file);
fprintf('BAND_WINDOW_TABLE=%s\n', band_window_table_file);
fprintf('SUBJECT_EFFECT_FIGURE=%s\n', subject_figure);
fprintf('SUBJECT_TFR_FIGURE=%s\n', subject_tfr_figure);
fprintf('BAND_WINDOW_FIGURE=%s\n', band_window_figure);
fprintf('SUMMARY=%s\n', summary_file);
