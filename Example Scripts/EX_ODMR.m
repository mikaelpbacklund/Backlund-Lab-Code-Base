%Default ODMR script example

%Required
p.scanBounds = [2.7 3]; %Frequency bounds
p.scanStepSize = .005; %Step size for RF frequency
p.collectionType = 'analog';%analog or counter

%General
p.RFamplitude = 10;
p.scanNotes = 'ODMR'; %Notes describing scan (will appear in titles for plots)
p.sequenceTimePerDataPoint = .25;%Before factoring in forced delay and other pauses
p.nIterations = 1; %Number of iterations of scan to perform
p.timeoutDuration = 10; %How long before auto-continue occurs
p.forcedDelayTime = .125; %Time to force pause before (1/2) and after (full) collecting data
p.nDataPointDeviationTolerance = .0001;%How precies measurement is. Lower number means more exacting values, could lead to repeated failures
p.baselineSubtraction = 0;%Amount to subtract from both reference and signal collected

%Config file names
p.pulseBlasterConfig = 'pulse_blaster_default';
p.SRSRFConfig = 'SRS_RF';
p.DAQConfig = 'daq_6361';
p.stageConfig = 'PI_stage';

%Plotting
p.plotAverageContrast = true;
p.plotCurrentContrast = true;
p.plotAverageReference = true;
p.plotCurrentReference = true;

%Stage optimization
p.optimizationEnabled = false; %Set to false to disable stage optimization
p.optimizationAxes = {'z'}; %The axes which will be optimized over
p.optimizationSteps = {-2:0.25:2}; %Locations the stage will move relative to current location
p.optimizationRFStatus = 'off'; %'off', 'on', or 'con' 
p.timePerOpimizationPoint = .1; %Duration of each data point during optimization
p.timeBetweenOptimizations = 180; %Seconds between optimizations (Inf to disable, 0 for optimization after every point)
p.percentageForcedOptimization = .75; %see below (0 to disable)

%percentageForcedOptimization is a more complex way of deciding when to do an optimization.
%After every optimization, the reference value of the next data point is recorded. After every data point, if the
%reference value is lower than X percent of that post-optimization value, a new optimization will be performed. This
%means setting the value to 1 corresponds to running an optimization if the value obtained is lower at all than the
%post-optimization value, .75 means running optimization if less than 3/4 post-optimization value etc.

if ~exist('ex','var') || isempty(ex),ex = []; end

%Runs ODMR using specified parameters
ex = ODMR(ex,p);