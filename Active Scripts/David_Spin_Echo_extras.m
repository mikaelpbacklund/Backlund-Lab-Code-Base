%Example Spin Echo extras using template

%Required
p.scanBounds = [10 50];
p.scanStepSize = 2;
p.piTime = 34;
p.uncorrectedTauTime = 100;%Before taking into account pi pulses or IQ buffers
p.RFResonanceFrequency = 2.0355;
p.collectionType = 'analog';
p.pulseNotes = 'I/Q buffer';%Exact notes of pulses to scan

%Other
p.sequenceTimePerDataPoint = 4;%seconds
p.collectionDuration = 0;%0 means overwritten by DAQ
p.collectionBufferDuration = 200;
p.intermissionBufferDuration = 2000;
p.repolarizationDuration = 10000;
p.RFRampTime = 4;
p.AOMCompensation = 480;
p.dataOnBuffer = 0;%Time after AOM is on where DAQ continues readout but AOM is shut off
p.extraBuffer = 0;%Pulse after dataOnBuffer where AOM and DAQ are off, before repolarization
p.IQBuffers = [10 10];
p.nIterations = 1;
p.RFAmplitude = 10;
p.timeoutDuration = 3;
p.forcedDelayTime = .25;
p.nDataPointDeviationTolerance = .1;
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
p.plotAverageReference = false;
p.plotCurrentReference = true;
p.plotAverageSignal = false;
p.plotCurrentSignal = false;
p.plotAverageSNR = false;
p.plotCurrentSNR = false;
p.plotCurrentDataPoints = false;
p.plotAverageDataPoints = false;
p.invertSignalForSNR = false;
p.plotPulseSequence = false;

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
ex = SpinEcho_extras(ex,p);