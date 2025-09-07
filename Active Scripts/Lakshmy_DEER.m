%Example DEER using template

clear p

%Required
p.scanType = 'frequency';%Either frequency or duration
p.scanBounds = [500e-3 800e-3]; %windfreak frequency (GHz)[400e-3 500e-3] or duration (ns)
p.scanStepSize = 5e-3;%1e-3
% p.scanBounds = [100 500]; %windfreak frequency (GHz) or duration (ns)
% p.scanStepSize = 20;
p.collectionType = 'counter';%analog or counter
p.RF2Frequency = .62055;%GHz. Overwritten by scan if frequency selected
p.RF2Duration = 100;%ns. Overwritten by scan if duration selected
p.nRF2Pulses = 2;%1 for centered on pi pulse, 2 for during tau
p.RF1ResonanceFrequency = 2.23;
p.piTime = 60;
p.tauTime = 600;

%General
p.timePerDataPoint = 4;%Before factoring in forced delay and other pauses
p.collectionDuration = 800;%How long to collect data for. 0 means overwritten by DAQ rate
p.collectionBufferDuration = 1000;%How long to wait between end of RF pulse and beginning of data collection
p.intermissionBufferDuration = 1000;
p.repolarizationDuration = 6500;
p.extraRF = 10;
p.AOMCompensation = 50;%550
p.dataOnBuffer = 800;
p.extraBuffer = 100;
p.IQBuffers = [22 0];
p.RF1Amplitude = 10;
p.RF2Amplitude = 21;%neg 20 dBm attn 23 before
p.nIterations = 500; %Number of iterations of scan to perform
p.timeoutDuration = 3; %How long before auto-continue occurs
p.forcedDelayTime = .25; %Time to force pause before (1/2) and after (full) collecting data
p.nDataPointDeviationTolerance = Inf;%How precies measurement is. Lower number means more exacting values, could lead to repeated failures
p.baselineSubtraction = 0;%Amount to subtract from both reference and signal collected
p.maxFailedCollections = 3;
p.perSecond = true;

%Config file names
p.pulseBlasterConfig = 'pulse_blaster_DEER';
p.SRSRFConfig = 'SRS_RF';
p.DAQConfig = 'daq_6361';
p.stageConfig = 'PI_stage';

%Plotting
p.plotAverageContrast = true;
p.plotCurrentContrast = false;
p.plotAverageReference = true;
p.plotCurrentReference = true;
p.plotAverageSNR = false;
p.plotCurrentSNR = false;
p.plotAveragePercentageDataPoints = true;
p.plotCurrentPercentageDataPoints = true;

%Stage optimization
p.optimizationEnabled = true; %Set to false to disable stage optimization
p.optimizationAxes = {'z'}; %{'x','y','z'}The axes which will be optimized over
p.optimizationSteps = {-0.5:0.1:0.5}; %{-0.2:0.05:.2, -0.2:0.05:.2, -0.5:0.1:.5}Locations the stage will move relative to current location
p.optimizationRFStatus = 'off'; %'off', 'on', or 'con' 
p.timePerOpimizationPoint = .1; %Duration of each data point during optimization
p.timeBetweenOptimizations = 120; %Seconds between optimizations (Inf to disable, 0 for optimization after every point)
p.percentageForcedOptimization = .75; %see below (0 to disable)
p.useOptimizationTimer = true;
p.useOptimizationPercentage = false;

%percentageForcedOptimization is a more complex way of deciding when to do an optimization.
%After every optimization, the reference value of the next data point is recorded. After every data point, if the
%reference value is lower than X percent of that post-optimization value, a new optimization will be performed. This
%means setting the value to 1 corresponds to running an optimization if the value obtained is lower at all than the
%post-optimization value, .75 means running optimization if less than 3/4 post-optimization value etc.

if ~exist('ex','var') || isempty(ex),ex = []; end

%Runs deer
ex = DEER(ex,p);

% savedData = ex.data.values;
% savedScan = ex.scan;
% save("MyFileName","savedData","savedScan")