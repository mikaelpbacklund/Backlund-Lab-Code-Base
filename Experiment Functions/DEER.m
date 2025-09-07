function ex = DEER(ex,p)

requiredParams = {'scanBounds','scanStepSize','collectionType','scanType','RF1ResonanceFrequency',...
   'tauTime','piTime','RF2Frequency','RF2Duration','nRF2Pulses'};

mustContainField(p,requiredParams)

paramsWithDefaults = {'plotAverageContrast',true;...
   'plotAverageReference',true;...
   'plotCurrentContrast',true;...
   'plotCurrentReference',true;...
   'plotCurrentPercentageDataPoints',false;...
   'plotAveragetPercentageDataPoints',false;...
   'plotAverageSNR',false;...
   'plotCurrentSNR',false;...
   'AOMCompensation',0;...
   'extraRF',0;...
   'RF1Amplitude',10;...
   'RF2Amplitude',11;...
   'collectionDuration',0;...%default overwritten with daq rate
   'collectionBufferDuration',1000;...
   'intermissionBufferDuration',2500;...
   'repolarizationDuration',7000;...
   'dataOnBuffer',0;...
   'extraBuffer',0;...
   'AOMCompensation',0;...
   'IQBuffers',[0 0];...
   'timePerDataPoint',3;...
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
   'pulseBlasterConfig','pulse_blaster_DEER';...
   'SRSRFConfig','SRS_RF';...
   'DAQConfig','daq_6361';...
   'stageConfig','PI_stage';...
   'windfreakConfig','windfreak_RF'};%this one

p = mustContainField(p,paramsWithDefaults(:,1),paramsWithDefaults(:,2));

%See ODMR example script for instrument loading information
warning('off','MATLAB:subscripting:noSubscriptsSpecified');

%Creates experiment object if none exists
if ~exist('ex','var') || isempty(ex),ex = []; end

%Loads pulse blaster, srs rf, and daq with given configs
% instrumentNames = ["pulse blaster","srs rf","daq"];
% instrumentConfigs = [c2s(p.pulseBlasterConfig),c2s(p.SRSRFConfig),c2s(p.DAQConfig)];
instrumentNames = ["pulse blaster","srs rf","daq","windfreak"];
instrumentConfigs = [c2s(p.pulseBlasterConfig),c2s(p.SRSRFConfig),c2s(p.DAQConfig),c2s(p.windfreakConfig)];
ex = loadInstruments(ex,instrumentNames,instrumentConfigs,false);

ex.optimizationInfo.enableOptimization = p.optimizationEnabled;

%Loads stage if optimization is enabled
if p.optimizationEnabled
   ex = loadInstruments(ex,"stage",c2s(p.stageConfig),false);
end

%Sends RF settings
ex.SRS_RF.enabled = 'on';
ex.SRS_RF.modulationEnabled = 'on';
ex.SRS_RF.modulationType = 'iq';
ex.SRS_RF.amplitude = p.RF1Amplitude;
ex.SRS_RF.frequency = p.RF1ResonanceFrequency;

ex.windfreak_RF.enabled = 'on';
ex.windfreak_RF.amplitude = p.RF2Amplitude;

%Sends DAQ settings
ex.DAQ.takeData = false;
ex.DAQ.differentiateSignal = 'on';
ex.DAQ.activeDataChannel = p.collectionType;

%Sets collectionDuration to inverse of sample rate in nanoseconds
if p.collectionDuration == 0
   p.collectionDuration = (1/ex.DAQ.sampleRate)*1e9;
end

%% Use template to create sequence and scan

%Changes scan info names based on frequency or duration
%Load empty parameter structure from template
if strcmpi(p.scanType,'frequency')
    p.frequencyStart = p.scanBounds(1);
    p.frequencyEnd = p.scanBounds(2);
    p.frequencyStepSize = p.scanStepSize;
    p.frequencyNSteps = [];
    [sentParams,~] = DEER_frequency_template([],[]);
else 
    p.RF2DurationStart = p.scanBounds(1);
    p.RF2DurationEnd = p.scanBounds(2);
    p.RF2DurationStepSize = p.scanStepSize;
    p.RF2DurationNSteps = [];
    [sentParams,~] = DEER_duration_template([],[]);
end

%Replaces values in sentParams with values in params if they aren't empty
for paramName = fieldnames(sentParams)'
   if isfield(p,paramName{1}) && ~isempty(p.(paramName{1}))
      sentParams.(paramName{1}) = p.(paramName{1});
   end
end

%Changes rf2 frequency if running duration scan (constant frequency)
if strcmpi(p.scanType,'duration')
    [ex.pulseBlaster,scanInfo] = DEER_duration_template(ex.pulseBlaster,sentParams);
    ex.windfreak_RF.frequency = scanInfo.RF2Frequency;
else
    [ex.pulseBlaster,scanInfo] = DEER_frequency_template(ex.pulseBlaster,sentParams);
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

%Deletes any pre-existing scan
ex.scan = [];

%Adds scan to experiment based on template output
ex = addScans(ex,scanInfo);

%Adds time (in seconds) after pulse blaster has stopped running before continuing to execute code
ex.forcedCollectionPauseTime = p.forcedDelayTime;

%Changes tolerance from .01 default to user setting
ex.nPointsTolerance = p.nDataPointDeviationTolerance;

ex.maxFailedCollections = p.maxFailedCollections;

%Runs scan
ex = runScan(ex,p);