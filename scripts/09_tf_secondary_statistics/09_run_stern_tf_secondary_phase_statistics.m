eeglab_dir    = getenv('EEGLAB_DIR');
fieldtrip_dir = getenv('FIELDTRIP_DIR');
project_dir   = getenv('STERN_PROJECT');

results_dir = fullfile(project_dir, 'results');
tfr_file = fullfile(results_dir, 'mat', 'stern_subject_level_tfr_db.mat');
reference_set = fullfile( ...
    project_dir, 'work', 'study_datasets', 'S01', 'Memorize.set');

figure_dir  = fullfile(results_dir, 'figures');
table_dir   = fullfile(results_dir, 'tables');
summary_dir = fullfile(results_dir, 'summaries');
mat_dir     = fullfile(results_dir, 'mat');

assert(isfile(fullfile(eeglab_dir, 'eeglab.m')), ...
    'EEGLAB not found: %s', eeglab_dir);
assert(isfile(fullfile(fieldtrip_dir, 'ft_defaults.m')), ...
    'FieldTrip not found: %s', fieldtrip_dir);
assert(isfile(tfr_file), ...
    'TFR file not found: %s', tfr_file);
assert(isfile(reference_set), ...
    'Reference dataset not found: %s', reference_set);

folders = {figure_dir, table_dir, summary_dir, mat_dir};
for i = 1:numel(folders)
    if ~isfolder(folders{i})
        mkdir(folders{i});
    end
end

rng(1, 'twister');

cd(eeglab_dir);
[ALLEEG, EEG, CURRENTSET, ALLCOM] = eeglab('nogui'); %#ok<ASGLU>

addpath(fieldtrip_dir);
ft_defaults;

loaded = load(tfr_file);

