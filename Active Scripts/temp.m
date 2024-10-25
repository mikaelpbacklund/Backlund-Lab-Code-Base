%i/q buffer not subtracting from previous
%AOM/DAQ does not have aom on
clear


%%
scanType = 'duration';%Either frequency or duration
params.RF2Frequency = .452;%GHz. Overwritten by scan if frequency selected
params.RF2Duration = 100;%ns. Overwritten by scan if duration selected
params.nRF2Pulses = 2;%1 for centered on pi pulse, 2 for during tau
params.RF1ResonanceFrequency = 2.4185;
params.piTime = 130;
params.tauTime = 300;
scanStart = 20;%ns or GHz
scanEnd = 300;%ns or GHz
scanStepSize = 10;%ns or GHz

%All parameters below this are optional in that they will revert to defaults if not specified
scanNSteps = [];%will override step size
params.timePerDataPoint = 10;%seconds
params.collectionDuration = 800;
params.collectionBufferDuration = 1000;
params.intermissionBufferDuration = 2500;
params.repolarizationDuration = 7000;
params.extraRF =  6;
params.AOM_DAQCompensation = -100;
params.IQPreBufferDuration = 22;
params.IQPostBufferDuration = 5;
nIterations = 10;
SRSAmplitude = 10;
windfreakAmplitude = 19;
dataType = 'counter';
timeoutDuration = 10;
forcedDelayTime = .25;
nDataPointDeviationTolerance = .2;

%%
if ~exist('ex','var'),  ex = experiment; end

if isempty(ex.pulseBlaster)
   ex.pulseBlaster = pulse_blaster('pulse_blaster_DEER');
   ex.pulseBlaster = connect(ex.pulseBlaster);
end

%%

if strcmpi(scanType,'frequency')
    params.frequencyStart = scanStart;
    params.frequencyEnd = scanEnd;
    params.frequencyStepSize = scanStepSize;
    params.frequencyNSteps = scanNSteps;
    [sentParams,~] = DEER_frequency_template([],[]);
else 
    params.RF2DurationStart = scanStart; %#ok<*UNRCH>
    params.RF2DurationEnd = scanEnd;
    params.RF2DurationStepSize = scanStepSize;
    params.RF2DurationNSteps = scanNSteps;
    [sentParams,~] = DEER_duration_template([],[]);
end

%Replaces values in sentParams with values in params if they aren't empty
for paramName = fieldnames(sentParams)'
   if ~isempty(params.(paramName{1}))
      sentParams.(paramName{1}) = params.(paramName{1});
   end
end

%%
%Changes rf2 frequency if running duration scan (constant frequency)
if strcmpi(scanType,'duration')
    [ex.pulseBlaster,scanInfo] = DEER_duration_template(ex.pulseBlaster,sentParams);
    % ex.windfreak_RF.frequency = scanInfo.RF2Frequency;
else
    [ex.pulseBlaster,scanInfo] = DEER_frequency_template(ex.pulseBlaster,sentParams);
end
%%
%Deletes any pre-existing scan
ex.scan = [];

%Adds scan to experiment based on template output
ex = addScans(ex,scanInfo);