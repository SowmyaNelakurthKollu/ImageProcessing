function labelAnchors(config)
if nargin < 1
    config = projectConfig();
end
if isfile(config.AnchorBoxes)
    error('Project:ExistingAnchorBoxes', ...
        'Anchor boxes already exist: %s. Move that file to relabel.', config.AnchorBoxes);
end
Frame = ["Anchor1.png"; "Anchor2.png"; "Anchor3.png"];
boxes = zeros(3,4);
fig = figure('Name', 'Crop anchors to the target - exclude room background');
cleanup = onCleanup(@() closeIfOpen(fig));
for k = 1:3
    imshow(imread(fullfile(config.AnchorFolder, Frame(k))));
    title(sprintf('Anchor %d: enclose entire target and hose; double-click.', k));
    roi = drawrectangle();
    wait(roi);
    if ~isvalid(roi)
        error('Project:Cancelled', 'Anchor annotation cancelled; nothing saved.');
    end
    boxes(k,:) = roi.Position;
end
labels = array2table(boxes, 'VariableNames', {'X','Y','Width','Height'});
labels = addvars(labels, Frame, 'Before', 1);
if ~isfolder(fileparts(config.AnchorBoxes)), mkdir(fileparts(config.AnchorBoxes)); end
writetable(labels, config.AnchorBoxes);
end

function closeIfOpen(fig)
if isgraphics(fig), close(fig); end
end
