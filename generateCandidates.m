function boxes = generateCandidates(frame, config)
% A target-specific proposal prior; it is not a category-level detector.
hsv = rgb2hsv(frame);
mask = (hsv(:,:,1) < 0.065 | hsv(:,:,1) > 0.94) & ...
    hsv(:,:,2) > 0.45 & hsv(:,:,3) > 0.12;
mask = imclose(mask, strel('disk', 2, 0));
mask = bwareaopen(mask, config.MinimumRedPixels);
regions = regionprops(mask, 'BoundingBox', 'Area');
boxes = zeros(0,4);
areas = zeros(0,1);
for k = 1:numel(regions)
    box = regions(k).BoundingBox;
    if box(4) < 8 || box(4)/box(3) < 1.2 || box(4)/box(3) > 15
        continue;
    end
    % Include the hose above/beside the red cylinder.
    x1 = max(1, floor(box(1) - 0.65*box(3)));
    y1 = max(1, floor(box(2) - 0.85*box(4)));
    x2 = min(size(frame,2), ceil(box(1) + 1.65*box(3)));
    y2 = min(size(frame,1), ceil(box(2) + 1.10*box(4)));
    boxes(end+1,:) = [x1,y1,x2-x1,y2-y1]; %#ok<AGROW>
    areas(end+1,1) = regions(k).Area; %#ok<AGROW>
end
[~, order] = sort(areas, 'descend');
boxes = boxes(order(1:min(numel(order),config.MaxCandidates)),:);
end
