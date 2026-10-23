function tests = testEvaluation
tests = functiontests(localfunctions);
end

function testCountsIncludeMislocalizedAcceptance(testCase)
[predictions,labels] = fixture();
[metrics,outcomes] = evaluateDetection(predictions,labels);
verifyEqual(testCase,[metrics.TP,metrics.FP,metrics.FN,metrics.TN],[1,2,2,1]);
verifyEqual(testCase,metrics.Precision,1/3,'AbsTol',1e-12);
verifyEqual(testCase,metrics.Recall,1/3,'AbsTol',1e-12);
verifyEqual(testCase,metrics.LocalizationSuccess,1/3,'AbsTol',1e-12);
verifyTrue(testCase,outcomes.FP(2) && outcomes.FN(2));
end

function testFrameAlignment(testCase)
[predictions,labels] = fixture();
a = evaluateDetection(predictions,labels);
b = evaluateDetection(predictions,labels(end:-1:1,:));
verifyEqual(testCase,a,b);
labels.Frame(1) = "missing";
verifyError(testCase,@() evaluateDetection(predictions,labels),'Project:FrameMismatch');
end

function testRejectUnknownLabelsAndInvalidCenters(testCase)
[predictions,labels] = fixture();
labels.TargetPresent(1) = NaN;
verifyError(testCase,@() evaluateDetection(predictions,labels),'Project:InvalidLabels');
[predictions,labels] = fixture();
predictions.CenterX(1) = NaN;
verifyError(testCase,@() evaluateDetection(predictions,labels),'Project:InvalidPrediction');
end

function testReviewAndDuplicateChecks(testCase)
[predictions,labels] = fixture();
labels.Reviewed = false(height(labels),1);
verifyError(testCase,@() evaluateDetection(predictions,labels),'Project:UnreviewedLabels');
[predictions,labels] = fixture();
predictions.Frame(2) = predictions.Frame(1);
verifyError(testCase,@() evaluateDetection(predictions,labels),'Project:InvalidFrames');
end

function testZeroDenominators(testCase)
[predictions,labels] = fixture();
predictions.Detected(:) = false;
metrics = evaluateDetection(predictions,labels);
verifyEqual(testCase,metrics.Precision,0);
verifyFalse(testCase,metrics.PrecisionDefined);
labels.TargetPresent(:) = 0;
metrics = evaluateDetection(predictions,labels);
verifyFalse(testCase,metrics.RecallDefined);
verifyEqual(testCase,metrics.TN,5);
end

function testThresholdUsesLocalizationAndValidity(testCase)
[predictions,labels] = fixture();
predictions.Score = [10;9;2;8;0];
predictions.Valid = [true;true;false;true;false];
[sweep,threshold,feasible] = tuneThreshold(predictions,labels,[0;9.5;Inf],0.75,0.3);
verifyEqual(testCase,sweep.FP(1),2);
verifyEqual(testCase,threshold,9.5);
verifyTrue(testCase,feasible);
verifyEqual(testCase,sweep.TP(end),0);
end

function testCenterRule(testCase)
verifyTrue(testCase,centerInsideBBox([10,10],[1,1,9,9]));
verifyFalse(testCase,centerInsideBBox([NaN,2],[1,1,9,9]));
verifyFalse(testCase,centerInsideBBox([2,2],[1,1,-1,9]));
end

function [predictions,labels] = fixture()
Frame = ["a";"b";"c";"d";"e"];
predictions = table(Frame,[true;true;false;true;false], ...
    [5;50;NaN;5;NaN],[5;50;NaN;5;NaN], ...
    'VariableNames',{'Frame','Detected','CenterX','CenterY'});
labels = table(Frame,[1;1;1;0;0],ones(5,1),ones(5,1), ...
    9*ones(5,1),9*ones(5,1), ...
    'VariableNames',{'Frame','TargetPresent','X','Y','Width','Height'});
end
