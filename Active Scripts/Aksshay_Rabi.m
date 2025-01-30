%Runs a simple Rabi sequence

%Highly recommended to use a "time per data point" of at least 3 seconds
%Lower than this is sensitive to jitters in number of points collected,
%resulting in failed and/or erroneous points

%Required
p.scanBounds = [10 410]; %RF duration bounds
p.scanStepSize = 10; %Step size for RF duration
p.collectionType = 'analog';%analog or counter
p.RFResonanceFrequency = 2.0355;

%General
p.RFAmplitude = 10;
p.sequenceTimePerDataPoint = 3;%Before factoring in forced delay and other pauses
p.nIterations = 1; %Number of iterations of scan to perform
p.timeoutDuration = 10; %How long before auto-continue occurs
p.forcedDelayTime = .125; %Time to force pause before (1/2) and after (full) collecting data
p.nDataPointDeviationTolerance = .1;%How precies measurement is. Lower number means more exacting values, could lead to repeated failures
p.baselineSubtraction = 0;%Amount to subtract from both reference and signal collected
p.collectionDuration = 0;%How long to collect data for. 0 means overwritten by DAQ rate
p.collectionBufferDuration = 100;%How long to wait between end of RF pulse and beginning of data collection
p.intermissionBufferDuration = 20000;%How long to wait between signal and reference halves of the sequence
p.AOMCompensation = 500;%How long AOM should be on before DAQ (negative flips to DAQ first)
p.repolarizationDuration = 10000;
p.RFReduction = 0;%Time to add to each RF pulse due to RF generator reducing pulse duration
p.perSecond = true;%convert to counts/s if using counter

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

%Runs Rabi using specified parameters
ex = Rabi(ex,p);
