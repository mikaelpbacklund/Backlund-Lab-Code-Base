%Example Spin Echo using template

%Required
p.tauStart = 400;
p.tauEnd = 5000;
p.tauStepSize = 300;
p.piTime = 95;
p.RFResonanceFrequency = 2.87;

%All parameters below this are optional in that they will revert to defaults if not specified
p.tauNSteps = [];%will override step size
p.timePerDataPoint = 8;%seconds
p.collectionDuration = 0;
p.collectionBufferDuration = 1000;
p.intermissionBufferDuration = 2500;
p.repolarizationDuration = 7000;
p.extraRF =  0;
p.AOM_DAQCompensation = 0;
p.IQPreBufferDuration = 0;
p.IQPostBufferDuration = 0;
p.nIterations = 1;
p.RFAmplitude = 10;
p.dataType = 'analog';
p.timeoutDuration = 10;
p.forcedDelayTime = .25;
p.nDataPointDeviationTolerance = .00015;

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
p.optimizationEnabled = true; %Set to false to disable stage optimization
p.optimizationAxes = {'z'}; %The axes which will be optimized over
p.optimizationSteps = {-2:0.1:2}; %Locations the stage will move relative to current location
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

%Runs Spin Echo
ex = SpinEcho(ex,p);