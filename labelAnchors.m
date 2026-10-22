function labelAnchors(config)
if nargin < 1
    config = projectConfig();
end
if isfile(config.AnchorBoxes)
    error('Project:ExistingAnchorBoxes', ...
        'Anchor boxes already exist: %s. Move that file to relabel.', config.AnchorBoxes);
end

% One row per box: image file and what to enclose.
Frame = ["Anchor1.png"; "Anchor1.png"; "Anchor1.png"; ...
    "Anchor2.png"; "Anchor2.png"; "Anchor2.png"; ...
    "Anchor3.png"];
Part  = ["body"; "label"; "valve"; ...
    "body"; "label"; "valve"; ...
    "body"];
prompt = dictionary("body",  "cylinder + valve, NO hose, minimal floor", ...
    "label", "label area only (text block)", ...
    "valve", "valve, handle and nozzle only");

boxes = zeros(numel(Frame),4);
fig = figure('Name', 'Crop anchors tightly - exclude room background');
cleanup = onCleanup(@() closeIfOpen(fig));
for k = 1:numel(Frame)
    imshow(imread(fullfile(config.AnchorFolder, Frame(k))));
    title(sprintf('%s [%s]: %s. Double-click to confirm.', ...
        Frame(k), Part(k), prompt(Part(k))));
    roi = drawrectangle();
    wait(roi);
    if ~isvalid(roi)
        error('Project:Cancelled', 'Anchor annotation cancelled; nothing saved.');
    end
    boxes(k,:) = roi.Position;
end

labels = array2table(boxes, 'VariableNames', {'X','Y','Width','Height'});
labels = addvars(labels, Frame, Part, 'Before', 1);
if ~isfolder(fileparts(config.AnchorBoxes)), mkdir(fileparts(config.AnchorBoxes)); end
writetable(labels, config.AnchorBoxes);
end

function closeIfOpen(fig)
if isgraphics(fig), close(fig); end
end

%[appendix]{"version":"1.0"}
%---
