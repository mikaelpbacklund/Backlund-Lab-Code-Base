%Example DEER using template

%Required
p.scanType = 'duration';%Either frequency or duration
p.scanBounds = [10 200]; %windfreak frequency (GHz) or duration (ns)
p.scanStepSize = 10;
p.collectionType = 'counter';%analog or counter
p.RF2Frequency = .46541;%GHz. Overwritten by scan if frequency selected
p.RF2Duration = 100;%ns. Overwritten by scan if duration selected
p.nRF2Pulses = 1;%1 for centered on pi pulse, 2 for during tau
p.RF1ResonanceFrequency = 2.405;
p.piTime = 66;
p.tauTime = 400;

%General
p.timePerDataPoint = 6;%Before factoring in forced delay and other pauses
p.collectionDuration = 0;%How long to collect data for. 0 means overwritten by DAQ rate
p.collectionBufferDuration = 1000;%How long to wait between end of RF pulse and beginning of data collection
p.intermissionBufferDuration = 2500;
p.repolarizationDuration = 7000;
p.extraRF = 0;
p.AOM_DAQCompensation = 300;
p.IQPreBufferDuration = 22;
p.IQPostBufferDuration = 0;
p.RF1Amplitude = 10;
p.RF2Amplitude = 19;
p.nIterations = 20; %Number of iterations of scan to perform
p.timeoutDuration = 3; %How long before auto-continue occurs
p.forcedDelayTime = .125; %Time to force pause before (1/2) and after (full) collecting data
p.nDataPointDeviationTolerance = .1;%How precies measurement is. Lower number means more exacting values, could lead to repeated failures
p.baselineSubtraction = 0;%Amount to subtract from both reference and signal collected
p.maxFailedCollections = 3;

%Config file names
p.pulseBlasterConfig = 'pulse_blaster_DEER';
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
p.optimizationSteps = {-2:0.1:2}; %Locations the stage will move relative to current location
p.optimizationRFStatus = 'off'; %'off', 'on', or 'con' 
p.timePerOpimizationPoint = .1; %Duration of each data point during optimization
p.timeBetweenOptimizations = 300; %Seconds between optimizations (Inf to disable, 0 for optimization after every point)
p.percentageForcedOptimization = .75; %see below (0 to disable)

%percentageForcedOptimization is a more complex way of deciding when to do an optimization.
%After every optimization, the reference value of the next data point is recorded. After every data point, if the
%reference value is lower than X percent of that post-optimization value, a new optimization will be performed. This
%means setting the value to 1 corresponds to running an optimization if the value obtained is lower at all than the
%post-optimization value, .75 means running optimization if less than 3/4 post-optimization value etc.

if ~exist('ex','var') || isempty(ex),ex = []; end

%Runs deer
ex = DEER(ex,p);