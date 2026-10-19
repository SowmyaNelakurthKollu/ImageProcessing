% Reproducible entry point. Annotation dialogs save progress after each frame.
config = projectConfig();
if ~isfile(config.AnchorBoxes), labelAnchors(config); end
if ~isfile(config.LabelFile), prepareAnnotations(config); end
labelProject(config);
testResults = runtests(fullfile(config.Root,'tests'));
assertSuccess(testResults);
summary = runProject(config);
exportDemo(config);
