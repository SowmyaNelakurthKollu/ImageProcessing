function [anchorImages, anchorFeatures, anchorValidPoints] = setupAnchors(anchorFolder, config)
if nargin < 2, config = projectConfig(); end
if ~isfile(config.AnchorBoxes)
    error('Project:MissingAnchorBoxes', 'Run labelAnchors before extracting anchor features.');
end
boxes = readtable(config.AnchorBoxes, 'TextType', 'string');
if height(boxes) ~= 3 || numel(unique(boxes.Frame)) ~= 3
    error('Project:InvalidAnchors', 'Exactly three unique anchor boxes are required.');
end
anchorImages = cell(1,3);
anchorFeatures = cell(1,3);
anchorValidPoints = cell(1,3);
for k = 1:3
    name = "Anchor" + k + ".png";
    row = find(boxes.Frame == name);
    if numel(row) ~= 1
        error('Project:InvalidAnchors', 'Missing or duplicate box for %s.', name);
    end
    image = imread(fullfile(anchorFolder, name));
    box = boxes{row, {'X','Y','Width','Height'}};
    if any(~isfinite(box)) || any(box(3:4) <= 0) || ...
            box(1) < 1 || box(2) < 1 || ...
            box(1)+box(3) > size(image,2)+1 || box(2)+box(4) > size(image,1)+1
        error('Project:InvalidAnchors', 'Anchor %d has an invalid bounding box.', k);
    end
    image = imcrop(image, box);
    image = imresize(image, min(1, config.MaxImageSide/max(size(image,1),size(image,2))));
    points = detectSIFTFeatures(im2gray(image));
    if points.Count < config.MinInliers
        error('Project:WeakAnchor', 'Anchor %d has too few SIFT points (%d).', k, points.Count);
    end
    [features, validPoints] = extractFeatures(im2gray(image), points);
    if validPoints.Count < config.MinInliers
        error('Project:WeakAnchor', 'Anchor %d has too few SIFT features (%d).', k, validPoints.Count);
    end
    anchorImages{k} = image;
    anchorFeatures{k} = features;
    anchorValidPoints{k} = validPoints;
    fprintf('Anchor %d: %d SIFT features in object crop.\n', k, validPoints.Count);
end
end
