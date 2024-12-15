%Example DEER using template

%Required
p.scanType = 'frequency';%Either frequency or duration
p.scanBounds = [425e-3 500e-3]; %windfreak frequency (GHz) or duration (ns)
p.scanStepSize = 1e-3;
% p.scanBounds = [100 500]; %windfreak frequency (GHz) or duration (ns)
% p.scanStepSize = 20;
p.collectionType = 'counter';%analog or counter
p.RF2Frequency = .464;%GHz. Overwritten by scan if frequency selected
p.RF2Duration = 400;%ns. Overwritten by scan if duration selected
p.nRF2Pulses = 2;%1 for centered on pi pulse, 2 for during tau
p.RF1ResonanceFrequency = 2.4055;
p.piTime = 76;
p.tauTime = 550;

%General
% p.timePerDataPoint = 20;%Before factoring in forced delay and other pauses
% p.collectionDuration = 0;%How long to collect data for. 0 means overwritten by DAQ rate
% p.collectionBufferDuration = 100;%How long to wait between end of RF pulse and beginning of data collection
% p.intermissionBufferDuration = 1000;
% p.repolarizationDuration = 7000;
% p.extraRF = 10;
% p.AOM_DAQCompensation = 550;
% p.dataOnBuffer = 800;
% p.extraBuffer = 100;
% p.IQPreBufferDuration = 22;
% p.IQPostBufferDuration = 0;
% p.RF1Amplitude = 10;
% p.RF2Amplitude = 23;
% p.nIterations = 100; %Number of iterations of scan to perform
% p.timeoutDuration = 3; %How long before auto-continue occurs
% p.forcedDelayTime = .125; %Time to force pause before (1/2) and after (full) collecting data
% p.nDataPointDeviationTolerance = .1;%How precies measurement is. Lower number means more exacting values, could lead to repeated failures
% p.baselineSubtraction = 0;%Amount to subtract from both reference and signal collected
% p.maxFailedCollections = 3;
% p.perSecond = true;

%Config file names
% p.pulseBlasterConfig = 'pulse_blaster_DEER';
% p.SRSRFConfig = 'SRS_RF';
% p.DAQConfig = 'daq_6361';
% p.stageConfig = 'PI_stage';

%Plotting
% p.plotAverageContrast = true;
% p.plotCurrentContrast = true;
% p.plotAverageReference = true;
% p.plotCurrentReference = true;
% p.plotAverageSNR = false;
% p.plotCurrentSNR = false;
% p.plotAveragePercentageDataPoints = true;
% p.plotCurrentPercentageDataPoints = true;

%Stage optimization
% p.optimizationEnabled = false; %Set to false to disable stage optimization
% p.optimizationAxes = {'z'}; %The axes which will be optimized over
% p.optimizationSteps = {-.5:0.1:.5}; %Locations the stage will move relative to current location
% p.optimizationRFStatus = 'off'; %'off', 'on', or 'con' 
% p.timePerOpimizationPoint = .1; %Duration of each data point during optimization
% p.timeBetweenOptimizations = 300; %Seconds between optimizations (Inf to disable, 0 for optimization after every point)
% p.percentageForcedOptimization = .75; %see below (0 to disable)

%percentageForcedOptimization is a more complex way of deciding when to do an optimization.
%After every optimization, the reference value of the next data point is recorded. After every data point, if the
%reference value is lower than X percent of that post-optimization value, a new optimization will be performed. This
%means setting the value to 1 corresponds to running an optimization if the value obtained is lower at all than the
%post-optimization value, .75 means running optimization if less than 3/4 post-optimization value etc.

if ~exist('ex','var') || isempty(ex),ex = []; end

%Runs deer
ex = DEER(ex,p);