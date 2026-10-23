function descriptor = colorDescriptor(image)
hsv = rgb2hsv(image);
counts = histcounts2(hsv(:,:,1), hsv(:,:,2), linspace(0,1,17), linspace(0,1,5));
descriptor = counts(:) / max(sum(counts(:)),1);
end