tf_db      = loaded.tf_db;
freq_hz    = double(loaded.freq_hz(:)');
time_s     = double(loaded.time_s(:)');
labels     = cellstr(string(loaded.labels));
conditions = cellstr(string(loaded.conditions));
subjects   = cellstr(string(loaded.subjects));

assert(isequal(size(tf_db), [3 13 69 14 50]), ...
    'Unexpected TFR array size: %s', mat2str(size(tf_db)));
assert(all(isfinite(tf_db), 'all'), ...
    'TFR array contains non-finite values.');

n_subjects = numel(subjects);
n_channels = numel(labels);

probe_index = find(strcmpi(conditions, 'Probe'), 1);
memorize_index = find(strcmpi(conditions, 'Memorize'), 1);
ignore_index = find(strcmpi(conditions, 'Ignore'), 1);

assert(~isempty(probe_index) && ...
       ~isempty(memorize_index) && ...
       ~isempty(ignore_index), ...
    'Could not resolve Probe, Memorize, and Ignore.');

contrast_names = { ...
    'Probe_minus_Memorize', ...
    'Probe_minus_Ignore'};

contrast_pretty = { ...
    'Probe - Memorize', ...
    'Probe - Ignore'};

contrast_pairs = [ ...
    probe_index memorize_index; ...
    probe_index ignore_index];

fprintf('\n=== LOADING CHANNEL LOCATIONS ===\n');

[ref_path, ref_name, ref_ext] = fileparts(reference_set);
EEG_REF = pop_loadset( ...
    'filename', [ref_name ref_ext], ...
    'filepath', ref_path);
EEG_REF = eeg_checkset(EEG_REF);

ref_labels = {EEG_REF.chanlocs.labels};
chanlocs = repmat(EEG_REF.chanlocs(1), 1, n_channels);

for ch = 1:n_channels
    idx = find(strcmpi(ref_labels, labels{ch}), 1);
    assert(~isempty(idx), ...
        'Channel %s missing from reference dataset.', labels{ch});
    chanlocs(ch) = EEG_REF.chanlocs(idx);
end

coords = [ ...
    [chanlocs.X]' ...
    [chanlocs.Y]' ...
    [chanlocs.Z]'];

assert(all(isfinite(coords), 'all'), ...
    'Channel coordinates contain non-finite values.');

elec = [];
elec.label   = labels(:);
elec.chanpos = coords;
elec.elecpos = coords;
elec.unit    = 'arbitrary';

fprintf('\n=== BUILDING SYMMETRIC CHANNEL NEIGHBOURS ===\n');

k_nearest = 4;
distance_matrix = nan(n_channels, n_channels);

for i = 1:n_channels
    for j = 1:n_channels
        distance_matrix(i, j) = norm(coords(i, :) - coords(j, :));
    end
end

adjacency = false(n_channels, n_channels);

for i = 1:n_channels
    distances = distance_matrix(i, :);
    distances(i) = inf;

    [~, order] = sort(distances, 'ascend');
    adjacency(i, order(1:k_nearest)) = true;
end

adjacency = adjacency | adjacency';
adjacency(1:n_channels+1:end) = false;

neighbours = repmat( ...
    struct('label', '', 'neighblabel', {{}}), ...
    n_channels, 1);

for i = 1:n_channels
    neighbours(i).label = labels{i};
    neighbours(i).neighblabel = labels(find(adjacency(i, :)));
end

neighbour_degree = sum(adjacency, 2);

assert(min(neighbour_degree) >= 4, ...
    'A channel has fewer than four neighbours.');

fprintf('NEIGHBOUR_DEGREE_MIN=%d\n', min(neighbour_degree));
fprintf('NEIGHBOUR_DEGREE_MEDIAN=%.1f\n', median(neighbour_degree));
fprintf('NEIGHBOUR_DEGREE_MAX=%d\n', max(neighbour_degree));

fprintf('\n=== BUILDING FIELDTRIP INPUTS ===\n');

condition_data = cell(1, numel(conditions));

for c = 1:numel(conditions)
    condition_data{c} = cell(1, n_subjects);

    for s = 1:n_subjects
        data = [];
        data.label = labels(:);
        data.freq = freq_hz;
        data.time = time_s;
        data.powspctrm = squeeze(tf_db(c, s, :, :, :));
        data.dimord = 'chan_freq_time';
        data.elec = elec;

        condition_data{c}{s} = data;
    end
end

design = zeros(2, 2 * n_subjects);
design(1, :) = [1:n_subjects 1:n_subjects];
design(2, :) = [ ...
    ones(1, n_subjects) ...
    2 .* ones(1, n_subjects)];

stats = cell(1, 2);
difference_maps = cell(1, 2);
significant_masks = cell(1, 2);
best_cluster_masks = cell(1, 2);
best_cluster_notes = strings(1, 2);
best_cluster_p = nan(1, 2);
best_cluster_sign = strings(1, 2);
peak_channels = strings(1, 2);
peak_frequencies = nan(1, 2);
peak_times = nan(1, 2);
topography_values = cell(1, 2);
topography_ranges = nan(2, 4);

all_tables = cell(1, 2);

fprintf('\n=== RUNNING SECONDARY TASK-PHASE TF CLUSTER TESTS ===\n');

for k = 1:2
    condition_a = contrast_pairs(k, 1);
    condition_b = contrast_pairs(k, 2);

    fprintf('\n--- %s ---\n', contrast_pretty{k});

    stat_file = fullfile( ...
        mat_dir, ...
        ['stern_tf_cluster_' contrast_names{k} '.mat']);

    reuse_stat = false;

    if isfile(stat_file)
        cached_stat = load(stat_file, 'stat');

        if isfield(cached_stat, 'stat') && ...
           isfield(cached_stat.stat, 'stat') && ...
           isfield(cached_stat.stat, 'label') && ...
           isfield(cached_stat.stat, 'freq') && ...
           isfield(cached_stat.stat, 'time') && ...
           isequal(size(cached_stat.stat.stat), [69 14 36])
            stat = cached_stat.stat;
            reuse_stat = true;
            fprintf('REUSING_STAT=%s\n', stat_file);
        end
    end

    if ~reuse_stat
        cfg = [];
        cfg.channel          = 'all';
        cfg.frequency        = [4 30];
        cfg.latency          = [0 1.4];
        cfg.parameter        = 'powspctrm';
        cfg.method           = 'montecarlo';
        cfg.statistic        = 'ft_statfun_depsamplesT';
        cfg.correctm         = 'cluster';
        cfg.clusteralpha     = 0.05;
        cfg.clusterstatistic = 'maxsum';
        cfg.minnbchan        = 2;
        cfg.neighbours       = neighbours;
        cfg.tail             = 0;
        cfg.clustertail      = 0;
        cfg.alpha            = 0.05;
        cfg.correcttail      = 'alpha';
        cfg.numrandomization = 'all';
        cfg.design           = design;
        cfg.uvar             = 1;
        cfg.ivar             = 2;

        stat = ft_freqstatistics( ...
            cfg, ...
            condition_data{condition_a}{:}, ...
            condition_data{condition_b}{:});

        save(stat_file, 'stat', '-v7.3');
    end

    stats{k} = stat;

    cluster_table = summarize_tf_clusters( ...
        stat, ...
        contrast_names{k}, ...
        0.05, ...
        8192);

    cluster_table.significant_across_two_secondary_contrasts_0_025 = ...
        cluster_table.pvalue < 0.025;

    all_tables{k} = cluster_table;

    significant_mask = false(size(stat.stat));
    if isfield(stat, 'mask')
        significant_mask = logical(stat.mask);
    end
    significant_masks{k} = significant_mask;

    [best_mask, best_sign, best_index, best_p] = ...
        select_best_significant_cluster(stat, 0.05);

    if any(best_mask, 'all')
        best_cluster_masks{k} = best_mask;
        best_cluster_sign(k) = string(best_sign);
        best_cluster_p(k) = best_p;
        best_cluster_notes(k) = sprintf( ...
            '%s cluster %d, p=%.6f', ...
            best_sign, best_index, best_p);

        candidate = abs(stat.stat);
        candidate(~best_mask) = -inf;
        [~, peak_linear_index] = max( ...
            candidate, [], 'all', 'linear');
    else
        best_cluster_masks{k} = false(size(stat.stat));
        best_cluster_notes(k) = ...
            "no corrected cluster; largest uncorrected |t|";
        [~, peak_linear_index] = max( ...
            abs(stat.stat), [], 'all', 'linear');
    end

    [peak_channel_index, peak_frequency_index, peak_time_index] = ...
        ind2sub(size(stat.stat), peak_linear_index);

    peak_channels(k) = string(stat.label{peak_channel_index});
    peak_frequencies(k) = stat.freq(peak_frequency_index);
    peak_times(k) = stat.time(peak_time_index);

    difference = squeeze(mean( ...
        tf_db(condition_a, :, :, :, :) - ...
        tf_db(condition_b, :, :, :, :), ...
        [2 3], ...
        'omitnan'));

    difference_maps{k} = difference;

    if any(best_mask, 'all')
        active_freq = find(any(best_mask, [1 3]));
        active_time = find(any(best_mask, [1 2]));

        freq_start = min(stat.freq(active_freq));
        freq_end = max(stat.freq(active_freq));
        time_start = min(stat.time(active_time));
        time_end = max(stat.time(active_time));
    else
        freq_start = max(4, peak_frequencies(k) - 2);
        freq_end = min(30, peak_frequencies(k) + 2);
        time_start = max(0, peak_times(k) - 0.08);
        time_end = min(1.4, peak_times(k) + 0.08);
    end

    topography_ranges(k, :) = [ ...
        freq_start, freq_end, time_start, time_end];

    freq_mask = freq_hz >= freq_start & freq_hz <= freq_end;
    time_mask = time_s >= time_start & time_s <= time_end;

    subject_channel_difference = squeeze(mean( ...
        tf_db(condition_a, :, :, freq_mask, time_mask) - ...
        tf_db(condition_b, :, :, freq_mask, time_mask), ...
        [4 5], ...
        'omitnan'));

    topography_values{k} = mean( ...
        subject_channel_difference, ...
        1, ...
        'omitnan');

    fprintf( ...
        '%s: clusters=%d, significant=%d, best=%s\n', ...
        contrast_pretty{k}, ...
        height(cluster_table), ...
        sum(cluster_table.significant_p_lt_0_05), ...
        best_cluster_notes(k));
end

combined_table = [all_tables{1}; all_tables{2}];

cluster_table_file = fullfile( ...
    table_dir, ...
    'stern_tf_secondary_phase_cluster_results.tsv');

writetable( ...
    combined_table, ...
    cluster_table_file, ...
    'FileType', 'text', ...
    'Delimiter', '\t');

fprintf('\n=== CREATING SECONDARY SENSOR-AVERAGE FIGURE ===\n');

sensor_figure = fullfile( ...
    figure_dir, ...
    'stern_tf_secondary_phase_sensor_average.png');

figure_limit = max(cellfun( ...
    @(x) max(abs(x), [], 'all'), ...
    difference_maps));

if figure_limit == 0
    figure_limit = 1;
end

fig = figure( ...
    'Visible', 'off', ...
    'Color', 'w', ...
    'Position', [100 100 1450 650]);

tiledlayout(1, 2, ...
    'TileSpacing', 'compact', ...
    'Padding', 'compact');

for k = 1:2
    stat = stats{k};
    any_significant = squeeze(any(significant_masks{k}, 1));

    nexttile;
    imagesc(time_s, freq_hz, difference_maps{k});
    set(gca, 'YDir', 'normal');
    hold on;

    if any(any_significant, 'all')
        contour( ...
            stat.time, ...
            stat.freq, ...
            double(any_significant), ...
            [0.5 0.5], ...
            'k', ...
            'LineWidth', 1.4);
    end

    xline(0, '--', 'Color', [0 0 0], ...
        'HandleVisibility', 'off');
    clim([-figure_limit figure_limit]);
    xlabel('Time (s)');
    ylabel('Frequency (Hz)');
    title(contrast_pretty{k});
    colorbar;
end

sgtitle([ ...
    'STERN secondary task-phase TF contrasts ' ...
    '(black contour: corrected cluster at one or more channels)']);

exportgraphics(fig, sensor_figure, 'Resolution', 300);
close(fig);

fprintf('\n=== CREATING REPRESENTATIVE CHANNEL FIGURE ===\n');

representative_figure = fullfile( ...
    figure_dir, ...
    'stern_tf_secondary_phase_representative_channels.png');

fig = figure( ...
    'Visible', 'off', ...
    'Color', 'w', ...
    'Position', [100 100 1450 650]);

tiledlayout(1, 2, ...
    'TileSpacing', 'compact', ...
    'Padding', 'compact');

for k = 1:2
    stat = stats{k};
    source_channel = find( ...
        strcmpi(labels, peak_channels(k)), 1);

    condition_a = contrast_pairs(k, 1);
    condition_b = contrast_pairs(k, 2);

    channel_difference = squeeze(mean( ...
        tf_db(condition_a, :, source_channel, :, :) - ...
        tf_db(condition_b, :, source_channel, :, :), ...
        2, ...
        'omitnan'));

    channel_mask = squeeze( ...
        significant_masks{k}( ...
            strcmpi(stat.label, peak_channels(k)), :, :));

    channel_limit = max(abs(channel_difference), [], 'all');
    if channel_limit == 0
        channel_limit = 1;
    end

    nexttile;
    imagesc(time_s, freq_hz, channel_difference);
    set(gca, 'YDir', 'normal');
    hold on;

    if any(channel_mask, 'all')
        contour( ...
            stat.time, ...
            stat.freq, ...
            double(channel_mask), ...
            [0.5 0.5], ...
            'k', ...
            'LineWidth', 1.4);
    end

    xline(0, '--', 'Color', [0 0 0], ...
        'HandleVisibility', 'off');
    clim([-channel_limit channel_limit]);
    xlabel('Time (s)');
    ylabel('Frequency (Hz)');
    title(sprintf( ...
        '%s at %s; peak %.1f Hz, %.2f s', ...
        contrast_pretty{k}, ...
        peak_channels(k), ...
        peak_frequencies(k), ...
        peak_times(k)));
    colorbar;
end

sgtitle('Representative channels for secondary TF task-phase contrasts');

exportgraphics(fig, representative_figure, 'Resolution', 300);
close(fig);

fprintf('\n=== CREATING SECONDARY TOPOGRAPHIES ===\n');

topography_figure = fullfile( ...
    figure_dir, ...
    'stern_tf_secondary_phase_topographies.png');

topography_limit = max(cellfun( ...
    @(x) max(abs(x), [], 'all'), ...
    topography_values));

if topography_limit == 0
    topography_limit = 1;
end

fig = figure( ...
    'Visible', 'off', ...
    'Color', 'w', ...
    'Position', [100 100 1300 650]);

tiledlayout(1, 2, ...
    'TileSpacing', 'compact', ...
    'Padding', 'compact');

for k = 1:2
    nexttile;

    topoplot( ...
        topography_values{k}, ...
        chanlocs, ...
        'electrodes', 'on', ...
        'maplimits', [-topography_limit topography_limit], ...
        'style', 'map', ...
        'shading', 'interp');

    title(sprintf( ...
        '%s, %.1f-%.1f Hz, %.2f-%.2f s', ...
        contrast_pretty{k}, ...
        topography_ranges(k, 1), ...
        topography_ranges(k, 2), ...
        topography_ranges(k, 3), ...
        topography_ranges(k, 4)));
    colorbar;
end

sgtitle('Secondary task-phase TF topographies');

exportgraphics(fig, topography_figure, 'Resolution', 300);
close(fig);

fprintf('\n=== WRITING SECONDARY TF SUMMARY ===\n');

summary_file = fullfile( ...
    summary_dir, ...
    'stern_tf_secondary_phase_cluster_statistics_summary.txt');

fid = fopen(summary_file, 'w');
assert(fid ~= -1, ...
    'Could not create summary: %s', summary_file);

fprintf(fid, ...
    '=== STERN SECONDARY TASK-PHASE TF CLUSTER SUMMARY ===\n');
fprintf(fid, 'Subjects: %d\n', n_subjects);
fprintf(fid, 'Channels: %d scalp EEG channels\n', n_channels);
fprintf(fid, 'Frequency range: 4 to 30 Hz\n');
fprintf(fid, 'Time range: 0 to 1.4 s\n');
fprintf(fid, 'Input scale: dB\n');
fprintf(fid, 'Test: dependent-samples t\n');
fprintf(fid, ...
    'Correction: channel x frequency x time cluster permutation\n');
fprintf(fid, 'Randomization: all possible within-subject permutations\n');
fprintf(fid, 'Exact permutation reference: 8192\n');
fprintf(fid, 'Within-contrast corrected alpha: 0.05\n');
fprintf(fid, ...
    'Additional conservative alpha across two secondary contrasts: 0.025\n');
fprintf(fid, '\nInterpretation constraint:\n');
fprintf(fid, ...
    ['Probe is aligned to probe events and includes later response and ' ...
     'correctness markers. Probe contrasts are task-phase comparisons, ' ...
     'not pure encoding-condition effects.\n']);

for k = 1:2
    table_k = all_tables{k};

    fprintf(fid, '\n%s\n', contrast_pretty{k});
    fprintf(fid, 'Clusters formed: %d\n', height(table_k));
    fprintf(fid, 'Significant at corrected p < 0.05: %d\n', ...
        sum(table_k.significant_p_lt_0_05));
    fprintf(fid, 'Significant at p < 0.025: %d\n', ...
        sum(table_k.significant_across_two_secondary_contrasts_0_025));
    fprintf(fid, 'Representative channel: %s\n', peak_channels(k));
    fprintf(fid, 'Representative frequency: %.6f Hz\n', ...
        peak_frequencies(k));
    fprintf(fid, 'Representative time: %.6f s\n', peak_times(k));
    fprintf(fid, 'Best corrected cluster: %s\n', best_cluster_notes(k));
end

fprintf(fid, '\nOutputs:\n');
fprintf(fid, 'Cluster table: %s\n', cluster_table_file);
fprintf(fid, 'Sensor-average figure: %s\n', sensor_figure);
fprintf(fid, 'Representative-channel figure: %s\n', ...
    representative_figure);
fprintf(fid, 'Topography figure: %s\n', topography_figure);

fclose(fid);

fprintf('\n=== STERN SECONDARY TF PHASE STATISTICS V2 PASSED ===\n');
fprintf('CLUSTER_TABLE=%s\n', cluster_table_file);
fprintf('SENSOR_FIGURE=%s\n', sensor_figure);
fprintf('REPRESENTATIVE_FIGURE=%s\n', representative_figure);
fprintf('TOPOGRAPHY_FIGURE=%s\n', topography_figure);
fprintf('SUMMARY=%s\n', summary_file);

function [mask, sign_name, index, probability] = ...
    select_best_significant_cluster(stat, alpha)

    mask = false(size(stat.stat));
    sign_name = '';
    index = NaN;
    probability = NaN;

    best_probability = inf;

    if isfield(stat, 'posclusters') && ~isempty(stat.posclusters)
        for idx = 1:numel(stat.posclusters)
            p = stat.posclusters(idx).prob;
            if p < alpha && p < best_probability
                best_probability = p;
                mask = stat.posclusterslabelmat == idx;
                sign_name = 'positive';
                index = idx;
                probability = p;
            end
        end
    end

    if isfield(stat, 'negclusters') && ~isempty(stat.negclusters)
        for idx = 1:numel(stat.negclusters)
            p = stat.negclusters(idx).prob;
            if p < alpha && p < best_probability
                best_probability = p;
                mask = stat.negclusterslabelmat == idx;
                sign_name = 'negative';
                index = idx;
                probability = p;
            end
        end
    end
end

function result = summarize_tf_clusters( ...
    stat, contrast_name, alpha, exact_permutations)

    rows = cell(0, 18);

    if isfield(stat, 'posclusters') && ~isempty(stat.posclusters)
        for idx = 1:numel(stat.posclusters)
            rows(end+1, :) = cluster_row( ...
                stat, ...
                stat.posclusterslabelmat == idx, ...
                contrast_name, ...
                'positive', ...
                idx, ...
                stat.posclusters(idx).prob, ...
                stat.posclusters(idx).clusterstat, ...
                alpha, ...
                exact_permutations); %#ok<AGROW>
        end
    end

    if isfield(stat, 'negclusters') && ~isempty(stat.negclusters)
        for idx = 1:numel(stat.negclusters)
            rows(end+1, :) = cluster_row( ...
                stat, ...
                stat.negclusterslabelmat == idx, ...
                contrast_name, ...
                'negative', ...
                idx, ...
                stat.negclusters(idx).prob, ...
                stat.negclusters(idx).clusterstat, ...
                alpha, ...
                exact_permutations); %#ok<AGROW>
        end
    end

    variable_names = { ...
        'contrast', ...
        'sign', ...
        'cluster_index', ...
        'pvalue', ...
        'pvalue_display', ...
        'cluster_statistic', ...
        'significant_p_lt_0_05', ...
        'time_start_s', ...
        'time_end_s', ...
        'frequency_start_hz', ...
        'frequency_end_hz', ...
        'n_channel_frequency_time_samples', ...
        'n_channels', ...
        'channels', ...
        'peak_t', ...
        'peak_channel', ...
        'peak_frequency_hz', ...
        'peak_time_s'};

    if isempty(rows)
        result = table( ...
            strings(0,1), strings(0,1), zeros(0,1), zeros(0,1), ...
            strings(0,1), zeros(0,1), false(0,1), zeros(0,1), ...
            zeros(0,1), zeros(0,1), zeros(0,1), zeros(0,1), ...
            zeros(0,1), strings(0,1), zeros(0,1), strings(0,1), ...
            zeros(0,1), zeros(0,1), ...
            'VariableNames', variable_names);
        return;
    end

    result = cell2table(rows, 'VariableNames', variable_names);

    numeric_variables = { ...
        'cluster_index', 'pvalue', 'cluster_statistic', ...
        'time_start_s', 'time_end_s', ...
        'frequency_start_hz', 'frequency_end_hz', ...
        'n_channel_frequency_time_samples', 'n_channels', ...
        'peak_t', 'peak_frequency_hz', 'peak_time_s'};

    % In recent MATLAB releases, cell2table can automatically convert
    % scalar numeric cells into numeric table variables. Convert only when
    % the variable is still a cell array.
    for i = 1:numel(numeric_variables)
        variable_name = numeric_variables{i};
        values = result.(variable_name);

        if iscell(values)
            result.(variable_name) = cell2mat(values);
        end
    end

    significance_values = result.significant_p_lt_0_05;
    if iscell(significance_values)
        significance_values = cell2mat(significance_values);
    end
    result.significant_p_lt_0_05 = logical(significance_values);

    result.contrast = string(result.contrast);
    result.sign = string(result.sign);
    result.pvalue_display = string(result.pvalue_display);
    result.channels = string(result.channels);
    result.peak_channel = string(result.peak_channel);
end

function row = cluster_row( ...
    stat, mask, contrast_name, sign_name, index, probability, ...
    cluster_stat, alpha, exact_permutations)

    [channel_indices, frequency_indices, time_indices] = ...
        ind2sub(size(mask), find(mask));

    unique_channels = unique(channel_indices);
    unique_frequencies = unique(frequency_indices);
    unique_times = unique(time_indices);

    cluster_t = stat.stat;
    cluster_t(~mask) = NaN;

    if strcmp(sign_name, 'positive')
        [peak_value, peak_linear] = max( ...
            cluster_t, [], 'all', 'omitnan', 'linear');
    else
        [peak_value, peak_linear] = min( ...
            cluster_t, [], 'all', 'omitnan', 'linear');
    end

    [peak_channel_index, peak_frequency_index, peak_time_index] = ...
        ind2sub(size(stat.stat), peak_linear);

    if probability == 0
        p_display = sprintf('< %.6f', 1 / exact_permutations);
    else
        p_display = sprintf('%.6f', probability);
    end

    row = { ...
        contrast_name, ...
        sign_name, ...
        index, ...
        probability, ...
        p_display, ...
        cluster_stat, ...
        probability < alpha, ...
        min(stat.time(unique_times)), ...
        max(stat.time(unique_times)), ...
        min(stat.freq(unique_frequencies)), ...
        max(stat.freq(unique_frequencies)), ...
        nnz(mask), ...
        numel(unique_channels), ...
        strjoin(string(stat.label(unique_channels)), ','), ...
        peak_value, ...
        stat.label{peak_channel_index}, ...
        stat.freq(peak_frequency_index), ...
        stat.time(peak_time_index)};
end
