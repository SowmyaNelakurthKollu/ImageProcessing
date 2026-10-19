function labelProject(config)
if nargin < 1
    config = projectConfig();
end
if ~isfile(config.LabelFile)
    prepareAnnotations(config);
end
labels = readtable(config.LabelFile, 'TextType', 'string');
fig = figure('Name', 'Reference labels - not model predictions');
cleanup = onCleanup(@() closeIfOpen(fig));
for k = 1:height(labels)
    if labels.Reviewed(k), continue; end
    image = imread(fullfile(config.Root, labels.Frame(k)));
    clf(fig);
    imshow(image);
    title(sprintf('%d/%d: REAL extinguisher? Printed replicas are absent.', ...
        k, height(labels)), 'Interpreter', 'none');
    choice = questdlg('Is the real physical target present?', ...
        'Ground truth', 'Present', 'Absent', 'Stop', 'Stop');
    if isempty(choice) || strcmp(choice, 'Stop'), return; end
    box = nan(1,4);
    if strcmp(choice, 'Present')
        title('Enclose the ENTIRE real target including hose; double-click to confirm.');
        roi = drawrectangle();
        wait(roi);
        if ~isvalid(roi), return; end
        box = roi.Position;
        if any(~isfinite(box)) || any(box(3:4) <= 0)
            error('Project:InvalidBox', 'Annotation must have positive finite dimensions.');
        end
    end
    choices = {'None', 'Printed replica', 'Similar physical object', 'Other'};
    [selected, ok] = listdlg('PromptString', ...
        'Distractor visible? (Even when the real target is also present)', ...
        'ListString', choices, 'SelectionMode', 'single');
    if ~ok, return; end
    labels.TargetPresent(k) = strcmp(choice, 'Present');
    labels{k, {'X','Y','Width','Height'}} = box;
    labels.Distractor(k) = string(choices{selected});
    labels.Reviewed(k) = true;
    writetable(labels, config.LabelFile);
end
fprintf('All %d frame labels reviewed and saved.\n', height(labels));
end

function closeIfOpen(fig)
if isgraphics(fig), close(fig); end
end
