function ex = Laser_Scan(ex,p)
%p is parameter structure

requiredParams = {'scanBounds','scanStepSize','collectionType','laserPropertyName'};

mustContainField(p,requiredParams)

paramsWithDefaults = {'parameterOfInterest','ref';...
   'plotAverageContrast',true;...
   'plotAverageReference',true;...
   'plotCurrentContrast',true;...
   'plotCurrentReference',true;...
   'plotCurrentPercentageDataPoints',false;...
   'plotAveragetPercentageDataPoints',false;...
   'plotAverageSNR',false;...
   'plotCurrentSNR',false;...
   'RFAmplitude',10;...
   'RFFrequency',2.87;...
   'scanNotes','Laser intensity scan';...
   'sequenceTimePerDataPoint',.2;...
   'nIterations',1;...
   'timeoutDuration',10;...
   'perSecond',true;...
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

%Loads pulse blaster and daq with given configs
instrumentNames = ["pulse blaster","daq",c2s(p.laserPropertyName)];
instrumentConfigs = [c2s(p.pulseBlasterConfig),c2s(p.DAQConfig),c2s(p.laserConfig)];
ex = loadInstruments(ex,instrumentNames,instrumentConfigs,false);

%Loads SRS if measuring contrast
if strcmpi(p.parameterOfInterest,'con')
   ex = loadInstruments(ex,"srs rf",c2s(p.SRSRFConfig),false);
   %Turns RF on, disables modulation, and sets amplitude and frequency
   ex.SRS_RF.enabled = 'on';
   ex.SRS_RF.modulationEnabled = 'off';
   ex.SRS_RF.amplitude = p.RFAmplitude;
   ex.SRS_RF.frequency = p.RFFrequency;
elseif ~strcmpi(p.parameterOfInterest,'ref')
   error('Parameter of interest must be ref or con')
end

ex.optimizationInfo.enableOptimization = p.optimizationEnabled;

%Loads stage if optimization is enabled
if p.optimizationEnabled
   ex = loadInstruments(ex,"stage",c2s(p.stageConfig),false);
end

%Temporarily disables taking data, set data channel, and turn signal differentiation on if needed
ex.DAQ.takeData = false;
ex.DAQ.activeDataChannel = p.collectionType;
if strcmpi(p.parameterOfInterest,'con')
   ex.DAQ.differentiateSignal = 'on';
else
   ex.DAQ.differentiateSignal = 'off';
   ex.DAQ.continuousCollection = true;
end

%Sets loops for entire sequence to "on". Deletes previous sequence if any existed
ex.pulseBlaster.nTotalLoops = 1;%will be overwritten later, used to find time for 1 loop
ex.pulseBlaster.useTotalLoop = true;
ex.pulseBlaster = deleteSequence(ex.pulseBlaster);

%Uses ODMR pulse sequence even if just getting contrast for the sake of simplicity. It just dumps signal data with
%reference instead of differentiating between the two

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

scan.bounds = p.scanBounds;
scan.stepSize = p.scanStepSize;
scan.parameter = 'set power'; %Scan set power of laser
scan.identifier = ex.(p.laserPropertyName).identifier; %Identifies which instrument will be altered
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

%Runs scan
ex = runScan(ex,p);
