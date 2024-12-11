%Example Spin Echo using template

%Required
p.tauStart = 110;
p.tauEnd = 1510;
p.tauStepSize = 25;
p.piTime = 76;
p.RFResonanceFrequency = 2.4055;

%All parameters below this are optional in that they will revert to defaults if not specified
p.tauNSteps = [];%will override step size
p.timePerDataPoint = 4;%seconds
p.collectionDuration = 0;
p.collectionBufferDuration = 800;
p.intermissionBufferDuration = 2500;
p.repolarizationDuration = 7000;
p.extraRF = 10;
p.AOM_DAQCompensation = 700;
p.IQPreBufferDuration = 22;
p.IQPostBufferDuration = 0;
p.nIterations = 1;
p.RFAmplitude = 10;
p.collectionType = 'counter';
p.timeoutDuration = 3;
p.forcedDelayTime = .25;
p.nDataPointDeviationTolerance = .1;
p.maxFailedCollections = 3;
p.baselineSubtraction = 1.5e4;
p.perSecond = true;

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
p.timeBetweenOptimizations = 180; %Seconds between optimizations (Inf to disable, 0 for optimization after every point)
p.percentageForcedOptimization = .75; %see below (0 to disable)

% Note from Kyle: I added these to prevent an error when running the
% script, not sure if these should be the default values
p.useOptimizationTimer = false;
p.useOptimizationPercentage = 0;

%percentageForcedOptimization is a more complex way of deciding when to do an optimization.
%After every optimization, the reference value of the next data point is recorded. After every data point, if the
%reference value is lower than X percent of that post-optimization value, a new optimization will be performed. This
%means setting the value to 1 corresponds to running an optimization if the value obtained is lower at all than the
%post-optimization value, .75 means running optimization if less than 3/4 post-optimization value etc.

if ~exist('ex','var') || isempty(ex),ex = []; end

%Runs Spin Echo
ex = SpinEcho(ex,p);