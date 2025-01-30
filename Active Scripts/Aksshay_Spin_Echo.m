%Example Spin Echo using template

%Required
p.tauStart = 200;
p.tauEnd = 11000;
p.tauStepSize = 100;
p.tauNSteps = [];%will override step size
p.piTime = 36;
p.RFResonanceFrequency = 2.0355;
p.collectionType = 'analog';

%For pi scanning
p.scanPi = false;%If true, scans pi using settings below instead of tau
p.givenTau = 500;
p.piStart = 12;
p.piEnd = 240;
piStepSize = 4;
p.piNSteps = ((p.piEnd - p.piStart)/piStepSize) + 1;

%Other
p.sequenceTimePerDataPoint = 5.0;%seconds
p.collectionDuration = 800;%0 means overwritten by DAQ
p.collectionBufferDuration = 1000;%
p.intermissionBufferDuration =10000;%
p.repolarizationDuration = 10000;%
p.extraRF = 6;
p.AOMCompensation = 600;
p.IQBuffers = [22 8];

p.nIterations = 1;
p.RFAmplitude = 10;
p.timeoutDuration = 3;
p.forcedDelayTime = .25;%
p.nDataPointDeviationTolerance = .05;%
p.maxFailedCollections = 3;
p.baselineSubtraction = 0;
p.perSecond = true;

%Config file names
p.pulseBlasterConfig = 'pulse_blaster_default';
p.SRSRFConfig = 'SRS_RF';
p.DAQConfig = 'daq_6361';
p.stageConfig = 'PI_stage';

%Plotting
p.plotAverageContrast = true;
p.plotCurrentContrast = false;
p.plotAverageReference = true;
p.plotCurrentReference = false;
p.plotAverageSNR = false;
p.plotCurrentSNR = false;
p.plotCurrentPercentageDataPoints = false;
p.plotAveragePercentageDataPoints = false;
p.invertSignalForSNR = false;

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