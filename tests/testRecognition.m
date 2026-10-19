function tests = testRecognition
tests = functiontests(localfunctions);
end

function testNoCandidateIsNeverAcceptedAtZeroThreshold(testCase)
config = projectConfig();
frame = uint8(zeros(100,100,3));
baseline = recognizeBaseline(frame,{frame,frame,frame},0,config);
final = recognizeTarget(frame,{}, {}, {},0,config);
verifyFalse(testCase,baseline.targetPresent);
verifyFalse(testCase,final.targetPresent);
verifyFalse(testCase,final.valid);
verifyEmpty(testCase,final.center);
end

function testRedProposalsAndHistogram(testCase)
config = projectConfig();
image = uint8(zeros(100,100,3));
image(40:80,45:55,1) = 255;
boxes = generateCandidates(image,config);
verifyGreaterThanOrEqual(testCase,size(boxes,1),1);
verifyTrue(testCase,centerInsideBBox([50,60],boxes(1,:)));
descriptor = colorDescriptor(image);
verifyEqual(testCase,sum(descriptor),1,'AbsTol',1e-12);
verifyEqual(testCase,sum(sqrt(descriptor.*descriptor)),1,'AbsTol',1e-12);
end

function testSyntheticSIFTLocalization(testCase)
config = projectConfig();
rng(2026,'twister');
texture = uint8(255*rand(180,120,3));
gray = im2gray(texture);
points = detectSIFTFeatures(gray);
[features,points] = extractFeatures(gray,points);
frame = uint8(zeros(300,260,3));
frame(51:230,41:160,:) = texture;
proposal = [41,51,119,179];
result = recognizeTarget(frame,{features},{points},{texture},0,config,proposal);
verifyTrue(testCase,result.targetPresent);
verifyTrue(testCase,centerInsideBBox(result.center,proposal));
verifyGreaterThanOrEqual(testCase,result.numInliers,config.MinInliers);
verifySize(testCase,result.polygon,[4,2]);
end
