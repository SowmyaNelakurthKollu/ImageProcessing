function config = projectConfig()
root = fileparts(mfilename('fullpath'));
config.Root = root;
config.LocalDataSave ='C:\Users\sowmy\OneDrive - Luleå University of Technology\Project_3';
config.RawFolder = 'C:\Users\sowmy\OneDrive - Luleå University of Technology\Project_3\raw';
config.EvalFolder = fullfile(config.RawFolder, 'eval');
config.CameraColorImageRawFolder = fullfile(config.EvalFolder, 'camera_color_image_raw');
config.AnchorFolder = fullfile(root, 'Anchor_Images');
config.AnchorBoxes = fullfile(root, 'annotations', 'anchor_boxes.csv');
config.LabelFile = fullfile(root, 'annotations', 'frames.csv');
config.ResultsFolder = fullfile(root, 'results');
config.Seed = 2026;
config.MaxFramesPerSequence = 40;
config.SplitBlockLength = 20;
config.SplitGuardFrames = 2;
config.MaxImageSide = 1280;
config.CandidateSide = 640;
config.MaxCandidates = 20;
config.MinimumRedPixels = 20;
config.MatchRatio = 0.75;
config.MinInliers = 4;
config.MinInlierRatio = 0.35;
config.MinAnchorCoverage = 0.02;
config.MaxReprojectionError = 4;
config.PrecisionTarget = 0.55;
config.RecallTarget = 0.50;
end

%[appendix]{"version":"1.0"}
%---
