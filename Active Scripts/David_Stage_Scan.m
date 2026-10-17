%Scans stage across 1 dimension
%0
%Reminders on functions to move stage or get location
%stageLocations = ex.PIstage.axisSum;
%1;
%ex.PIstage = relativeMove(ex.PIstage,'z',-50);

%Default ODMR script example

clear p

%Required
p.scanBounds = {[19900,20000]};
p.scanAxes = {'z'};
p.scanStepSize = {5};
% p.scanBounds = {[1550,1650],[2400,2500]};
% p.scanAxes = {'y','x'};
% p.scanStepSize = {10,10};
p.collectionType = 'analog';%analog or counter
p.contrastVSReference = 'con';

%General    
p.RFFrequency = 2.87;
p.RFAmplitude = 10;
p.scanNotes = ' Stage Scan'; %Notes describing scan (will appear in titles for plots)
for ii = 1:numel(p.scanAxes)
    p.scanNotes = [p.scanAxes{ii},p.scanNotes];
end
p.sequenceTimePerDataPoint = .2;%Before factoring in forced delay and other pauses
p.maxFailedCollections = 5;
p.nIterations = 1; %Number of iterations of scan to perform
p.timeoutDuration = 2; %How long besfore auto-continue occurs
p.forcedDelayTime = 0; %Time to force pause before (1/2) and after (full) collecting data
p.nDataPointDeviationTolerance = 5e-1;%How precies measurement is. Lower number means more exacting values, could lead to repeated failures
p.baselineSubtraction = 0.045;% .069 Amount to subtract from both reference and signal collected
p.perSecond = false;
p.pollInterval = 3;
p.closeFigsEveryIteration = false;
p.intermissionBufferDuration = 1000;%ns

%Config file names
p.pulseBlasterConfig = 'pb_swabian';
p.SRSRFConfig = 'SRS_RF';
% p.DAQConfig = 'daq_6361';
p.DAQConfig = 'daq_testing';
p.stageConfig = 'PI_stage';

%Plotting
p.plotAverageContrast = true;
p.plotCurrentContrast = false;
p.plotAverageReference = true;
p.plotCurrentReference = false;
p.plotAverageSignal = false;
p.plotCurrentSignal = false;
p.plotAverageSNR = true;
p.plotCurrentSNR = false;
p.plotCurrentDataPoints = false;
p.plotAverageDataPoints = false;
p.invertSignalForSNR = false;
p.plotPulseSequence = false;
p.plotAverageContrastFFT = false;
p.plotCurrentContrastFFT = false;

%Stage optimization
p.optimizationEnabled = false; %Set to false to disable stage optimization
p.optimizationAxes = {'z'}; %The axes which will be optimized over
p.optimizationSteps = {-1:0.2:1}; %Locations the stage will move relative to current location
p.optimizationRFStatus = 'off'; %'off', 'on', or 'con' 
p.timePerOpimizationPoint = .2; %Duration of each data point during optimization
p.timeBetweenOptimizations = 180; %Seconds between optimizations (Inf to disable, 0 for optimization after every point)
p.percentageForcedOptimization = .5; %see below (0 to disable)

%percentageForcedOptimization is a more complex way of deciding when to do an optimization.
%After every optimization, the reference value of the next data point is recorded. After every data point, if the
%reference value is lower than X percent of that post-optimization value, a new optimization will be performed. This
%means setting the value to 1 corresponds to running an optimization if the value obtained is lower at all than the
%post-optimization value, .75 means running optimization if less than 3/4 post-optimization value etc.

if ~exist('ex','var') || isempty(ex),ex = []; end

%Runs ODMR using specified parameters
ex = Stage_Scan(ex,p);
