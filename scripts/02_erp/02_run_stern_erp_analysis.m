eeglab_dir = getenv('EEGLAB_DIR');
work_data  = getenv('STERN_WORK_DATA');
study_dir  = getenv('STERN_STUDY_DIR');
results_dir = getenv('STERN_RESULTS_DIR');
log_dir    = getenv('STERN_LOG_DIR');

assert(isfile(fullfile(eeglab_dir, 'eeglab.m')), ...
    'EEGLAB not found: %s', eeglab_dir);
assert(isfolder(work_data), ...
    'Working dataset directory not found: %s', work_data);

if ~isfolder(study_dir), mkdir(study_dir); end
if ~isfolder(results_dir), mkdir(results_dir); end
if ~isfolder(fullfile(results_dir, 'figures')), mkdir(fullfile(results_dir, 'figures')); end
if ~isfolder(fullfile(results_dir, 'tables')), mkdir(fullfile(results_dir, 'tables')); end
if ~isfolder(fullfile(results_dir, 'summaries')), mkdir(fullfile(results_dir, 'summaries')); end
if ~isfolder(log_dir), mkdir(log_dir); end

rng(1, 'twister');

cd(eeglab_dir);
[ALLEEG, EEG, CURRENTSET, ALLCOM] = eeglab('nogui'); %#ok<ASGLU>
pop_editoptions('option_storedisk', 1);

subjects = arrayfun(@(x) sprintf('S%02d', x), 1:13, 'UniformOutput', false);
conditions = {'Ignore', 'Memorize', 'Probe'};

commands = {};
dataset_index = 0;

for s = 1:numel(subjects)
    for c = 1:numel(conditions)
        dataset_index = dataset_index + 1;
        set_file = fullfile(work_data, subjects{s}, [conditions{c} '.set']);

        assert(isfile(set_file), 'Missing working dataset: %s', set_file);

        commands{end+1} = { ...
            'index', dataset_index, ...
            'load', set_file, ...
            'subject', subjects{s}, ...
            'condition', conditions{c} ...
        }; %#ok<SAGROW>
    end
end

fprintf('\n=== CREATING 13-SUBJECT STUDY ===\n');

[STUDY, ALLEEG] = std_editset([], [], ...
    'name', 'STERN portfolio ERP study', ...
    'task', 'Sternberg working-memory letter task', ...
    'commands', commands, ...
    'updatedat', 'on');

[STUDY, ALLEEG] = std_checkset(STUDY, ALLEEG);

assert(numel(ALLEEG) == 39, ...
    'Expected 39 datasets, found %d.', numel(ALLEEG));

STUDY = std_makedesign(STUDY, ALLEEG, 1, ...
    'name', 'Ignore vs Memorize vs Probe', ...
    'delfiles', 'off', ...
    'defaultdesign', 'off', ...
    'variable1', 'condition', ...
    'values1', conditions, ...
    'vartype1', 'categorical', ...
    'pairing1', 'on', ...
    'subjselect', subjects);

STUDY.currentdesign = 1;

rejected_ic_counts = zeros(numel(ALLEEG), 1);
channel_counts = zeros(numel(ALLEEG), 1);
trial_counts = zeros(numel(ALLEEG), 1);

for i = 1:numel(ALLEEG)
    channel_counts(i) = ALLEEG(i).nbchan;
    trial_counts(i) = ALLEEG(i).trials;

    if isfield(ALLEEG(i), 'reject') && ...
       isfield(ALLEEG(i).reject, 'gcompreject') && ...
       ~isempty(ALLEEG(i).reject.gcompreject)
        rejected_ic_counts(i) = sum(ALLEEG(i).reject.gcompreject);
    end
end

