function exportDemo(config)
if nargin < 1, config = projectConfig(); end
experiment = load(fullfile(config.ResultsFolder,'experiment.mat'), ...
    'labels','tables','details','summary');
labels = experiment.labels;
selected = find(labels.Split == "evaluation");
folder = fullfile(config.ResultsFolder,'visualizations');
if ~isfolder(folder), mkdir(folder); end
writer = VideoWriter(fullfile(config.ResultsFolder,'demonstration.mp4'), 'MPEG-4');
writer.FrameRate = 3;
open(writer);
cleanup = onCleanup(@() close(writer));
for k = selected'
    image = imread(fullfile(config.Root,labels.Frame(k)));
    originalSize = [size(image,1),size(image,2)];
    scale = min(1,config.MaxImageSide/max(originalSize));
    image = imresize(image,max(1,round(originalSize*scale)));
    ratio = [size(image,2)/originalSize(2),size(image,1)/originalSize(1)];
    if labels.TargetPresent(k)
        box = scaledBox(labels{k,{'X','Y','Width','Height'}},ratio);
        image = insertShape(image,'Rectangle',box,'Color','cyan','LineWidth',3);
    end
    colors = {'yellow','green'};
    names = {'Color baseline','SIFT final'};
    for m = 1:2
        predictions = experiment.tables{m};
        if predictions.Detected(k)
            box = scaledBox(predictions{k,{'X','Y','Width','Height'}},ratio);
            image = insertShape(image,'Rectangle',box,'Color',colors{m},'LineWidth',3);
        end
        text = sprintf('%s: accepted=%d score=%.3f', ...
            names{m},predictions.Detected(k),predictions.Score(k));
        image = insertText(image,[5,5+(m-1)*30],text,'FontSize',16, ...
            'BoxColor','black','TextColor',colors{m});
    end
    image = insertText(image,[5,size(image,1)-30], ...
        'Cyan = reference | Yellow = baseline | Green = final', ...
        'FontSize',14,'BoxColor','black','TextColor','white');
    writeVideo(writer,image);
    imwrite(image,fullfile(folder,sprintf('frame_%03d.jpg',k)));
end
fprintf('Saved annotated held-out demo and images at %s.\n',config.ResultsFolder);
end

function box = scaledBox(box,ratio)
box(1:2) = (box(1:2)-0.5).*ratio + 0.5;
box(3:4) = box(3:4).*ratio;
end
