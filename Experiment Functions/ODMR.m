function ex = ODMR(ex,p)
%p is parameter structure

requiredParams = {'scanBounds','scanStepSize','collectionType'};

mustContainField(p,requiredParams)

paramsWithDefaults = {'plotAverageContrast',true;...
   'plotAverageReference',true;...
   'plotCurrentContrast',true;...
   'plotCurrentReference',true;...
   'plotCurrentPercentageDataPoints',false;...
   'plotAveragetPercentageDataPoints',false;...
   'plotAverageSNR',false;...
   'plotCurrentSNR',false;...
   'RFAmplitude',10;...
   'scanNotes','ODMR';...
   'sequenceTimePerDataPoint',.2;...
   'nIterations',1;...
   'perSecond',true;...
   'timeoutDuration',10;...
   'forcedDelayTime',.125;...
   'nDataPointDeviationTolerance',.0001;...
   'baselineSubtraction',0;...
   'maxFailedCollections',3;...
   'optimizationEnabled',false;...
   'optimizationAxes',{'z'};...
   'optimizationSteps',{-2:.25:2};...
   'optimizationRFStatus','off';...
   'timePerOpimizationPoint',.1;...
   'timeBetweenOptimizations',180;...
   'percentageForcedOptimization',.75;...
   'pulseBlasterConfig','pulse_blaster_default';...
   'SRSRFConfig','SRS_RF';...
   'DAQConfig','daq_6361';...
   'stageConfig','PI_stage'};

p = mustContainField(p,paramsWithDefaults(:,1),paramsWithDefaults(:,2));

%This warning *should* be suppressed in the DAQ code but isn't for an unknown reason. This is not related to my code but
%rather the data acquisition toolbox code which I obviously can't change
warning('off','MATLAB:subscripting:noSubscriptsSpecified');

%This warning is for unreachable code. This will usually happen in this file dependant on user settings at the start
%#ok<*UNRCH>

%Creates experiment object if none exists
if ~exist('ex','var') || isempty(ex),   ex = experiment;   end

%Loads pulse blaster, srs rf, and daq with given configs
instrumentNames = ["pulse blaster","srs rf","daq"];
instrumentConfigs = [c2s(p.pulseBlasterConfig),c2s(p.SRSRFConfig),c2s(p.DAQConfig)];
ex = loadInstruments(ex,instrumentNames,instrumentConfigs,false);

ex.optimizationInfo.enableOptimization = p.optimizationEnabled;

%Loads stage if optimization is enabled
if p.optimizationEnabled
   ex = loadInstruments(ex,"stage",c2s(p.stageConfig),false);
end


%Turns RF on, disables modulation, and sets amplitude to 10 dBm
ex.SRS_RF.enabled = 'on';
ex.SRS_RF.modulationEnabled = 'off';
ex.SRS_RF.amplitude = p.RFAmplitude;

%Temporarily disables taking data, differentiates signal and reference (to get contrast), and sets data channel to
%counter
ex.DAQ.takeData = false;
ex.DAQ.differentiateSignal = 'on';
ex.DAQ.activeDataChannel = p.collectionType;

%Sets loops for entire sequence to "on". Deletes previous sequence if any existed
ex.pulseBlaster.nTotalLoops = 1;%will be overwritten later, used to find time for 1 loop
ex.pulseBlaster.useTotalLoop = true;
ex.pulseBlaster = deleteSequence(ex.pulseBlaster);

%For each of the following sections:
%Clear previous information
%Set which channels should be active in the pulse blaster
%Set how long this pulse should run for
%List any notes to describe the pulse
%Add the pulse to the current sequence
clear pulseInfo 
pulseInfo.activeChannels = {};
pulseInfo.duration = 2500;
pulseInfo.notes = 'Initial buffer';
ex.pulseBlaster = addPulse(ex.pulseBlaster,pulseInfo);

%Condensed version below puts this on one line
ex.pulseBlaster = condensedAddPulse(ex.pulseBlaster,{'AOM','DAQ'},1e6,'Reference');
ex.pulseBlaster = condensedAddPulse(ex.pulseBlaster,{},2500,'Middle buffer signal off');
ex.pulseBlaster = condensedAddPulse(ex.pulseBlaster,{'Signal'},2500,'Middle buffer signal on');
ex.pulseBlaster = condensedAddPulse(ex.pulseBlaster,{'AOM','DAQ','RF','Signal'},1e6,'Signal');
ex.pulseBlaster = condensedAddPulse(ex.pulseBlaster,{'Signal'},2500,'Final buffer');

%Gets duration of user sequence in order to change number of loops to match desired time for each data point
ex.pulseBlaster = calculateDuration(ex.pulseBlaster,'user');
ex.pulseBlaster.nTotalLoops = floor(p.sequenceTimePerDataPoint/ex.pulseBlaster.sequenceDurations.user.totalSeconds);

%Sends the currently saved pulse sequence to the pulse blaster instrument itself
ex.pulseBlaster = sendToInstrument(ex.pulseBlaster);

%Deletes any pre-existing scan
ex.scan = [];

scan.bounds = p.scanBounds; %RF frequency bounds
scan.stepSize = p.scanStepSize; %Step size for RF frequency
scan.parameter = 'frequency'; %Scan frequency parameter
scan.identifier = ex.SRS_RF.identifier; %Instrument has identifier 'SRS RF' (not needed if only one RF generator is connected)
scan.notes = p.scanNotes; %Notes describing scan (will appear in titles for plots)

%Add the current scan
ex = addScans(ex,scan);

%Adds time (in seconds) after pulse blaster has stopped running before continuing to execute code
ex.forcedCollectionPauseTime = p.forcedDelayTime;

%Number of failed collections before giving error
ex.maxFailedCollections = 5;

%Changes tolerance from .01 default to user setting
ex.nPointsTolerance = p.nDataPointDeviationTolerance;

%Information for stage optimization
ex.optimizationInfo.algorithmType = 'max value';
ex.optimizationInfo.acquisitionType = 'pulse blaster';
ex.optimizationInfo.enableOptimization = p.optimizationEnabled;
ex.optimizationInfo.stageAxes = p.optimizationAxes;
ex.optimizationInfo.steps = p.optimizationSteps;
ex.optimizationInfo.timePerPoint = p.timePerOpimizationPoint;
ex.optimizationInfo.timeBetweenOptimizations = p.timeBetweenOptimizations;
if isempty(p.timeBetweenOptimizations) || p.timeBetweenOptimizations == Inf
   ex.optimizationInfo.useTimer = false;
else
   ex.optimizationInfo.useTimer = true;
end
ex.optimizationInfo.percentageToForceOptimization = p.percentageForcedOptimization;
if isempty(p.percentageForcedOptimization) || p.percentageForcedOptimization == 0
   ex.optimizationInfo.usePercentageDifference = false;
else
   ex.optimizationInfo.usePercentageDifference = true;
end
ex.optimizationInfo.needNewValue = true;
ex.optimizationInfo.lastOptimizationTime = [];
ex.optimizationInfo.postOptimizationValue = 0;
ex.optimizationInfo.rfStatus = p.optimizationRFStatus;

ex.maxFailedCollections = p.maxFailedCollections;

%Sends information to command window
scanStartInfo(ex.scan.nSteps,ex.pulseBlaster.sequenceDurations.sent.totalSeconds + ex.forcedCollectionPauseTime*1.5,p.nIterations,.28)

%Asks for user input on whether to continue
cont = checkContinue(p.timeoutDuration*2);
if ~cont
    return
end

%Runs scan
ex = runScan(ex,p);
