%Example Spin Echo using template

clear p

%Required
p.scanBounds = [200 5200];
p.scanStepSize = 1000;
p.collectionType = 'counter';
p.piTime = 110;
p.RFResonanceFrequency = 2.44;
p.scanNSteps = [];%will override step size

%All parameters below this are optional in that they will revert to defaults if not specified 
p.sequenceTimePerDataPoint = 4;%seconds
p.collectionDuration = 0;
p.collectionBufferDuration = 100;
p.intermissionBufferDuration = 1000;
p.repolarizationDuration = 7000;
p.RFRampTime = 10;
p.AOM_DAQCompensation = 700;%550
p.dataOnBuffer = 800;%Time after AOM is on where DAQ continues readout but AOM is shut off
p.extraBuffer = 100;%Pulse after dataOnBuffer where AOM and DAQ are off, before repolarization
p.IQBuffers = [22 0];
p.nIterations = 1;
p.RFAmplitude = 10;
p.timeoutDuration = 3;
p.forcedDelayTime = .25;
p.nDataPointDeviationTolerance = .1;
p.maxFailedCollections = 3;
p.baselineSubtraction = 0;
p.perSecond = true;

%Config file names
p.pulseBlasterConfig = 'pulse_blaster_DEER';
p.SRSRFConfig = 'SRS_RF';
p.DAQConfig = 'daq_6361';
p.stageConfig = 'PI_stage';

%Plotting
p.plotAverageContrast = true;
p.plotCurrentContrast = false;
p.plotAverageReference = false;
p.plotCurrentReference = true;
p.plotAverageSNR = false;
p.plotCurrentSNR = false;
p.invertSignalForSNR = false;

%Stage optimization
p.optimizationEnabled = true; %Set to false to disable stage optimization
p.optimizationAxes = {'x','y','z'}; %The axes which will be optimized over
p.optimizationSteps = {-0.2:0.05:.2, -0.2:0.05:.2, -0.5:0.1:.5}; %Locations the stage will move relative to current location
p.optimizationRFStatus = 'off'; %'off', 'on', or 'con' 
p.timePerOpimizationPoint = .1; %Duration of each data point during optimization
p.timeBetweenOptimizations = 60; %Seconds between optimizations (Inf to disable, 0 for optimization after every point)
p.percentageForcedOptimization = .75; %see below (0 to disable)
p.useOptimizationTimer = true;
p.useOptimizationPercentage = false;

%percentageForcedOptimization is a more complex way of deciding when to do an optimization.
%After every optimization, the reference value of the next data point is recorded. After every data point, if the
%reference value is lower than X percent of that post-optimization value, a new optimization will be performed. This
%means setting the value to 1 corresponds to running an optimization if the value obtained is lower at all than the
%post-optimization value, .75 means running optimization if less than 3/4 post-optimization value etc.

if ~exist('ex','var') || isempty(ex),ex = []; end

%Runs Spin Echo
ex = SpinEcho(ex,p);