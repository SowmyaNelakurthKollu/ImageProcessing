function exportDemo(config)
if nargin < 1, config = projectConfig(); end
experiment = load(fullfile(config.ResultsFolder,'experiment.mat'), ...
    'labels','tables','details','summary');
labels = experiment.labels;
selected = find(labels.Split == "evaluation");

methods = {'baseline','final'};
colors = {'yellow','green'};
names = {'Color baseline','SIFT final'};
root = fullfile(config.ResultsFolder,'visualizations');

% Work out each method's outcome for every evaluation frame.
% selected(j) is the row in labels, and outcomes row j matches it.
outcomeFolder = strings(numel(selected),2);
for m = 1:2
    predictions = experiment.tables{m};
    [~, outcomes] = evaluateDetection(predictions(selected,:), labels(selected,:));
    for j = 1:numel(selected)
        outcomeFolder(j,m) = outcomeName(outcomes, j);
    end
end

% Clear outcome folders from earlier runs.
categories = ["TruePositives","TrueNegatives","FalsePositives","FalseNegatives"];
for m = 1:2
    for c = categories
        d = fullfile(root, methods{m}, c);
        if isfolder(d), rmdir(d,'s'); end
    end
end

writer = VideoWriter(fullfile(config.ResultsFolder,'demonstration.mp4'), 'MPEG-4');
writer.FrameRate = 3;
open(writer);
cleanup = onCleanup(@() close(writer));

for j = 1:numel(selected)
    k = selected(j);
    image = imread(fullfile(config.LocalDataSave,labels.Frame(k)));
    originalSize = [size(image,1),size(image,2)];
    scale = min(1,config.MaxImageSide/max(originalSize));
    image = imresize(image,max(1,round(originalSize*scale)));
    ratio = [size(image,2)/originalSize(2),size(image,1)/originalSize(1)];

    if labels.TargetPresent(k)
        box = scaledBox(labels{k,{'X','Y','Width','Height'}},ratio);
        image = insertShape(image,'Rectangle',box,'Color','cyan','LineWidth',3);
    end
    reference = image;   % reference box only, reused for the per-method images

    % Combined frame for the video (both methods).
    for m = 1:2
        image = drawMethod(image, experiment.tables{m}, k, ratio, m, colors, names);
    end
    image = addLegend(image);
    writeVideo(writer,image);

    % One image per method, showing only that method, in its outcome folder.
    for m = 1:2
        single = drawMethod(reference, experiment.tables{m}, k, ratio, m, colors, names);
        single = addLegend(single);
        outDir = fullfile(root, methods{m}, outcomeFolder(j,m));
        if ~isfolder(outDir), mkdir(outDir); end
        imwrite(single, fullfile(outDir, sprintf('frame_%03d.jpg',k)));
    end
end
fprintf('Saved annotated held-out demo and images at %s.\n',config.ResultsFolder);
end

function image = drawMethod(image, predictions, k, ratio, m, colors, names)
if predictions.Detected(k)
    box = scaledBox(predictions{k,{'X','Y','Width','Height'}},ratio);
    image = insertShape(image,'Rectangle',box,'Color',colors{m},'LineWidth',3);
end
text = sprintf('%s: accepted=%d score=%.3f', ...
    names{m}, predictions.Detected(k), predictions.Score(k));
image = insertText(image,[5,5+(m-1)*30],text,'FontSize',16, ...
    'BoxColor','black','TextColor',colors{m});
end

function image = addLegend(image)
image = insertText(image,[5,size(image,1)-30], ...
    'Cyan = reference | Yellow = baseline | Green = final', ...
    'FontSize',14,'BoxColor','black','TextColor','white');
end

function name = outcomeName(outcomes, j)
if outcomes.TP(j)
    name = "TruePositives";
elseif outcomes.FP(j)
    name = "FalsePositives";
elseif outcomes.TN(j)
    name = "TrueNegatives";
else
    name = "FalseNegatives";
end
end

function box = scaledBox(box,ratio)
box(1:2) = (box(1:2)-0.5).*ratio + 0.5;
box(3:4) = box(3:4).*ratio;
end