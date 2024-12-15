function ex = Random_Scanning_Using_Rabi(ex,p)

requiredParams = {'scanBounds','scanStepSize','collectionType','RFFrequency','pulseNotes'};

mustContainField(p,requiredParams)

paramsWithDefaults = {'plotAverageContrast',true;...
   'plotAverageReference',true;...
   'plotCurrentContrast',true;...
   'plotCurrentReference',true;...
   'AOMCompensation',0;...
   'RFReduction',0;...
   'RFAmplitude',10;...
   'collectionDuration',0;...%default overwritten with daq rate
   'collectionBufferDuration',1000;...
   'sequenceTimePerDataPoint',3;...
   'nIterations',1;...
   'timeoutDuration',10;...
   'forcedDelayTime',.125;...
   'nDataPointDeviationTolerance',.0002;...
   'baselineSubtraction',0;...
   'maxFailedCollections',3;...
   'optimizationEnabled',false;...
   'optimizationAxes',{'z'};...
   'optimizationSteps',{-2:.25:2};...
   'optimizationRFStatus','off';...
   'timePerOpimizationPoint',.1;...
   'timeBetweenOptimizations',180;...
   'percentageForcedOptimization',.75;...
   'perSecond',true;...
   'pulseBlasterConfig','pulse_blaster_default';...
   'SRSRFConfig','SRS_RF';...
   'DAQConfig','daq_6361';...
   'stageConfig','PI_stage'};

p = mustContainField(p,paramsWithDefaults(:,1),paramsWithDefaults(:,2));

%See ODMR example script for instrument loading information
warning('off','MATLAB:subscripting:noSubscriptsSpecified');

%Creates experiment object if none exists
if ~exist('ex','var') || isempty(ex),ex = []; end

%Loads pulse blaster, srs rf, and daq with given configs
instrumentNames = ["pulse blaster","srs rf","daq"];
instrumentConfigs = [c2s(p.pulseBlasterConfig),c2s(p.SRSRFConfig),c2s(p.DAQConfig)];
ex = loadInstruments(ex,instrumentNames,instrumentConfigs,false);

%Loads stage if optimization is enabled
if p.optimizationEnabled
   ex = loadInstruments(ex,"stage",c2s(p.stageConfig),false);   
end

%Sets all optimization info into appropriate place in experiment object
ex.optimizationInfo.enableOptimization = p.optimizationEnabled;
ex.optimizationInfo.stageAxes = p.optimizationAxes;
ex.optimizationInfo.steps = p.optimizationSteps;
ex.optimizationInfo.timePerPoint = p.timePerOpimizationPoint;
ex.optimizationInfo.timeBetweenOptimizations = p.timeBetweenOptimizations;
ex.optimizationInfo.percentageToForceOptimization = p.percentageForcedOptimization;
ex.optimizationInfo.rfStatus = p.optimizationRFStatus;
ex.optimizationInfo.useTimer = p.useOptimizationTimer;
ex.optimizationInfo.usePercentageDifference = p.useOptimizationPercentage;

%Sends RF settings
ex.SRS_RF.enabled = 'on';
ex.SRS_RF.modulationEnabled = 'off';
ex.SRS_RF.amplitude = p.RFAmplitude;
ex.SRS_RF.frequency = p.RFFrequency;

%Sends DAQ settings
ex.DAQ.takeData = false;
ex.DAQ.differentiateSignal = 'on';
ex.DAQ.activeDataChannel = p.collectionType;

%Sets collectionDuration to inverse of sample rate in nanoseconds
if p.collectionDuration == 0
   p.collectionDuration = (1/ex.DAQ.sampleRate)*1e9;
end

%% Use template to create sequence and scan

%Load empty parameter structure from template
[parameters,~] = Rabi_template([],[]);

%Set parameters
%Leaves intermissionBufferDuration, collectionDuration, repolarizationDuration, and collectionBufferDuration as default
parameters.RFResonanceFrequency = p.RFFrequency;
parameters.tauStart = p.scanBounds(1);
parameters.tauEnd = p.scanBounds(2);
parameters.timePerDataPoint = p.sequenceTimePerDataPoint;
parameters.AOM_DAQCompensation = p.AOMCompensation;
parameters.collectionBufferDuration = p.collectionBufferDuration;
parameters.collectionDuration = p.collectionDuration;
parameters.tauStepSize = p.scanStepSize;
parameters.RFReduction = p.RFReduction;
parameters.repolarizationBuffer = 100;
parameters.extraBuffer = p.extraBuffer;
parameters.dataOnBuffer = p.dataOnBuffer;
parameters.intermissionBufferDuration = p.intermissionBufferDuration;

%Sends parameters to template
%Creates and sends pulse sequence to pulse blaster
%Gets scan information
[ex.pulseBlaster,scanInfo] = Rabi_template(ex.pulseBlaster,parameters);

%Deletes any pre-existing scan
ex.scan = [];
tauAddresses = scanInfo.address;

scanInfo.address = findPulses(ex.pulseBlaster,'notes',p.pulseNotes,'matches');
scanInfo.bounds = cell(1,numel(scanInfo.address));
[scanInfo.bounds{:}] = deal(p.scanBounds);
scanInfo.stepSize = ones(1,numel(scanInfo.address));
scanInfo.stepSize(:) = p.scanStepSize;
scanInfo.nSteps = [];
for ii = 1:numel(tauAddresses)
    ex.pulseBlaster = modifyPulse(ex.pulseBlaster,tauAddresses(ii),'duration',p.piTime+p.RFReduction);
end

%Adds scan to experiment based on template output
ex = addScans(ex,scanInfo);

%Adds time (in seconds) after pulse blaster has stopped running before continuing to execute code
ex.forcedCollectionPauseTime = p.forcedDelayTime;

%Changes tolerance from .01 default to user setting
ex.nPointsTolerance = p.nDataPointDeviationTolerance;

ex.maxFailedCollections = p.maxFailedCollections;

%Sends information to command window
scanStartInfo(ex.scan.nSteps,ex.pulseBlaster.sequenceDurations.sent.totalSeconds + ex.forcedCollectionPauseTime*1.5,p.nIterations,.28)

cont = checkContinue(p.timeoutDuration*2);
if ~cont
   return
end

%Runs scan
ex = runScan(ex,p);