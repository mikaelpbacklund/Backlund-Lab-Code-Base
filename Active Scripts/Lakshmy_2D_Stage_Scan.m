%Scans stage across 1 dimension

%Reminders on functions to move stage or get location
%stageLocations = ex.PIstage.axisSum;
%ex.PIstage = absoluteMove(ex.PIstage,'z',7500);
%ex.PIstage = relativeMove(ex.PIstage,'z',-50);

clear p

%% User Inputs
p.scanBounds = {[-1395 -1390],[-72 -68]};
p.scanAxes = {'x','y'};
p.scanStepSize = {.2,.2};
p.collectionType = 'counter';%analog or counter

%General
p.contrastVSReference = 'ref';%'ref' or 'con'. If con, applies ODMR sequence but shows ref and con; if ref, uses fast sequence and only shows ref
p.sequenceTimePerDataPoint = .05;%Before factoring in forced delay and other pauses
p.scanNotes = 'Stage scan'; %Notes describing scan (will appear in titles for plots)
p.RFAmplitude = 10;%Only applicable if contrast enabled
p.RFFrequency = 2.87;%Only applicable if contrast enabled
p.nIterations = 1; %Number of iterations of scan to perform
p.timeoutDuration = 10; %How long before auto-continue occurs
p.forcedDelayTime = 0; %Time to force pause before (1/2) and after (full) collecting data
p.nDataPointDeviationTolerance = .0001;%How precies measurement is. Lower number means more exacting values, could lead to repeated failures
p.baselineSubtraction = 0;%Amount to subtract from both reference and signal collected
p.perSecond = true;
p.intermissionBufferDuration = 1000;