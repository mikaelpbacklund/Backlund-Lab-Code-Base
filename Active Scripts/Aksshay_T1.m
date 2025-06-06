%Example Spin Echo using template

clear p

%Required
p.scanBounds = [1000 1000000];
p.scanStepSize = 200;
p.scanNSteps = [];%will override step size
% p.piTime = 36;
% p.RFResonanceFrequency = 2.269;
p.collectionType = 'analog';

%Other
p.sequenceTimePerDataPoint = 6;%seconds
p.collectionDuration = 0;%0 means overwritten by DAQ
p.collectionBufferDuration = 100;
p.intermissionBufferDuration = 12000;
p.repolarizationDuration = 10000;
% p.extraRF = 4;
p.AOMCompensation = 400;
p.dataOnBuffer = 0;%Time after AOM is on where DAQ continues readout but AOM is shut off
p.extraBuffer = 0;%Pulse after dataOnBuffer where AOM and DAQ are off, before repolarization
p.IQBuffers = [30 0];
p.nIterations = 1;
p.RFAmplitude = 10;
p.timeoutDuration = 3;
p.forcedDelayTime = .25;
p.nDataPointDeviationTolerance = .1;
p.maxFailedCollections = 3;
p.baselineSubtraction = 0;
p.perSecond = false;
p.resetData = true;%Resets data of previous scan. If false, continues adding data to previous scan

%Config file names
p.pulseBlasterConfig = 'pulse_blaster_default';
p.SRSRFConfig = 'SRS_RF';
p.DAQConfig = 'daq_6361';
p.stageConfig = 'PI_stage';

%Plotting
p.plotAverageContrast = true;
p.plotCurrentContrast = false;
p.plotAverageReference = false;
p.plotCurrentReference = true;
p.plotAverageSignal = false;
p.plotCurrentSignal = false;
p.plotAverageSNR = false;
p.plotCurrentSNR = false;
p.plotCurrentDataPoints = false;
p.plotAverageDataPoints = false;
p.invertSignalForSNR = false;
p.plotPulseSequence = true;

%Stage optimization
p.optimizationEnabled = false; %Set to false to disable stage optimization
p.optimizationAxes = {'z'}; %The axes which will be optimized over
p.optimizationSteps = {-.5:0.5:.5}; %Locations the stage will move relative to current location
p.optimizationRFStatus = 'off'; %'off', 'on', 'snr', or 'con'
p.timePerOpimizationPoint = .5; %Duration of each data point during optimization
p.timeBetweenOptimizations = 120; %Seconds between optimizations (Inf to disable, 0 for optimization after every point)
p.useOptimizationTimer = true;
p.percentageForcedOptimization = .75; %see below (0 to disable)
p.useOptimizationPercentage = false;

%percentageForcedOptimization is a more complex way of deciding when to do an optimization.
%After every optimization, the reference value of the next data point is recorded. After every data point, if the
%reference value is lower than X percent of that post-optimization value, a new optimization will be performed. This
%means setting the value to 1 corresponds to running an optimization if the value obtained is lower at all than the
%post-optimization value, .75 means running optimization if less than 3/4 post-optimization value etc.

if ~exist('ex','var') || isempty(ex),ex = []; end

%Runs Spin Echo
ex = SpinEcho(ex,p);