fprintf('Datasets: %d\n', numel(ALLEEG));
fprintf('Subjects: %d\n', numel(subjects));
fprintf('Channel counts: %s\n', mat2str(unique(channel_counts)'));
fprintf('Total trials: %d\n', sum(trial_counts));
fprintf('Pre-marked rejected ICs across datasets: %d\n', sum(rejected_ic_counts));

study_file = fullfile(study_dir, 'stern_portfolio_erp.study');

STUDY.filename = 'stern_portfolio_erp.study';
STUDY.filepath = study_dir;

[STUDY, ALLEEG] = pop_savestudy(STUDY, ALLEEG, ...
    'filename', 'stern_portfolio_erp.study', ...
    'filepath', study_dir, ...
    'savemode', 'standard');

fprintf('\n=== PRECOMPUTING BASELINE-CORRECTED ERPS ===\n');

[STUDY, ALLEEG] = std_precomp(STUDY, ALLEEG, {}, ...
    'rmicacomps', 'on', ...
    'interp', 'on', ...
    'recompute', 'on', ...
    'erp', 'on', ...
    'erpparams', {'rmbase', [-200 0]});

[STUDY, ALLEEG] = pop_savestudy(STUDY, ALLEEG, ...
    'filename', 'stern_portfolio_erp.study', ...
    'filepath', study_dir, ...
    'savemode', 'standard');

fprintf('\n=== EXTRACTING OZ SUBJECT-LEVEL ERPS ===\n');

[STUDY, erpdata, erptimes] = std_erpplot( ...
    STUDY, ALLEEG, ...
    'channels', {'OZ'}, ...
    'design', 1, ...
    'timerange', [-200 1000], ...
    'noplot', 'on');

assert(numel(erpdata) == 3, ...
    'Expected 3 condition cells in erpdata, found %d.', numel(erpdata));

condition_values = STUDY.design(1).variable(1).value;
if ischar(condition_values)
    condition_values = {condition_values};
end

case_values = subjects;
if isfield(STUDY.design(1), 'cases') && ...
   isfield(STUDY.design(1).cases, 'value') && ...
   ~isempty(STUDY.design(1).cases.value)
    case_values = STUDY.design(1).cases.value;
end

clean_erp = cell(1, 3);

for c = 1:3
    values = squeeze(erpdata{c});

    if size(values, 1) ~= numel(erptimes) && ...
       size(values, 2) == numel(erptimes)
        values = values';
    end

    assert(size(values, 1) == numel(erptimes), ...
        'Unexpected ERP dimensions for condition %s.', condition_values{c});

    clean_erp{c} = double(values);
end

n_subjects = size(clean_erp{1}, 2);
if numel(case_values) ~= n_subjects
    case_values = arrayfun(@(x) sprintf('S%02d', x), ...
        1:n_subjects, 'UniformOutput', false);
end

all_time = [];
all_subject = strings(0, 1);
all_condition = strings(0, 1);
all_amplitude = [];

for c = 1:3
    values = clean_erp{c};

    assert(size(values, 2) == n_subjects, ...
        'Subject count differs across conditions.');

    for s = 1:n_subjects
        all_time = [all_time; erptimes(:)]; %#ok<AGROW>
        all_subject = [all_subject; repmat(string(case_values{s}), numel(erptimes), 1)]; %#ok<AGROW>
        all_condition = [all_condition; repmat(string(condition_values{c}), numel(erptimes), 1)]; %#ok<AGROW>
        all_amplitude = [all_amplitude; values(:, s)]; %#ok<AGROW>
    end
end

erp_table = table( ...
    all_time, ...
    all_subject, ...
    all_condition, ...
    all_amplitude, ...
    'VariableNames', {'time_ms', 'subject', 'condition', 'amplitude_uv'});

erp_table_file = fullfile(results_dir, 'tables', ...
    'stern_OZ_subject_level_erp.tsv');

writetable(erp_table, erp_table_file, ...
    'FileType', 'text', ...
    'Delimiter', '\t');

fprintf('\n=== CREATING OZ GRAND-AVERAGE FIGURE ===\n');

fig = figure('Visible', 'off', ...
    'Color', 'w', ...
    'Position', [100 100 1200 720]);

hold on;
line_colors = lines(3);

for c = 1:3
    values = clean_erp{c};
    grand_mean = mean(values, 2, 'omitnan');
    sem = std(values, 0, 2, 'omitnan') ./ sqrt(sum(isfinite(values), 2));

    upper = grand_mean + sem;
    lower = grand_mean - sem;

    fill( ...
        [erptimes(:); flipud(erptimes(:))], ...
        [upper; flipud(lower)], ...
        line_colors(c, :), ...
        'FaceAlpha', 0.16, ...
        'EdgeColor', 'none', ...
        'HandleVisibility', 'off');

    plot(erptimes, grand_mean, ...
        'LineWidth', 2.2, ...
        'Color', line_colors(c, :), ...
        'DisplayName', condition_values{c});
end

xline(0, '--', 'Stimulus', ...
    'LabelVerticalAlignment', 'bottom', ...
    'HandleVisibility', 'off');
yline(0, ':', 'HandleVisibility', 'off');

xlim([-200 1000]);
xlabel('Time (ms)');
ylabel('Amplitude (\muV)');
title(sprintf('STERN grand-average ERP at Oz (N = %d)', n_subjects));
legend('Location', 'best');
grid on;
box off;
set(gca, 'FontSize', 13);

figure_file = fullfile(results_dir, 'figures', ...
    'stern_grand_average_erp_OZ.png');

exportgraphics(fig, figure_file, 'Resolution', 300);
close(fig);

summary_file = fullfile(results_dir, 'summaries', ...
    'stern_erp_stage1_summary.txt');

fid = fopen(summary_file, 'w');
assert(fid ~= -1, 'Could not create summary: %s', summary_file);

fprintf(fid, '=== STERN ERP STAGE 1 SUMMARY ===\n');
fprintf(fid, 'EEGLAB version: %s\n', eeg_getversion);
fprintf(fid, 'MATLAB version: %s\n', version);
fprintf(fid, 'Study file: %s\n', study_file);
fprintf(fid, 'Datasets: %d\n', numel(ALLEEG));
fprintf(fid, 'Subjects: %d\n', n_subjects);
fprintf(fid, 'Conditions: %s\n', strjoin(condition_values, ', '));
fprintf(fid, 'Channel counts before STUDY interpolation: %s\n', ...
    mat2str(unique(channel_counts)'));
fprintf(fid, 'Total trials: %d\n', sum(trial_counts));
fprintf(fid, 'Total pre-marked rejected ICs: %d\n', sum(rejected_ic_counts));
fprintf(fid, 'ERP baseline: -200 to 0 ms\n');
fprintf(fid, 'ERP extraction channel: OZ\n');
fprintf(fid, 'ERP extraction range: -200 to 1000 ms\n');

for c = 1:3
    fprintf(fid, '%s ERP matrix: %d time points x %d subjects\n', ...
        condition_values{c}, size(clean_erp{c}, 1), size(clean_erp{c}, 2));
    fprintf(fid, '%s NaN values: %d\n', ...
        condition_values{c}, sum(isnan(clean_erp{c}), 'all'));
end

fprintf(fid, 'ERP table: %s\n', erp_table_file);
fprintf(fid, 'ERP figure: %s\n', figure_file);
fclose(fid);

fprintf('\n=== STERN ERP STAGE 1 PASSED ===\n');
fprintf('STUDY=%s\n', study_file);
fprintf('SUMMARY=%s\n', summary_file);
fprintf('ERP_TABLE=%s\n', erp_table_file);
fprintf('ERP_FIGURE=%s\n', figure_file);

pop_editoptions('option_storedisk', 0);
