function [anchorImages, anchorFeatures, anchorValidPoints, anchorInfo] = setupAnchors(anchorFolder, config)
if nargin < 2, config = projectConfig(); end
if ~isfile(config.AnchorBoxes)
    error('Project:MissingAnchorBoxes', 'Run labelAnchors before extracting anchor features.');
end
boxes = readtable(config.AnchorBoxes, 'TextType', 'string');
if ~ismember('Part', boxes.Properties.VariableNames)
    boxes.Part = repmat("body", height(boxes), 1);   % old CSV: treat as body
end

anchorImages = {}; anchorFeatures = {}; anchorValidPoints = {};
anchorInfo = table('Size',[0 3], 'VariableTypes',{'string','string','double'}, ...
    'VariableNames',{'Frame','Part','Height'});

for k = 1:height(boxes)
    name = boxes.Frame(k);
    image = imread(fullfile(anchorFolder, name));
    box = boxes{k, {'X','Y','Width','Height'}};
    if any(~isfinite(box)) || any(box(3:4) <= 0) || ...
            box(1) < 1 || box(2) < 1 || ...
            box(1)+box(3) > size(image,2)+1 || box(2)+box(4) > size(image,1)+1
        error('Project:InvalidAnchors', 'Row %d (%s) has an invalid bounding box.', k, name);
    end
    crop = imcrop(image, box);

    if boxes.Part(k) == "body"
        heights = config.AnchorBodyHeights;     % e.g. [250 180 120]
    else
        heights = config.AnchorPartHeights;     % e.g. [120 80]
    end

    for h = heights
        scale = h / size(crop,1);
        scaled = imresize(crop, scale);

        if min(size(scaled,1), size(scaled,2)) < 32
            warning('Skipping %s [%s] at %d px: image too small after resize.', ...
                name, boxes.Part(k), h);
            continue;
        end

        g = im2gray(scaled);
        points = detectSIFTFeatures(g, 'ContrastThreshold', config.ContrastThreshold);

        if points.Count < config.MinAnchorPoints
            warning('Skipping %s [%s] at %d px: only %d SIFT points.', ...
                name, boxes.Part(k), h, points.Count);
            continue;
        end

        [features, validPoints] = extractFeatures(g, points);
        anchorImages{end+1} = scaled;           %#ok<AGROW>
        anchorFeatures{end+1} = features;       %#ok<AGROW>
        anchorValidPoints{end+1} = validPoints; %#ok<AGROW>
        anchorInfo(end+1,:) = {name, boxes.Part(k), h}; %#ok<AGROW>
        fprintf('%s [%s] %d px: %d SIFT features.\n', ...
            name, boxes.Part(k), h, validPoints.Count);
    end
end
if isempty(anchorImages)
    error('Project:WeakAnchor', 'No anchor produced enough SIFT points.');
end
end