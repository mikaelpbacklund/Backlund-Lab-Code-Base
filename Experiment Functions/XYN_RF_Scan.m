function ex = XYN_RF_Scan(ex,p)

requiredParams = {'scanBounds','collectionType','RFResonanceFrequency',...
   'tauTime','nXY','setsXYN'};

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
   'RFRampTime',0;...
   'RFAmplitude',10;...
   'collectionDuration',0;...%default overwritten with daq rate
   'collectionBufferDuration',1000;...
   'intermissionBufferDuration',1000;...
   'IQBuffers',[0 0];...
   'dataOnBuffer',0;...
   'extraBuffer',0;...
   'repolarizationDuration',7000;...
   'sequenceTimePerDataPoint',3;...
   'nIterations',1;...
   'boundsToUse',2;...%1st set is tau/2, second is tau
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
   'useOptimizationTimer',false;...
   'useOptimizationPercentage',false;...
   'pulseBlasterConfig','pulse_blaster_default';...
   'SRSRFConfig','SRS_RF';...
   'DAQConfig','daq_6361';...
   'stageConfig','PI_stage'};

p = mustContainField(p,paramsWithDefaults(:,1),paramsWithDefaults(:,2));

%Does not attempt to calculate scan values in template
p.templateScanCalculation = false;

%Change pi time input for template to mean of bounds
p.piTime = mean(p.scanBounds);

%Stores RF and compensating tau bounds for use later
RFBounds = p.scanBounds+p.RFRampTime;
RFBoundsByTwo = p.scanBounds/2 + p.RFRampTime;
tauBounds = p.tauTime - (sum(p.IQBuffers) + p.scanBounds + p.RFRampTime);
tauBoundsByTwo = p.tauTime/2 - (sum(p.IQBuffers) + (3/4)*p.scanBounds + p.RFRampTime);
p.scanBounds = [p.tauTime,p.tauTime];%Will be overwritten later regardless

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
   ex = loadInstruments(ex,"PIstage",c2s(p.stageConfig),false);   
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
ex.SRS_RF.modulationEnabled = 'on';
ex.SRS_RF.modulationType = 'iq';
ex.SRS_RF.amplitude = p.RFAmplitude;
ex.SRS_RF.frequency = p.RFResonanceFrequency;

%Sends DAQ settings
ex.DAQ.takeData = false;
ex.DAQ.differentiateSignal = 'on';
ex.DAQ.activeDataChannel = p.collectionType;

%Sets collectionDuration to inverse of sample rate in nanoseconds
if p.collectionDuration == 0
   p.collectionDuration = (1/ex.DAQ.sampleRate)*1e9;
end

%Load empty parameter structure from template
[sentParams,~] = XYn_m_template([],[]);

%Replaces values in sentParams with values in params if they aren't empty
for paramName = fieldnames(sentParams)'
   if isfield(p,paramName{1}) && ~isempty(p.(paramName{1}))
      sentParams.(paramName{1}) = p.(paramName{1});
   end
end

%Sends parameters to template
%Creates and sends pulse sequence to pulse blaster
%Gets scan information
ex.pulseBlaster = XYn_m_template(ex.pulseBlaster,sentParams);

%Find RF pulses which will be scanned
RFScans = findPulses(ex.pulseBlaster,'notes','π','contains');
nRF = numel(RFScans);

%Find tau pulses which will be scanned inverse to RF pulse to keep consistent tau
TauScans = findPulses(ex.pulseBlaster,'notes','π','contains');
nTau = numel(TauScans);

%Finds pulses designated as π or τ which will be scanned
scanInfo.address = [RFScans TauScans];

%Set bounds for RF, RF/2, tau, and tau/2 scans
for ii = 1:nRF
   scanInfo.bounds{ii} = RFBounds;
end
for ii = [1,nRF/2,nRF/2+1,nRF]
    scanInfo.bounds{ii} = RFBoundsByTwo;
end
for ii = nRF+1:numel(scanInfo.address)
   scanInfo.bounds{ii} = tauBounds;
end
for ii = [nRF+1,nRF + nTau/2,nRF+nTau/2+1,numel(scanInfo.address)]
    scanInfo.bounds{ii} = tauBoundsByTwo;
end

scanInfo.nSteps = p.scanNSteps;
scanInfo.parameter = 'duration';
scanInfo.identifier = 'Pulse Blaster';
scanInfo.notes = sprintf('XY%d-%d (tau: %d, RF: %.3f GHz)',p.nXY,p.setsXYN,round(p.tauTime),p.RFResonanceFrequency);
scanInfo.RFFrequency = p.RFResonanceFrequency;

%Adds x offset to account for extra pulses, swaps bounds to plot to be tau
p.xOffset = scanInfo.reducedTauTime;
p.boundsToUse = 2;

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
end