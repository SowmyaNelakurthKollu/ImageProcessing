function inside = centerInsideBBox(center,bbox)

%% =========================================================
% Check whether predicted center lies inside ground-truth box
%
% bbox = [x y width height]
% center = [x y]
% ==========================================================

if isempty(center) || isempty(bbox)

    inside = false;
    return;

end

cx = center(1);
cy = center(2);

x = bbox(1);
y = bbox(2);
w = bbox(3);
h = bbox(4);

inside = ...
    cx >= x && ...
    cx <= x+w && ...
    cy >= y && ...
    cy <= y+h;

end